#!/bin/bash

VERSION="v0.18.2"

ADDITIONAL_FLAGS="--dangerously-skip-permissions --output-format stream-json --verbose"

NOTES_FILE="SHARED_TASK_NOTES.md"
AUTO_UPDATE=false
DISABLE_UPDATES=false

PROMPT_JQ_INSTALL="Please install jq for JSON parsing"

PROMPT_COMMIT_MESSAGE="Please review all uncommitted changes in the git repository (both modified and new files). Write a commit message with: (1) a short one-line summary, (2) two newlines, (3) then a detailed explanation. Do not include any footers or metadata like 'Generated with Claude Code' or 'Co-Authored-By'. Feel free to look at the last few commits to get a sense of the commit message style for consistency. First run 'git add .' to stage all changes including new untracked files, then commit using 'git commit -m \"your message\"' (don't push, just commit, no need to ask for confirmation)."

PROMPT_WORKFLOW_CONTEXT="## CONTINUOUS WORKFLOW CONTEXT

This is part of a continuous development loop where work happens incrementally across multiple iterations. You might run once, then a human developer might make changes, then you run again, and so on. This could happen daily or on any schedule.

**Important**: You don't need to complete the entire goal in one iteration. Just make meaningful progress on one thing, then leave clear notes for the next iteration (human or AI). Think of it as a relay race where you're passing the baton.

**Do NOT commit or push changes** - The automation will handle committing and pushing your changes after you finish. Just focus on making the code changes.

**Project Completion Signal**: If you determine that not just your current task but the ENTIRE project goal is fully complete (nothing more to be done on the overall goal), only include the exact phrase \"COMPLETION_SIGNAL_PLACEHOLDER\" in your response. Only use this when absolutely certain that the whole project is finished, not just your individual task. We will stop working on this project when multiple developers independently determine that the project is complete.

## PRIMARY GOAL"

PROMPT_NOTES_UPDATE_EXISTING="Update the \`$NOTES_FILE\` file with relevant context for the next iteration. Add new notes and remove outdated information to keep it current and useful."

PROMPT_NOTES_CREATE_NEW="Create a \`$NOTES_FILE\` file with relevant context and instructions for the next iteration."

PROMPT_NOTES_GUIDELINES="

This file helps coordinate work across iterations (both human and AI developers). It should:

- Contain relevant context and instructions for the next iteration
- Stay concise and actionable (like a notes file, not a detailed report)
- Help the next developer understand what to do next

The file should NOT include:
- Lists of completed work or full reports
- Information that can be discovered by running tests/coverage
- Unnecessary details"

PROMPT_REVIEWER_CONTEXT="## CODE REVIEW CONTEXT

You are performing a review pass on changes just made by another developer. This is NOT a new feature implementation - you are reviewing and validating existing changes using the instructions given below by the user. Feel free to use git commands to see what changes were made if it's helpful to you.

**Do NOT commit or push changes** - The automation will handle committing and pushing your changes after you finish. Just focus on validating and fixing any issues."

PROMPT_CI_FIX_CONTEXT="## CI FAILURE FIX CONTEXT

You are analyzing and fixing a CI/CD failure for a pull request.

**Your task:**
1. Inspect the failed CI workflow using the commands below
2. Analyze the error logs to understand what went wrong
3. Make the necessary code changes to fix the issue
4. Stage and commit your changes (they will be pushed to update the PR)

**Commands to inspect CI failures:**
- \`gh run list --status failure --limit 3\` - List recent failed runs
- \`gh run view <RUN_ID> --log-failed\` - View failed job logs (shorter output)
- \`gh run view <RUN_ID> --log\` - View full logs for a specific run

**Important:**
- Focus only on fixing the CI failure, not adding new features
- Make minimal changes necessary to pass CI
- If the failure seems unfixable (e.g., flaky test, infrastructure issue), explain why in your response"

PROMPT=""
MAX_RUNS=""
MAX_COST=""
MAX_DURATION=""
ENABLE_COMMITS=true
DISABLE_BRANCHES=false
GIT_BRANCH_PREFIX="continuous-claude/"
MERGE_STRATEGY="squash"
GITHUB_OWNER=""
GITHUB_REPO=""
WORKTREE_NAME=""
WORKTREE_BASE_DIR="../continuous-claude-worktrees"
CLEANUP_WORKTREE=false
LIST_WORKTREES=false
DRY_RUN=false
COMPLETION_SIGNAL="CONTINUOUS_CLAUDE_PROJECT_COMPLETE"
COMPLETION_THRESHOLD=3
ERROR_LOG=""
error_count=0
extra_iterations=0
successful_iterations=0
total_cost=0
completion_signal_count=0
i=1
EXTRA_CLAUDE_FLAGS=()
REVIEW_PROMPT=""
start_time=""
CI_RETRY_ENABLED=true
CI_RETRY_MAX_ATTEMPTS=1

parse_duration() {
    # Parse a duration string like "2h", "30m", "1h30m", "90s" to seconds
    # Returns: number of seconds, or empty string on error
    local duration_str="$1"
    
    # Remove all whitespace
    duration_str=$(echo "$duration_str" | tr -d '[:space:]')
    
    if [ -z "$duration_str" ]; then
        return 1
    fi
    
    local total_seconds=0
    local remaining="$duration_str"
    
    # Parse hours (e.g., "2h" or "2H")
    if [[ "$remaining" =~ ([0-9]+)[hH] ]]; then
        local hours="${BASH_REMATCH[1]}"
        total_seconds=$((total_seconds + hours * 3600))
        remaining="${remaining/${BASH_REMATCH[0]}/}"
    fi
    
    # Parse minutes (e.g., "30m" or "30M")
    if [[ "$remaining" =~ ([0-9]+)[mM] ]]; then
        local minutes="${BASH_REMATCH[1]}"
        total_seconds=$((total_seconds + minutes * 60))
        remaining="${remaining/${BASH_REMATCH[0]}/}"
    fi
    
    # Parse seconds (e.g., "45s" or "45S")
    if [[ "$remaining" =~ ([0-9]+)[sS] ]]; then
        local seconds="${BASH_REMATCH[1]}"
        total_seconds=$((total_seconds + seconds))
        remaining="${remaining/${BASH_REMATCH[0]}/}"
    fi
    
    # Check if anything unparsed remains (invalid format)
    if [ -n "$remaining" ]; then
        return 1
    fi
    
    # Must have parsed at least something
    if [ $total_seconds -eq 0 ]; then
        return 1
    fi
    
    echo "$total_seconds"
    return 0
}

format_duration() {
    # Format seconds into a human-readable duration string
    local seconds="$1"
    
    if [ -z "$seconds" ] || [ "$seconds" -eq 0 ]; then
        echo "0s"
        return
    fi
    
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    
    local result=""
    if [ $hours -gt 0 ]; then
        result="${hours}h"
    fi
    if [ $minutes -gt 0 ]; then
        result="${result}${minutes}m"
    fi
    if [ $secs -gt 0 ] || [ -z "$result" ]; then
        result="${result}${secs}s"
    fi
    
    echo "$result"
}

show_help() {
    cat << EOF
Continuous Claude - Run Claude Code iteratively with automatic PR management

USAGE:
    continuous-claude -p "prompt" (-m max-runs | --max-cost max-cost | --max-duration duration) [--owner owner] [--repo repo] [options]
    continuous-claude update

REQUIRED OPTIONS:
    -p, --prompt <text>           The prompt/goal for Claude Code to work on
    -m, --max-runs <number>       Maximum number of successful iterations (use 0 for unlimited with --max-cost or --max-duration)
    --max-cost <dollars>          Maximum cost in USD to spend (alternative to --max-runs)
    --max-duration <duration>     Maximum duration to run (e.g., "2h", "30m", "1h30m") (alternative to --max-runs)

OPTIONAL FLAGS:
    -h, --help                    Show this help message
    -v, --version                 Show version information
    --owner <owner>               GitHub repository owner (auto-detected from git remote if not provided)
    --repo <repo>                 GitHub repository name (auto-detected from git remote if not provided)
    --disable-commits             Disable automatic commits and PR creation
    --disable-branches            Commit on current branch without creating branches or PRs
    --auto-update                 Automatically install updates when available
    --disable-updates             Skip all update checks and prompts
    --git-branch-prefix <prefix>  Branch prefix for iterations (default: "continuous-claude/")
    --merge-strategy <strategy>   PR merge strategy: squash, merge, or rebase (default: "squash")
    --notes-file <file>           Shared notes file for iteration context (default: "SHARED_TASK_NOTES.md")
    --worktree <name>             Run in a git worktree for parallel execution (creates if needed)
    --worktree-base-dir <path>    Base directory for worktrees (default: "../continuous-claude-worktrees")
    --cleanup-worktree            Remove worktree after completion
    --cleanup-worktree            Remove worktree after completion
    --list-worktrees              List all active git worktrees and exit
    --dry-run                     Simulate execution without making changes
    --completion-signal <phrase>  Phrase that agents output when project is complete (default: "CONTINUOUS_CLAUDE_PROJECT_COMPLETE")
    --completion-threshold <num>  Number of consecutive signals to stop early (default: 3)
    -r, --review-prompt <text>    Run a reviewer pass after each iteration to validate changes
                                  (e.g., run build/lint/tests and fix any issues)
    --disable-ci-retry            Disable automatic CI failure retry (enabled by default)
    --ci-retry-max <number>       Maximum CI fix attempts per PR (default: 1)

COMMANDS:
    update                        Check for and install the latest version

EXAMPLES:
    # Run 5 iterations to fix bugs
    continuous-claude -p "Fix all linter errors" -m 5 --owner myuser --repo myproject

    # Run with cost limit
    continuous-claude -p "Add tests" --max-cost 10.00 --owner myuser --repo myproject

    # Run for a maximum duration (time-boxed)
    continuous-claude -p "Add documentation" --max-duration 2h --owner myuser --repo myproject
    
    # Run for 30 minutes
    continuous-claude -p "Refactor module" --max-duration 30m --owner myuser --repo myproject

    # Run without commits (testing mode)
    continuous-claude -p "Refactor code" -m 3 --disable-commits

    # Run with commits on current branch (no branches or PRs)
    continuous-claude -p "Quick fixes" -m 3 --disable-branches

    # Use custom branch prefix and merge strategy
    continuous-claude -p "Feature work" -m 10 --owner myuser --repo myproject \\
        --git-branch-prefix "ai/" --merge-strategy merge

    # Combine duration and cost limits (whichever comes first)
    continuous-claude -p "Add tests" --max-duration 1h30m --max-cost 5.00 --owner myuser --repo myproject

    # Run in a worktree for parallel execution
    continuous-claude -p "Add unit tests" -m 5 --owner myuser --repo myproject --worktree instance-1

    # Run multiple instances in parallel (in different terminals)
    continuous-claude -p "Task A" -m 5 --owner myuser --repo myproject --worktree task-a
    continuous-claude -p "Task B" -m 5 --owner myuser --repo myproject --worktree task-b

    # List all active worktrees
    continuous-claude --list-worktrees

    # Clean up worktree after completion
    continuous-claude -p "Quick fix" -m 1 --owner myuser --repo myproject \\
        --worktree temp --cleanup-worktree

    # Use completion signal to stop early when project is done
    continuous-claude -p "Add unit tests to all files" -m 50 --owner myuser --repo myproject \\
        --completion-threshold 3

    # Use a reviewer to validate and fix changes after each iteration
    continuous-claude -p "Add new feature" -m 5 --owner myuser --repo myproject \\
        -r "Run npm test and npm run lint, fix any failures"

    # Allow up to 2 CI fix attempts per PR (default is 1)
    continuous-claude -p "Add tests" -m 5 --owner myuser --repo myproject --ci-retry-max 2

    # Disable automatic CI failure retry
    continuous-claude -p "Add tests" -m 5 --owner myuser --repo myproject --disable-ci-retry

    # Check for and install updates
    continuous-claude update

REQUIREMENTS:
    - Claude Code CLI (https://claude.ai/code)
    - GitHub CLI (gh) - authenticated with 'gh auth login'
    - jq - JSON parsing utility
    - Git repository (unless --disable-commits is used)
    
NOTE:
    continuous-claude automatically checks for updates at startup. You can press 'N' to skip the update.

For more information, visit: https://github.com/AnandChowdhary/continuous-claude
EOF
}

show_version() {
    echo "continuous-claude version $VERSION"
}

get_latest_version() {
    # Fetch the latest release version from GitHub using gh CLI
    local latest_version
    if ! command -v gh &> /dev/null; then
        return 1
    fi
    
    latest_version=$(gh release view --repo AnandChowdhary/continuous-claude --json tagName --jq '.tagName' 2>/dev/null)
    if [ -z "$latest_version" ]; then
        return 1
    fi
    
    echo "$latest_version"
    return 0
}

compare_versions() {
    # Compare two version strings (e.g., "v0.9.1" and "v0.10.0")
    # Returns 0 if they're equal, 1 if first is older, 2 if first is newer
    local ver1="$1"
    local ver2="$2"
    
    # Remove 'v' prefix if present
    ver1="${ver1#v}"
    ver2="${ver2#v}"
    
    # Remove any pre-release suffix (e.g., -beta, -rc1) for simple comparison
    ver1="${ver1%%-*}"
    ver2="${ver2%%-*}"
    
    if [ "$ver1" = "$ver2" ]; then
        return 0
    fi
    
    # Split versions and compare using safer array creation
    local IFS=.
    local i ver1_arr ver2_arr
    read -ra ver1_arr <<< "$ver1"
    read -ra ver2_arr <<< "$ver2"
    
    # Fill empty positions with zeros
    for ((i=${#ver1_arr[@]}; i<${#ver2_arr[@]}; i++)); do
        ver1_arr[i]=0
    done
    for ((i=${#ver2_arr[@]}; i<${#ver1_arr[@]}; i++)); do
        ver2_arr[i]=0
    done
    
    # Compare each component, fallback to string comparison if non-numeric
    for ((i=0; i<${#ver1_arr[@]}; i++)); do
        local c1="${ver1_arr[i]}"
        local c2="${ver2_arr[i]}"
        if [[ "$c1" =~ ^[0-9]+$ ]] && [[ "$c2" =~ ^[0-9]+$ ]]; then
            if ((10#$c1 < 10#$c2)); then
                return 1
            fi
            if ((10#$c1 > 10#$c2)); then
                return 2
            fi
        else
            # Fallback: string comparison for non-numeric components
            if [[ "$c1" < "$c2" ]]; then
                return 1
            fi
            if [[ "$c1" > "$c2" ]]; then
                return 2
            fi
        fi
    done
    
    return 0
}

get_script_path() {
    # Get the absolute path to the current script
    local script_path
    script_path=$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")
    echo "$script_path"
}

download_and_install_update() {
    local latest_version="$1"
    local script_path="$2"
    
    echo "📥 Downloading version $latest_version..." >&2
    
    # Download the new version to a temporary file
    local temp_file=$(mktemp)
    # Use the specific release tag instead of main branch
    local download_url="https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/${latest_version}/continuous_claude.sh"
    local checksum_url="https://raw.githubusercontent.com/AnandChowdhary/continuous-claude/${latest_version}/continuous_claude.sh.sha256"
    if ! curl -fsSL "$download_url" -o "$temp_file"; then
        echo "❌ Failed to download update" >&2
        rm -f "$temp_file"
        return 1
    fi
    
    # Download the checksum file
    local checksum_file=$(mktemp)
    if ! curl -fsSL "$checksum_url" -o "$checksum_file"; then
        echo "❌ Failed to download checksum file" >&2
        rm -f "$temp_file" "$checksum_file"
        return 1
    fi
    
    # Verify checksum
    local expected_checksum
    expected_checksum=$(cat "$checksum_file" | awk '{print $1}')
    local actual_checksum
    actual_checksum=$(sha256sum "$temp_file" | awk '{print $1}')
    if [ "$expected_checksum" != "$actual_checksum" ]; then
        echo "❌ Checksum verification failed! Update aborted." >&2
        rm -f "$temp_file" "$checksum_file"
        return 1
    fi
    rm -f "$checksum_file"
    
    # Verify the downloaded file is valid bash
    if ! bash -n "$temp_file" 2>/dev/null; then
        echo "❌ Downloaded file has invalid syntax" >&2
        rm -f "$temp_file"
        return 1
    fi
    
    # Make it executable
    chmod +x "$temp_file"
    
    # Replace the current script
    if ! mv "$temp_file" "$script_path"; then
        echo "❌ Failed to replace script (permission denied?)" >&2
        rm -f "$temp_file"
        return 1
    fi
    
    echo "✅ Updated to version $latest_version" >&2
    return 0
}

check_for_updates() {
    local skip_prompt="$1"
    
    if [ "$DISABLE_UPDATES" = "true" ]; then
        return 0
    fi

    # Get the latest version
    local latest_version
    if ! latest_version=$(get_latest_version); then
        # Silently fail if we can't check for updates
        return 0
    fi
    
    # Compare versions
    compare_versions "$VERSION" "$latest_version"
    local comparison=$?
    
    if [ $comparison -eq 1 ]; then
        # Current version is older
        echo "" >&2
        echo "🆕 A new version of continuous-claude is available: $latest_version (current: $VERSION)" >&2
        
        if [ "$skip_prompt" = "true" ]; then
            return 0
        fi
        
        local response
        if [ "$AUTO_UPDATE" = "true" ]; then
            response="y"
        else
            echo -n "Would you like to update now? [y/N] " >&2
            if ! read -t 60 -r response; then
                echo "" >&2
                echo "⏱️  No response received within 60 seconds, skipping update." >&2
                response="n"
            fi
        fi

        if [[ "$response" =~ ^[Yy]$ ]]; then
            local script_path=$(get_script_path)
            
            if download_and_install_update "$latest_version" "$script_path"; then
                echo "🔄 Restarting with new version..." >&2
                # Restart the script with the original arguments
                # This happens early in startup before main application logic runs
                exec "$script_path" "$@"
            else
                echo "⚠️  Update failed. Continuing with current version." >&2
            fi
        else
            echo "⏭️  Skipping update. You can update later with: continuous-claude update" >&2
        fi
    fi
    
    return 0
}

handle_update_command() {
    if [ "$DISABLE_UPDATES" = "true" ]; then
        echo "⚠️  Updates are disabled via --disable-updates flag. Skipping." >&2
        exit 0
    fi

    echo "🔍 Checking for updates..." >&2
    
    local latest_version
    if ! latest_version=$(get_latest_version); then
        echo "❌ Failed to check for updates. Make sure 'gh' CLI is installed and authenticated." >&2
        exit 1
    fi
    
    compare_versions "$VERSION" "$latest_version"
    local comparison=$?
    
    if [ $comparison -eq 0 ]; then
        echo "✅ You're already on the latest version ($VERSION)" >&2
        exit 0
    elif [ $comparison -eq 2 ]; then
        echo "ℹ️  You're on a newer version ($VERSION) than the latest release ($latest_version)" >&2
        exit 0
    fi
    
    # Current version is older
    echo "🆕 New version available: $latest_version (current: $VERSION)" >&2

    local response
    if [ "$AUTO_UPDATE" = "true" ]; then
        response="y"
    else
        echo -n "Would you like to update now? [y/N] " >&2
        if ! read -t 60 -r response; then
            echo "" >&2
            echo "⏱️  No response received within 60 seconds, skipping update." >&2
            response="n"
        fi
    fi

    if [[ "$response" =~ ^[Yy]$ ]]; then
        local script_path=$(get_script_path)
        
        if download_and_install_update "$latest_version" "$script_path"; then
            echo "✅ Update complete! Version $latest_version is now installed." >&2
            exit 0
        else
            echo "❌ Update failed." >&2
            exit 1
        fi
    else
        echo "⏭️  Update cancelled." >&2
        exit 0
    fi
}

detect_github_repo() {
    # Try to detect GitHub owner and repo from git remote
    # Returns: "owner repo" on success, empty string on failure
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        return 1
    fi
    
    # Try to get the origin remote URL
    local remote_url
    if ! remote_url=$(git remote get-url origin 2>/dev/null); then
        return 1
    fi
    
    # Parse GitHub URL (supports both HTTPS and SSH formats)
    # HTTPS: https://github.com/owner/repo.git or https://github.com/owner/repo
    # SSH: git@github.com:owner/repo.git or git@github.com:owner/repo
    local owner=""
    local repo=""
    
    if [[ "$remote_url" =~ ^https://github\.com/([^/]+)/([^/]+)$ ]]; then
        # HTTPS format
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
    elif [[ "$remote_url" =~ ^git@github\.com:([^/]+)/([^/]+)$ ]]; then
        # SSH format
        owner="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
    else
        return 1
    fi
    
    # Remove .git suffix if present
    repo="${repo%.git}"
    
    # Validate that we got both owner and repo
    if [ -z "$owner" ] || [ -z "$repo" ]; then
        return 1
    fi
    
    echo "$owner $repo"
    return 0
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -p|--prompt)
                PROMPT="$2"
                shift 2
                ;;
            -m|--max-runs)
                MAX_RUNS="$2"
                shift 2
                ;;
            --max-cost)
                MAX_COST="$2"
                shift 2
                ;;
            --max-duration)
                MAX_DURATION="$2"
                shift 2
                ;;
            --git-branch-prefix)
                GIT_BRANCH_PREFIX="$2"
                shift 2
                ;;
            --merge-strategy)
                MERGE_STRATEGY="$2"
                shift 2
                ;;
            --owner)
                GITHUB_OWNER="$2"
                shift 2
                ;;
            --repo)
                GITHUB_REPO="$2"
                shift 2
                ;;
            --disable-commits)
                ENABLE_COMMITS=false
                shift
                ;;
            --disable-branches)
                DISABLE_BRANCHES=true
                shift
                ;;
            --auto-update)
                AUTO_UPDATE=true
                shift
                ;;
            --disable-updates)
                DISABLE_UPDATES=true
                shift
                ;;
            --notes-file)
                NOTES_FILE="$2"
                shift 2
                ;;
            --worktree)
                WORKTREE_NAME="$2"
                shift 2
                ;;
            --worktree-base-dir)
                WORKTREE_BASE_DIR="$2"
                shift 2
                ;;
            --cleanup-worktree)
                CLEANUP_WORKTREE=true
                shift
                ;;
            --list-worktrees)
                LIST_WORKTREES=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --completion-signal)
                COMPLETION_SIGNAL="$2"
                shift 2
                ;;
            --completion-threshold)
                COMPLETION_THRESHOLD="$2"
                shift 2
                ;;
            -r|--review-prompt)
                REVIEW_PROMPT="$2"
                shift 2
                ;;
            --disable-ci-retry)
                CI_RETRY_ENABLED=false
                shift
                ;;
            --ci-retry-max)
                CI_RETRY_MAX_ATTEMPTS="$2"
                shift 2
                ;;
            *)
                # Collect unknown flags to forward to claude
                EXTRA_CLAUDE_FLAGS+=("$1")
                shift
                ;;
        esac
    done
}

parse_update_flags() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --auto-update)
                AUTO_UPDATE=true
                shift
                ;;
            --disable-updates)
                DISABLE_UPDATES=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "❌ Unknown flag for update command: $1" >&2
                exit 1
                ;;
        esac
    done
}

validate_arguments() {
    if [ -z "$PROMPT" ]; then
        echo "❌ Error: Prompt is required. Use -p to provide a prompt." >&2
        echo "Run '$0 --help' for usage information." >&2
        exit 1
    fi

    if [ -z "$MAX_RUNS" ] && [ -z "$MAX_COST" ] && [ -z "$MAX_DURATION" ]; then
        echo "❌ Error: Either --max-runs, --max-cost, or --max-duration is required." >&2
        echo "Run '$0 --help' for usage information." >&2
        exit 1
    fi

    if [ -n "$MAX_RUNS" ] && ! [[ "$MAX_RUNS" =~ ^[0-9]+$ ]]; then
        echo "❌ Error: --max-runs must be a non-negative integer" >&2
        exit 1
    fi

    if [ -n "$MAX_COST" ]; then
        if ! [[ "$MAX_COST" =~ ^[0-9]+\.?[0-9]*$ ]] || [ "$(awk "BEGIN {print ($MAX_COST <= 0)}")" = "1" ]; then
            echo "❌ Error: --max-cost must be a positive number" >&2
            exit 1
        fi
    fi

    if [ -n "$MAX_DURATION" ]; then
        local duration_seconds
        if ! duration_seconds=$(parse_duration "$MAX_DURATION"); then
            echo "❌ Error: --max-duration must be a valid duration (e.g., '2h', '30m', '1h30m', '90s')" >&2
            exit 1
        fi
        # Store parsed duration in seconds back to MAX_DURATION for later use
        MAX_DURATION="$duration_seconds"
    fi

    if [[ ! "$MERGE_STRATEGY" =~ ^(squash|merge|rebase)$ ]]; then
        echo "❌ Error: --merge-strategy must be one of: squash, merge, rebase" >&2
        exit 1
    fi

    if [ -n "$COMPLETION_THRESHOLD" ]; then
        if ! [[ "$COMPLETION_THRESHOLD" =~ ^[0-9]+$ ]] || [ "$COMPLETION_THRESHOLD" -lt 1 ]; then
            echo "❌ Error: --completion-threshold must be a positive integer" >&2
            exit 1
        fi
    fi

    if [ -n "$CI_RETRY_MAX_ATTEMPTS" ]; then
        if ! [[ "$CI_RETRY_MAX_ATTEMPTS" =~ ^[0-9]+$ ]] || [ "$CI_RETRY_MAX_ATTEMPTS" -lt 1 ]; then
            echo "❌ Error: --ci-retry-max must be a positive integer" >&2
            exit 1
        fi
    fi

    # Only require GitHub info if commits are enabled
    if [ "$ENABLE_COMMITS" = "true" ]; then
        # Auto-detect owner and repo if not provided
        if [ -z "$GITHUB_OWNER" ] || [ -z "$GITHUB_REPO" ]; then
            local detected_info
            if detected_info=$(detect_github_repo); then
                # Parse the detected owner and repo
                local detected_owner=$(echo "$detected_info" | awk '{print $1}')
                local detected_repo=$(echo "$detected_info" | awk '{print $2}')
                
                # Only use detected values if not already provided
                if [ -z "$GITHUB_OWNER" ]; then
                    GITHUB_OWNER="$detected_owner"
                fi
                if [ -z "$GITHUB_REPO" ]; then
                    GITHUB_REPO="$detected_repo"
                fi
            fi
        fi
        
        # After detection attempt, verify both are set
        if [ -z "$GITHUB_OWNER" ]; then
            echo "❌ Error: GitHub owner is required. Use --owner to provide the owner, or run from a git repository with a GitHub remote." >&2
            echo "Run '$0 --help' for usage information." >&2
            exit 1
        fi

        if [ -z "$GITHUB_REPO" ]; then
            echo "❌ Error: GitHub repo is required. Use --repo to provide the repo, or run from a git repository with a GitHub remote." >&2
            echo "Run '$0 --help' for usage information." >&2
            exit 1
        fi
    fi
}

validate_requirements() {
    if ! command -v claude &> /dev/null; then
        echo "❌ Error: Claude Code is not installed: https://claude.ai/code" >&2
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        echo "⚠️ jq is required for JSON parsing but is not installed. Asking Claude Code to install it..." >&2
        claude -p "$PROMPT_JQ_INSTALL" --allowedTools "Bash,Read"
        if ! command -v jq &> /dev/null; then
            echo "❌ Error: jq is still not installed after Claude Code attempt." >&2
            exit 1
        fi
    fi

    # Only check for GitHub CLI if commits are enabled
    if [ "$ENABLE_COMMITS" = "true" ]; then
        if ! command -v gh &> /dev/null; then
            echo "❌ Error: GitHub CLI (gh) is not installed: https://cli.github.com" >&2
            exit 1
        fi

        if ! gh auth status >/dev/null 2>&1; then
            echo "❌ Error: GitHub CLI is not authenticated. Run 'gh auth login' first." >&2
            exit 1
        fi
    fi
}

wait_for_pr_checks() {
    local pr_number="$1"
    local owner="$2"
    local repo="$3"
    local iteration_display="$4"
    local max_iterations=180  # 180 * 10 seconds = 30 minutes
    local iteration=0

    local prev_check_count=""
    local prev_success_count=""
    local prev_pending_count=""
    local prev_failed_count=""
    local prev_review_status=""
    local prev_no_checks_configured=""
    local waiting_message_printed=false

    while [ $iteration -lt $max_iterations ]; do
        local checks_json
        local no_checks_configured=false
        if ! checks_json=$(gh pr checks "$pr_number" --repo "$owner/$repo" --json state,bucket 2>&1); then
            if echo "$checks_json" | grep -q "no checks"; then
                no_checks_configured=true
                checks_json="[]"
            else
                echo "⚠️  $iteration_display Failed to get PR checks status: $checks_json" >&2
                return 1
            fi
        fi

        local check_count=$(echo "$checks_json" | jq 'length' 2>/dev/null || echo "0")
        
        local all_completed=true
        local all_success=true
        
        if [ "$no_checks_configured" = "false" ] && [ "$check_count" -eq 0 ]; then
            all_completed=false
        fi

        local pending_count=0
        local success_count=0
        local failed_count=0
        
        if [ "$check_count" -gt 0 ]; then
            local idx=0
            while [ $idx -lt $check_count ]; do
                local state=$(echo "$checks_json" | jq -r ".[$idx].state")
                local bucket=$(echo "$checks_json" | jq -r ".[$idx].bucket // \"pending\"")

                if [ "$bucket" = "pending" ] || [ "$bucket" = "null" ]; then
                    all_completed=false
                    pending_count=$((pending_count + 1))
                elif [ "$bucket" = "fail" ]; then
                    all_success=false
                    failed_count=$((failed_count + 1))
                else
                    success_count=$((success_count + 1))
                fi

                idx=$((idx + 1))
            done
        fi

        local pr_info
        if ! pr_info=$(gh pr view "$pr_number" --repo "$owner/$repo" --json reviewDecision,reviewRequests 2>&1); then
            echo "⚠️  $iteration_display Failed to get PR review status: $pr_info" >&2
            return 1
        fi

        local review_decision=$(echo "$pr_info" | jq -r 'if .reviewDecision == "" then "null" else (.reviewDecision // "null") end')
        local review_requests_count=$(echo "$pr_info" | jq '.reviewRequests | length' 2>/dev/null || echo "0")
        
        local reviews_pending=false
        if [ "$review_decision" = "REVIEW_REQUIRED" ] || [ "$review_requests_count" -gt 0 ]; then
            reviews_pending=true
        fi
        
        local review_status="None"
        if [ -n "$review_decision" ] && [ "$review_decision" != "null" ]; then
            review_status="$review_decision"
        elif [ "$review_requests_count" -gt 0 ]; then
            review_status="$review_requests_count review(s) requested"
        fi
        
        # Check if anything changed
        local state_changed=false
        if [ "$check_count" != "$prev_check_count" ] || \
           [ "$success_count" != "$prev_success_count" ] || \
           [ "$pending_count" != "$prev_pending_count" ] || \
           [ "$failed_count" != "$prev_failed_count" ] || \
           [ "$review_status" != "$prev_review_status" ] || \
           [ "$no_checks_configured" != "$prev_no_checks_configured" ] || \
           [ -z "$prev_check_count" ]; then
            state_changed=true
        fi
        
        # Only log if state changed
        if [ "$state_changed" = "true" ]; then
            echo "" >&2
            echo "🔍 $iteration_display Checking PR status (iteration $((iteration + 1))/$max_iterations)..." >&2
            
            if [ "$no_checks_configured" = "true" ]; then
                echo "   📊 No checks configured" >&2
            else
                echo "   📊 Found $check_count check(s)" >&2
            fi
            
            if [ "$check_count" -gt 0 ]; then
                echo "   🟢 $success_count    🟡 $pending_count    🔴 $failed_count" >&2
            fi
            
            echo "   👁️  Review status: $review_status" >&2
            
            # Update previous state
            prev_check_count="$check_count"
            prev_success_count="$success_count"
            prev_pending_count="$pending_count"
            prev_failed_count="$failed_count"
            prev_review_status="$review_status"
            prev_no_checks_configured="$no_checks_configured"
        fi

        if [ "$check_count" -eq 0 ] && [ "$checks_json" = "[]" ] && [ "$no_checks_configured" = "false" ]; then
            if [ "$iteration" -lt 18 ]; then
                if [ "$waiting_message_printed" = "false" ]; then
                    echo -n "⏳ Waiting for checks to start... (will timeout after 3 minutes) " >&2
                    waiting_message_printed=true
                fi
                echo -n "." >&2
                sleep 10
                iteration=$((iteration + 1))
                continue
            else
                echo "" >&2
                echo "   ⚠️  No checks found after waiting, proceeding without checks" >&2
                all_completed=true
                all_success=true
            fi
        else
            # If we were waiting and now checks are found, print newline
            if [ "$waiting_message_printed" = "true" ]; then
                echo "" >&2
            fi
            # Reset waiting message flag when checks are found
            waiting_message_printed=false
        fi

        if [ "$all_completed" = "true" ] && [ "$all_success" = "true" ] && [ "$reviews_pending" = "false" ]; then
            # Only merge if: review is APPROVED, or no review was ever requested (null + no review requests)
            if [ "$review_decision" = "APPROVED" ]; then
                echo "✅ $iteration_display All PR checks and reviews passed" >&2
                return 0
            elif { [ "$review_decision" = "null" ] || [ -z "$review_decision" ]; } && [ "$review_requests_count" -eq 0 ]; then
                echo "✅ $iteration_display All PR checks and reviews passed" >&2
                return 0
            fi
        fi
        
        if [ "$all_completed" = "true" ] && [ "$all_success" = "true" ] && [ "$reviews_pending" = "true" ]; then
            if [ "$state_changed" = "true" ]; then
                echo "   ✅ All checks passed, but waiting for review..." >&2
            fi
        fi

        if [ "$all_completed" = "true" ] && [ "$all_success" = "false" ]; then
            echo "❌ $iteration_display PR checks failed" >&2
            return 1
        fi

        if [ "$review_decision" = "CHANGES_REQUESTED" ]; then
            echo "❌ $iteration_display PR has changes requested in review" >&2
            return 1
        fi

        local waiting_items=()
        
        if [ "$all_completed" = "false" ]; then
            waiting_items+=("checks to complete")
        fi
        
        if [ "$reviews_pending" = "true" ]; then
            waiting_items+=("code review")
        fi
        
        if [ ${#waiting_items[@]} -gt 0 ] && [ "$state_changed" = "true" ]; then
            echo "⏳ Waiting for: ${waiting_items[*]}" >&2
        fi

        sleep 10
        iteration=$((iteration + 1))
    done

    echo "⏱️  $iteration_display Timeout waiting for PR checks and reviews (30 minutes)" >&2
    return 1
}

get_failed_run_id() {
    local pr_number="$1"
    local owner="$2"
    local repo="$3"

    # Get the most recent failed workflow run for this PR's head SHA
    local head_sha
    head_sha=$(gh pr view "$pr_number" --repo "$owner/$repo" --json headRefOid --jq '.headRefOid' 2>/dev/null)

    if [ -z "$head_sha" ]; then
        return 1
    fi

    # Get failed runs for this commit
    local run_id
    run_id=$(gh run list --repo "$owner/$repo" --commit "$head_sha" --status failure --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null)

    if [ -z "$run_id" ] || [ "$run_id" = "null" ]; then
        return 1
    fi

    echo "$run_id"
    return 0
}

merge_pr_and_cleanup() {
    local pr_number="$1"
    local owner="$2"
    local repo="$3"
    local branch_name="$4"
    local iteration_display="$5"
    local current_branch="$6"

    echo "🔄 $iteration_display Updating branch with latest from main..." >&2
    local update_output
    if update_output=$(gh pr update-branch "$pr_number" --repo "$owner/$repo" 2>&1); then
        echo "📥 $iteration_display Branch updated, re-checking PR status..." >&2
        if ! wait_for_pr_checks "$pr_number" "$owner" "$repo" "$iteration_display"; then
            echo "❌ $iteration_display PR checks failed after branch update" >&2
            return 1
        fi
    else
        # Check if update failed due to conflicts or just because branch is already up-to-date
        if echo "$update_output" | grep -qi "already up-to-date\|is up to date"; then
            echo "✅ $iteration_display Branch already up-to-date" >&2
        else
            echo "⚠️  $iteration_display Branch update failed: $update_output" >&2
            return 1
        fi
    fi

    # Map merge strategy to gh pr merge flag
    local merge_flag=""
    case "$MERGE_STRATEGY" in
        squash)
            merge_flag="--squash"
            ;;
        merge)
            merge_flag="--merge"
            ;;
        rebase)
            merge_flag="--rebase"
            ;;
    esac

    echo "🔀 $iteration_display Merging PR #$pr_number with strategy: $MERGE_STRATEGY..." >&2
    if ! gh pr merge "$pr_number" --repo "$owner/$repo" $merge_flag >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to merge PR (may have conflicts or be blocked)" >&2
        return 1
    fi

    echo "📥 $iteration_display Pulling latest from main..." >&2
    if ! git checkout "$current_branch" >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to checkout $current_branch" >&2
        return 1
    fi

    if ! git pull origin "$current_branch" >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to pull from $current_branch" >&2
        return 1
    fi

    echo "🗑️  $iteration_display Deleting local branch: $branch_name" >&2
    git branch -d "$branch_name" >/dev/null 2>&1 || true

    return 0
}

create_iteration_branch() {
    local iteration_display="$1"
    local iteration_num="$2"
    
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo ""
        return 0
    fi

    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    
    if [[ "$current_branch" == ${GIT_BRANCH_PREFIX}* ]]; then
        echo "⚠️  $iteration_display Already on iteration branch: $current_branch" >&2
        git checkout main >/dev/null 2>&1 || return 1
        current_branch="main"
    fi
    
    local date_str=$(date +%Y-%m-%d)
    
    local random_hash
    if command -v openssl >/dev/null 2>&1; then
        random_hash=$(openssl rand -hex 4)
    elif [ -r /dev/urandom ]; then
        random_hash=$(LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 8)
    else
        random_hash=$(printf "%x" $(($(date +%s) % 100000000)))$(printf "%x" $$)
        random_hash=${random_hash:0:8}
    fi
    
    local branch_name="${GIT_BRANCH_PREFIX}iteration-${iteration_num}/${date_str}-${random_hash}"
    
    echo "🌿 $iteration_display Creating branch: $branch_name" >&2
    
    if [ "$DRY_RUN" = "true" ]; then
        echo "   (DRY RUN) Would create branch $branch_name" >&2
        echo "$branch_name"
        return 0
    fi
    
    if ! git checkout -b "$branch_name" >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to create branch" >&2
        echo ""
        return 1
    fi
    
    echo "$branch_name"
    return 0
}

continuous_claude_commit() {
    local iteration_display="$1"
    local branch_name="$2"
    local main_branch="$3"
    
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        return 0
    fi

    # Check for any changes: modified tracked files, staged changes, or new untracked files
    # Note: --ignore-submodules=dirty to not treat dirty submodules as changes
    local has_changes=false
    if ! git diff --quiet --ignore-submodules=dirty || ! git diff --cached --quiet --ignore-submodules=dirty; then
        has_changes=true
    fi
    
    # Also check for untracked files (excluding ignored files)
    if [ -z "$(git ls-files --others --exclude-standard)" ]; then
        : # no untracked files
    else
        has_changes=true
    fi
    
    if [ "$has_changes" = "false" ]; then
        echo "🫙 $iteration_display No changes detected, cleaning up branch..." >&2
        git checkout "$main_branch" >/dev/null 2>&1
        git branch -D "$branch_name" >/dev/null 2>&1 || true
        return 0
    fi
    
    if [ "$DRY_RUN" = "true" ]; then
        echo "💬 $iteration_display (DRY RUN) Would commit changes..." >&2
        echo "📦 $iteration_display (DRY RUN) Changes committed on branch: $branch_name" >&2
        echo "📤 $iteration_display (DRY RUN) Would push branch..." >&2
        echo "🔨 $iteration_display (DRY RUN) Would create pull request..." >&2
        echo "✅ $iteration_display (DRY RUN) PR merged: <commit title would appear here>" >&2
        return 0
    fi
    
    echo "💬 $iteration_display Committing changes..." >&2
    
    if ! claude -p "$PROMPT_COMMIT_MESSAGE" --allowedTools "Bash(git)" --dangerously-skip-permissions >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to commit changes" >&2
        git checkout "$main_branch" >/dev/null 2>&1
        return 1
    fi

    # Verify all changes (including untracked files) were committed
    # Note: --ignore-submodules=dirty allows continuing when submodules have uncommitted content
    if ! git diff --quiet --ignore-submodules=dirty || ! git diff --cached --quiet --ignore-submodules=dirty || [ -n "$(git ls-files --others --exclude-standard)" ]; then
        echo "⚠️  $iteration_display Commit command ran but changes still present (uncommitted or untracked files remain)" >&2
        git checkout "$main_branch" >/dev/null 2>&1
        return 1
    fi

    echo "📦 $iteration_display Changes committed on branch: $branch_name" >&2

    local commit_message=$(git log -1 --format="%B" "$branch_name")
    local commit_title=$(echo "$commit_message" | head -n 1)
    local commit_body=$(echo "$commit_message" | tail -n +4)

    echo "📤 $iteration_display Pushing branch..." >&2
    if ! git push -u origin "$branch_name" >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to push branch" >&2
        git checkout "$main_branch" >/dev/null 2>&1
        return 1
    fi

    echo "🔨 $iteration_display Creating pull request..." >&2
    local pr_output
    if ! pr_output=$(gh pr create --repo "$GITHUB_OWNER/$GITHUB_REPO" --title "$commit_title" --body "$commit_body" --base "$main_branch" 2>&1); then
        echo "⚠️  $iteration_display Failed to create PR: $pr_output" >&2
        git checkout "$main_branch" >/dev/null 2>&1
        return 1
    fi

    local pr_number=$(echo "$pr_output" | grep -oE '(pull/|#)[0-9]+' | grep -oE '[0-9]+' | head -n 1)
    if [ -z "$pr_number" ]; then
        echo "⚠️  $iteration_display Failed to extract PR number from: $pr_output" >&2
        git checkout "$main_branch" >/dev/null 2>&1
        return 1
    fi

    echo "🔍 $iteration_display PR #$pr_number created, waiting 5 seconds for GitHub to set up..." >&2
    sleep 5
    if ! wait_for_pr_checks "$pr_number" "$GITHUB_OWNER" "$GITHUB_REPO" "$iteration_display"; then
        # CI checks failed - attempt retry if enabled
        if [ "$CI_RETRY_ENABLED" = "true" ]; then
            echo "🔧 $iteration_display CI checks failed, attempting automatic fix..." >&2
            if attempt_ci_fix_and_recheck "$pr_number" "$GITHUB_OWNER" "$GITHUB_REPO" "$branch_name" "$iteration_display" "$main_branch" "$ERROR_LOG"; then
                echo "🎉 $iteration_display CI fix successful!" >&2
                # Continue to merge
            else
                # CI fix failed, close PR as before
                echo "⚠️  $iteration_display CI fix unsuccessful, closing PR and deleting remote branch..." >&2
                gh pr close "$pr_number" --repo "$GITHUB_OWNER/$GITHUB_REPO" --delete-branch >/dev/null 2>&1 || true
                echo "🗑️  $iteration_display Cleaning up local branch: $branch_name" >&2
                git checkout "$main_branch" >/dev/null 2>&1
                git branch -D "$branch_name" >/dev/null 2>&1 || true
                return 1
            fi
        else
            # Original behavior - close PR immediately
            echo "⚠️  $iteration_display PR checks failed or timed out, closing PR and deleting remote branch..." >&2
            gh pr close "$pr_number" --repo "$GITHUB_OWNER/$GITHUB_REPO" --delete-branch >/dev/null 2>&1 || true
            echo "🗑️  $iteration_display Cleaning up local branch: $branch_name" >&2
            git checkout "$main_branch" >/dev/null 2>&1
            git branch -D "$branch_name" >/dev/null 2>&1 || true
            return 1
        fi
    fi

    if ! merge_pr_and_cleanup "$pr_number" "$GITHUB_OWNER" "$GITHUB_REPO" "$branch_name" "$iteration_display" "$main_branch"; then
        # Check if PR is still open before closing (might have been merged but cleanup failed)
        local pr_state=$(gh pr view "$pr_number" --repo "$GITHUB_OWNER/$GITHUB_REPO" --json state --jq '.state' 2>/dev/null || echo "UNKNOWN")
        if [ "$pr_state" = "OPEN" ]; then
            echo "⚠️  $iteration_display Failed to merge PR, closing it and deleting remote branch..." >&2
            gh pr close "$pr_number" --repo "$GITHUB_OWNER/$GITHUB_REPO" --delete-branch >/dev/null 2>&1 || true
        else
            echo "⚠️  $iteration_display PR was merged but cleanup failed" >&2
        fi
        echo "🗑️  $iteration_display Cleaning up local branch: $branch_name" >&2
        git checkout "$main_branch" >/dev/null 2>&1
        git branch -D "$branch_name" >/dev/null 2>&1 || true
        return 1
    fi

    echo "✅ $iteration_display PR #$pr_number merged: $commit_title" >&2
    
    # Ensure we're back on the main branch
    if ! git checkout "$main_branch" >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to checkout $main_branch" >&2
        return 1
    fi
    
    return 0
}

commit_on_current_branch() {
    local iteration_display="$1"

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        return 0
    fi

    # Check for any changes: modified tracked files, staged changes, or new untracked files
    # Note: --ignore-submodules=dirty to not treat dirty submodules as changes
    local has_changes=false
    if ! git diff --quiet --ignore-submodules=dirty || ! git diff --cached --quiet --ignore-submodules=dirty; then
        has_changes=true
    fi

    # Also check for untracked files (excluding ignored files)
    if [ -n "$(git ls-files --others --exclude-standard)" ]; then
        has_changes=true
    fi

    if [ "$has_changes" = "false" ]; then
        echo "ℹ️  $iteration_display No changes to commit" >&2
        return 0
    fi

    if [ "$DRY_RUN" = "true" ]; then
        echo "💬 $iteration_display (DRY RUN) Would commit changes on current branch..." >&2
        return 0
    fi

    echo "💬 $iteration_display Committing changes on current branch..." >&2

    if ! claude -p "$PROMPT_COMMIT_MESSAGE" --allowedTools "Bash(git)" --dangerously-skip-permissions >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to commit changes" >&2
        return 1
    fi

    # Verify all changes were committed
    # Note: --ignore-submodules=dirty allows continuing when submodules have uncommitted content
    if ! git diff --quiet --ignore-submodules=dirty || ! git diff --cached --quiet --ignore-submodules=dirty || [ -n "$(git ls-files --others --exclude-standard)" ]; then
        echo "⚠️  $iteration_display Commit command ran but changes still present" >&2
        return 1
    fi

    local commit_title=$(git log -1 --format="%s")
    echo "✅ $iteration_display Committed: $commit_title" >&2
    return 0
}

list_worktrees() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "❌ Error: Not in a git repository" >&2
        exit 1
    fi

    echo "📋 Active Git Worktrees:"
    echo ""
    
    if ! git worktree list 2>/dev/null; then
        echo "❌ Error: Failed to list worktrees" >&2
        exit 1
    fi
    
    exit 0
}

setup_worktree() {
    if [ -z "$WORKTREE_NAME" ]; then
        # No worktree specified, work in current directory
        return 0
    fi
    
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "❌ Error: Not in a git repository. Worktrees require a git repository." >&2
        exit 1
    fi
    
    # Get the main repo directory
    local main_repo_dir=$(git rev-parse --show-toplevel)
    local worktree_path="${WORKTREE_BASE_DIR}/${WORKTREE_NAME}"
    
    # Make worktree path absolute if it's relative
    if [[ "$worktree_path" != /* ]]; then
        worktree_path="${main_repo_dir}/${worktree_path}"
    fi
    
    # Get current branch (usually main or master)
    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    
    # Check if worktree already exists
    if [ -d "$worktree_path" ]; then
        echo "🌿 Worktree '$WORKTREE_NAME' already exists at: $worktree_path" >&2
        echo "📂 Switching to worktree directory..." >&2
        
        if ! cd "$worktree_path"; then
            echo "❌ Error: Failed to change to worktree directory: $worktree_path" >&2
            exit 1
        fi
        
        echo "📥 Pulling latest changes from $current_branch..." >&2
        if ! git pull origin "$current_branch" >/dev/null 2>&1; then
            echo "⚠️  Warning: Failed to pull latest changes (continuing anyway)" >&2
        fi
    else
        echo "🌿 Creating new worktree '$WORKTREE_NAME' at: $worktree_path" >&2
        
        # Create base directory if it doesn't exist
        local base_dir=$(dirname "$worktree_path")
        if [ ! -d "$base_dir" ]; then
            mkdir -p "$base_dir" || {
                echo "❌ Error: Failed to create worktree base directory: $base_dir" >&2
                exit 1
            }
        fi
        
        # Create the worktree
        if ! git worktree add "$worktree_path" "$current_branch" 2>&1; then
            echo "❌ Error: Failed to create worktree" >&2
            exit 1
        fi
        
        echo "📂 Switching to worktree directory..." >&2
        if ! cd "$worktree_path"; then
            echo "❌ Error: Failed to change to worktree directory: $worktree_path" >&2
            exit 1
        fi
    fi
    
    echo "✅ Worktree '$WORKTREE_NAME' ready at: $worktree_path" >&2
    return 0
}

cleanup_worktree() {
    if [ -z "$WORKTREE_NAME" ] || [ "$CLEANUP_WORKTREE" = "false" ]; then
        return 0
    fi
    
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        return 0
    fi
    
    local worktree_path="${WORKTREE_BASE_DIR}/${WORKTREE_NAME}"
    
    # Get the main repo directory to make path absolute
    local main_repo_dir=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$main_repo_dir" ]; then
        if [[ "$worktree_path" != /* ]]; then
            worktree_path="${main_repo_dir}/${worktree_path}"
        fi
    fi
    
    echo "" >&2
    echo "🗑️  Cleaning up worktree '$WORKTREE_NAME'..." >&2
    
    # Try to find the main repo
    local current_dir=$(pwd)
    local git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
    
    if [ -n "$git_common_dir" ]; then
        local main_repo=$(dirname "$git_common_dir")
        if [ -d "$main_repo" ]; then
            cd "$main_repo" 2>/dev/null || true
        fi
    fi
    
    # Remove the worktree
    if git worktree remove "$worktree_path" --force 2>/dev/null; then
        echo "✅ Worktree removed successfully" >&2
    else
        echo "⚠️  Warning: Failed to remove worktree (may need manual cleanup)" >&2
        echo "   You can manually remove it with: git worktree remove $worktree_path --force" >&2
    fi
}

get_iteration_display() {
    local iteration_num=$1
    local max_runs=$2
    local extra_iters=$3
    
    if [ $max_runs -eq 0 ]; then
        echo "($iteration_num)"
    else
        local total=$((max_runs + extra_iters))
        echo "($iteration_num/$total)"
    fi
}

run_claude_iteration() {
    local prompt="$1"
    local flags="$2"
    local error_log="$3"
    local iteration_display="$4"

    if [ "$DRY_RUN" = "true" ]; then
        echo "🤖 (DRY RUN) Would run Claude Code with prompt: $prompt" >&2
        echo "📝 (DRY RUN) Output: This is a simulated response from Claude Code." > "$error_log"
        return 0
    fi

    # Run claude and capture both stdout and stderr
    # Use temporary files for both to ensure synchronous capture
    local temp_stdout=$(mktemp)
    local temp_stderr=$(mktemp)
    local exit_code=0

    # Stream stdout (stream-json) to terminal in human-readable format while capturing raw JSON
    # Filter extracts text from assistant messages for display
    set -o pipefail
    claude -p "$prompt" $flags "${EXTRA_CLAUDE_FLAGS[@]}" 2> >(tee "$temp_stderr" >&2) | \
        tee "$temp_stdout" | \
        while IFS= read -r line; do
            # Extract text from assistant messages for human-readable display
            text=$(echo "$line" | jq -r '
                if .type == "assistant" then
                    .message.content[]? | select(.type == "text") | .text // empty
                elif .type == "result" then
                    empty
                else
                    empty
                end
            ' 2>/dev/null)
            if [ -n "$text" ]; then
                # Indent each line with the iteration prefix
                echo "$text" | while IFS= read -r output_line; do
                    printf "   %s %s\n" "$iteration_display" "$output_line" >&2
                done
            fi
        done
    exit_code=${PIPESTATUS[0]}
    set +o pipefail

    # Wait for background processes to complete
    wait

    # Output captured stdout (JSON result) so caller can capture it
    if [ -f "$temp_stdout" ] && [ -s "$temp_stdout" ]; then
        cat "$temp_stdout"
    fi

    # Save stderr to error log (already displayed in real-time via tee)
    if [ -f "$temp_stderr" ] && [ -s "$temp_stderr" ]; then
        cat "$temp_stderr" > "$error_log"
    fi
    
    # If claude failed, check for error info in both stderr and stdout (JSON)
    if [ $exit_code -ne 0 ]; then
        # If stderr is empty, try to extract error from JSON stdout
        if [ ! -s "$error_log" ] && [ -f "$temp_stdout" ] && [ -s "$temp_stdout" ]; then
            # Check if stdout contains JSON with error info (stream-json format)
            local json_error=$(cat "$temp_stdout" | jq -s -r '.[-1] | if .is_error == true then .result // .error // "Unknown error" else empty end' 2>/dev/null || echo "")
            if [ -n "$json_error" ]; then
                echo "$json_error" > "$error_log"
                echo "$json_error" >&2
            fi
        fi
        
        # If still no error info, provide fallback message
        if [ ! -s "$error_log" ]; then
            {
                echo "Claude Code exited with code $exit_code but produced no error output"
                echo ""
                echo "This usually means:"
                echo "  - Claude Code crashed or failed to start"
                echo "  - An authentication or permission issue occurred"
                echo "  - The command arguments are invalid"
                echo ""
                echo "Try running this command directly to see the full error:"
                echo "  claude -p \"$prompt\" $flags ${EXTRA_CLAUDE_FLAGS[*]}"
            } >> "$error_log"
        fi
        
        # Cleanup temp files after error handling
        rm -f "$temp_stdout" "$temp_stderr"
        return $exit_code
    fi
    
    # Cleanup temp files on success
    rm -f "$temp_stdout" "$temp_stderr"

    return 0
}

run_reviewer_iteration() {
    local iteration_display="$1"
    local review_prompt="$2"
    local error_log="$3"

    echo "🔍 $iteration_display Running reviewer pass..." >&2

    # Build the reviewer prompt with context
    local full_reviewer_prompt="${PROMPT_REVIEWER_CONTEXT}

## USER REVIEW INSTRUCTIONS

${review_prompt}"

    # Run Claude with the reviewer prompt
    local result
    local claude_exit_code=0
    result=$(run_claude_iteration "$full_reviewer_prompt" "$ADDITIONAL_FLAGS" "$error_log" "$iteration_display") || claude_exit_code=$?

    if [ $claude_exit_code -ne 0 ]; then
        echo "❌ $iteration_display Reviewer pass failed with exit code: $claude_exit_code" >&2
        return 1
    fi

    # Parse and validate the result
    local parse_result=$(parse_claude_result "$result")
    if [ "$?" != "0" ]; then
        echo "❌ $iteration_display Reviewer pass returned error: $parse_result" >&2
        return 1
    fi

    # Extract and accumulate cost from reviewer (stream-json format)
    local reviewer_cost=$(echo "$result" | jq -s -r '.[-1].total_cost_usd // empty')
    if [ -n "$reviewer_cost" ]; then
        printf "💰 $iteration_display Reviewer cost: \$%.3f\n" "$reviewer_cost" >&2
        total_cost=$(awk "BEGIN {printf \"%.3f\", $total_cost + $reviewer_cost}")
        printf "   Running total: \$%.3f\n" "$total_cost" >&2
    fi

    echo "✅ $iteration_display Reviewer pass completed" >&2
    return 0
}

run_ci_fix_iteration() {
    local iteration_display="$1"
    local pr_number="$2"
    local owner="$3"
    local repo="$4"
    local branch_name="$5"
    local error_log="$6"
    local retry_attempt="$7"

    echo "🔧 $iteration_display Attempting to fix CI failure (attempt $retry_attempt/$CI_RETRY_MAX_ATTEMPTS)..." >&2

    # Get the failed run ID for context
    local failed_run_id
    failed_run_id=$(get_failed_run_id "$pr_number" "$owner" "$repo")

    # Build the CI fix prompt
    local ci_fix_prompt="${PROMPT_CI_FIX_CONTEXT}

## CURRENT CONTEXT

- Repository: $owner/$repo
- PR Number: #$pr_number
- Branch: $branch_name"

    if [ -n "$failed_run_id" ]; then
        ci_fix_prompt+="
- Failed Run ID: $failed_run_id (use this with \`gh run view $failed_run_id --log-failed\`)"
    fi

    ci_fix_prompt+="

## INSTRUCTIONS

1. Start by running \`gh run list --status failure --limit 3\` to see recent failures
2. Then use \`gh run view <RUN_ID> --log-failed\` to see the error details
3. Analyze what went wrong and fix it
4. After making changes, stage and commit them with a clear commit message describing the fix"

    # Run Claude with the CI fix prompt
    local result
    local claude_exit_code=0
    result=$(run_claude_iteration "$ci_fix_prompt" "$ADDITIONAL_FLAGS" "$error_log" "$iteration_display") || claude_exit_code=$?

    if [ $claude_exit_code -ne 0 ]; then
        echo "❌ $iteration_display CI fix attempt failed with exit code: $claude_exit_code" >&2
        return 1
    fi

    # Parse and validate the result
    local parse_result=$(parse_claude_result "$result")
    if [ "$?" != "0" ]; then
        echo "❌ $iteration_display CI fix returned error: $parse_result" >&2
        return 1
    fi

    # Extract and accumulate cost from CI fix (stream-json format)
    local fix_cost=$(echo "$result" | jq -s -r '.[-1].total_cost_usd // empty')
    if [ -n "$fix_cost" ]; then
        printf "💰 $iteration_display CI fix cost: \$%.3f\n" "$fix_cost" >&2
        total_cost=$(awk "BEGIN {printf \"%.3f\", $total_cost + $fix_cost}")
        printf "   Running total: \$%.3f\n" "$total_cost" >&2
    fi

    # Check if there are any changes to commit/push
    local has_changes=false
    if ! git diff --quiet || ! git diff --cached --quiet; then
        has_changes=true
    fi
    if [ -n "$(git ls-files --others --exclude-standard)" ]; then
        has_changes=true
    fi

    if [ "$has_changes" = "false" ]; then
        echo "⚠️  $iteration_display CI fix made no changes" >&2
        return 1
    fi

    # Check if changes are already committed
    local uncommitted_changes=false
    if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
        uncommitted_changes=true
    fi

    if [ "$uncommitted_changes" = "true" ]; then
        # Commit the fix using the same commit prompt pattern
        echo "💬 $iteration_display Committing CI fix..." >&2
        if ! claude -p "$PROMPT_COMMIT_MESSAGE" --allowedTools "Bash(git)" --dangerously-skip-permissions >/dev/null 2>&1; then
            echo "⚠️  $iteration_display Failed to commit CI fix" >&2
            return 1
        fi
    fi

    # Push the fix to update the PR
    echo "📤 $iteration_display Pushing CI fix to branch..." >&2
    if ! git push origin "$branch_name" >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to push CI fix" >&2
        return 1
    fi

    echo "✅ $iteration_display CI fix pushed, waiting for new checks..." >&2
    return 0
}

attempt_ci_fix_and_recheck() {
    local pr_number="$1"
    local owner="$2"
    local repo="$3"
    local branch_name="$4"
    local iteration_display="$5"
    local main_branch="$6"
    local error_log="$7"

    local retry_attempt=1

    while [ $retry_attempt -le $CI_RETRY_MAX_ATTEMPTS ]; do
        # Run CI fix iteration
        if ! run_ci_fix_iteration "$iteration_display" "$pr_number" "$owner" "$repo" "$branch_name" "$error_log" "$retry_attempt"; then
            echo "⚠️  $iteration_display CI fix attempt $retry_attempt failed" >&2
            retry_attempt=$((retry_attempt + 1))
            continue
        fi

        # Wait a bit for GitHub to register the new push
        sleep 5

        # Wait for new CI checks
        echo "🔍 $iteration_display Waiting for CI checks after fix..." >&2
        if wait_for_pr_checks "$pr_number" "$owner" "$repo" "$iteration_display"; then
            echo "✅ $iteration_display CI checks passed after fix!" >&2
            return 0
        fi

        echo "⚠️  $iteration_display CI still failing after fix attempt $retry_attempt" >&2
        retry_attempt=$((retry_attempt + 1))
    done

    echo "❌ $iteration_display All CI fix attempts exhausted" >&2
    return 1
}

parse_claude_result() {
    local result="$1"
    
    # For stream-json format: validate by slurping and checking last element
    if ! echo "$result" | jq -s -e '.[-1]' >/dev/null 2>&1; then
        echo "invalid_json"
        return 1
    fi

    local is_error=$(echo "$result" | jq -s -r '.[-1].is_error // false')
    if [ "$is_error" = "true" ]; then
        echo "claude_error"
        return 1
    fi
    
    echo "success"
    return 0
}

handle_iteration_error() {
    local iteration_display="$1"
    local error_type="$2"
    local error_output="$3"
    
    error_count=$((error_count + 1))
    extra_iterations=$((extra_iterations + 1))
    
    case "$error_type" in
        "exit_code")
            echo "" >&2
            echo "❌ $iteration_display Error occurred ($error_count consecutive errors):" >&2
            echo "" >&2
            if [ -f "$ERROR_LOG" ] && [ -s "$ERROR_LOG" ]; then
                echo "Error details:" >&2
                cat "$ERROR_LOG" >&2
            else
                echo "No error details captured in log file" >&2
                echo "Error log path: $ERROR_LOG" >&2
            fi
            echo "" >&2
            ;;
        "invalid_json")
            echo "" >&2
            echo "❌ $iteration_display Error: Invalid JSON response ($error_count consecutive errors):" >&2
            echo "" >&2
            echo "$error_output" >&2
            echo "" >&2
            ;;
        "claude_error")
            echo "" >&2
            echo "❌ $iteration_display Error in Claude Code response ($error_count consecutive errors):" >&2
            echo "" >&2
            echo "$error_output" | jq -s -r '.[-1].result // .[-1] // empty' >&2
            echo "" >&2
            ;;
    esac
    
    if [ $error_count -ge 3 ]; then
        echo "❌ Fatal: 3 consecutive errors occurred. Exiting." >&2
        exit 1
    fi
    
    return 1
}

handle_iteration_success() {
    local iteration_display="$1"
    local result="$2"
    local branch_name="$3"
    local main_branch="$4"
    
    # For stream-json format: slurp newline-delimited JSON and get result from last object
    # (Output already displayed in real-time via streaming)
    local result_text=$(echo "$result" | jq -s -r '.[-1].result // empty')

    # Check for completion signal in the output
    if [ -n "$result_text" ] && [[ "$result_text" == *"$COMPLETION_SIGNAL"* ]]; then
        completion_signal_count=$((completion_signal_count + 1))
        echo "" >&2
        echo "🎯 $iteration_display Completion signal detected ($completion_signal_count/$COMPLETION_THRESHOLD)" >&2
    else
        if [ $completion_signal_count -gt 0 ]; then
            echo "" >&2
            echo "🔄 $iteration_display Completion signal not found, resetting counter" >&2
        fi
        completion_signal_count=0
    fi

    # For stream-json format: slurp and get cost from last object
    local cost=$(echo "$result" | jq -s -r '.[-1].total_cost_usd // empty')
    if [ -n "$cost" ]; then
        echo "" >&2
        printf "💰 $iteration_display Iteration cost: \$%.3f\n" "$cost" >&2
        total_cost=$(awk "BEGIN {printf \"%.3f\", $total_cost + $cost}")
        printf "   Running total: \$%.3f\n" "$total_cost" >&2
    fi

    echo "✅ $iteration_display Work completed" >&2
    if [ "$ENABLE_COMMITS" = "true" ]; then
        if [ "$DISABLE_BRANCHES" = "true" ]; then
            # Commit on current branch without PR workflow
            if ! commit_on_current_branch "$iteration_display"; then
                error_count=$((error_count + 1))
                extra_iterations=$((extra_iterations + 1))
                echo "❌ $iteration_display Commit failed ($error_count consecutive errors)" >&2
                if [ $error_count -ge 3 ]; then
                    echo "❌ Fatal: 3 consecutive errors occurred. Exiting." >&2
                    exit 1
                fi
                return 1
            fi
        else
            # Full PR workflow
            if ! continuous_claude_commit "$iteration_display" "$branch_name" "$main_branch"; then
                error_count=$((error_count + 1))
                extra_iterations=$((extra_iterations + 1))
                echo "❌ $iteration_display PR merge queue failed ($error_count consecutive errors)" >&2
                if [ $error_count -ge 3 ]; then
                    echo "❌ Fatal: 3 consecutive errors occurred. Exiting." >&2
                    exit 1
                fi
                return 1
            fi
        fi
    else
        echo "⏭️  $iteration_display Skipping commits (--disable-commits flag set)" >&2
        # Clean up branch if commits are disabled
        if [ -n "$branch_name" ] && git rev-parse --git-dir > /dev/null 2>&1; then
            git checkout "$main_branch" >/dev/null 2>&1
            git branch -D "$branch_name" >/dev/null 2>&1 || true
        fi
    fi
    
    error_count=0
    if [ $extra_iterations -gt 0 ]; then
        extra_iterations=$((extra_iterations - 1))
    fi
    successful_iterations=$((successful_iterations + 1))
    return 0
}

execute_single_iteration() {
    local iteration_num=$1
    
    local iteration_display=$(get_iteration_display $iteration_num $MAX_RUNS $extra_iterations)
    echo "🔄 $iteration_display Starting iteration..." >&2

    # Get current branch and create iteration branch
    local main_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    local branch_name=""
    
    if [ "$ENABLE_COMMITS" = "true" ] && [ "$DISABLE_BRANCHES" != "true" ]; then
        branch_name=$(create_iteration_branch "$iteration_display" "$iteration_num")
        if [ $? -ne 0 ] || [ -z "$branch_name" ]; then
            if git rev-parse --git-dir > /dev/null 2>&1; then
                echo "❌ $iteration_display Failed to create branch" >&2
                handle_iteration_error "$iteration_display" "exit_code" ""
                return 1
            fi
            # Not a git repo, continue without branch
            branch_name=""
        fi
    fi

    local enhanced_prompt="${PROMPT_WORKFLOW_CONTEXT//COMPLETION_SIGNAL_PLACEHOLDER/$COMPLETION_SIGNAL}

$PROMPT

"

    if [ -f "$NOTES_FILE" ]; then
        local notes_content
        notes_content=$(cat "$NOTES_FILE")
        enhanced_prompt+="## CONTEXT FROM PREVIOUS ITERATION

The following is from $NOTES_FILE, maintained by previous iterations to provide context:

$notes_content

"
    fi

    enhanced_prompt+="## ITERATION NOTES

"
    
    if [ -f "$NOTES_FILE" ]; then
        enhanced_prompt+="$PROMPT_NOTES_UPDATE_EXISTING"
    else
        enhanced_prompt+="$PROMPT_NOTES_CREATE_NEW"
    fi
    
    enhanced_prompt+="$PROMPT_NOTES_GUIDELINES"

    echo "🤖 $iteration_display Running Claude Code..." >&2
    
    local result
    local claude_exit_code=0
    result=$(run_claude_iteration "$enhanced_prompt" "$ADDITIONAL_FLAGS" "$ERROR_LOG" "$iteration_display") || claude_exit_code=$?
    
    if [ $claude_exit_code -ne 0 ]; then
        echo "" >&2
        echo "⚠️  Claude Code command failed with exit code: $claude_exit_code" >&2
        # Clean up branch on error
        if [ -n "$branch_name" ] && git rev-parse --git-dir > /dev/null 2>&1; then
            git checkout "$main_branch" >/dev/null 2>&1
            git branch -D "$branch_name" >/dev/null 2>&1 || true
        fi
        handle_iteration_error "$iteration_display" "exit_code" ""
        return 1
    fi
    
    local parse_result=$(parse_claude_result "$result")
    if [ "$?" != "0" ]; then
        # Clean up branch on error
        if [ -n "$branch_name" ] && git rev-parse --git-dir > /dev/null 2>&1; then
            git checkout "$main_branch" >/dev/null 2>&1
            git branch -D "$branch_name" >/dev/null 2>&1 || true
        fi
        handle_iteration_error "$iteration_display" "$parse_result" "$result"
        return 1
    fi

    # Run reviewer pass if REVIEW_PROMPT is set
    if [ -n "$REVIEW_PROMPT" ]; then
        if ! run_reviewer_iteration "$iteration_display" "$REVIEW_PROMPT" "$ERROR_LOG"; then
            echo "❌ $iteration_display Reviewer failed, aborting iteration" >&2
            # Clean up branch on reviewer failure
            if [ -n "$branch_name" ] && git rev-parse --git-dir > /dev/null 2>&1; then
                git checkout "$main_branch" >/dev/null 2>&1
                git branch -D "$branch_name" >/dev/null 2>&1 || true
            fi
            # Count as an error for consecutive error tracking
            error_count=$((error_count + 1))
            extra_iterations=$((extra_iterations + 1))
            if [ $error_count -ge 3 ]; then
                echo "❌ Fatal: 3 consecutive errors occurred. Exiting." >&2
                exit 1
            fi
            return 1
        fi
    fi

    handle_iteration_success "$iteration_display" "$result" "$branch_name" "$main_branch"
    return 0
}

main_loop() {
    # Initialize start time if MAX_DURATION is set
    if [ -n "$MAX_DURATION" ]; then
        start_time=$(date +%s)
    fi
    
    while true; do
        # Check if we should continue based on limits
        local should_continue=false
        
        # Continue if MAX_RUNS is not set or not reached
        if [ -z "$MAX_RUNS" ] || [ "$MAX_RUNS" -eq 0 ] || [ $successful_iterations -lt $MAX_RUNS ]; then
            should_continue=true
        fi
        
        # Stop if MAX_COST is set and reached/exceeded
        if [ -n "$MAX_COST" ] && [ "$(awk "BEGIN {print ($total_cost >= $MAX_COST)}")" = "1" ]; then
            should_continue=false
        fi
        
        # Stop if MAX_DURATION is set and reached/exceeded
        if [ -n "$MAX_DURATION" ] && [ -n "$start_time" ]; then
            local current_time=$(date +%s)
            local elapsed_time=$((current_time - start_time))
            if [ $elapsed_time -ge $MAX_DURATION ]; then
                echo "" >&2
                echo "⏱️  Maximum duration reached ($(format_duration $elapsed_time))" >&2
                should_continue=false
            fi
        fi
        
        # If both limits are set and both are reached, stop
        if [ -n "$MAX_RUNS" ] && [ "$MAX_RUNS" -ne 0 ] && [ $successful_iterations -ge $MAX_RUNS ]; then
            should_continue=false
        fi
        
        # Stop if completion signal threshold reached
        if [ $completion_signal_count -ge $COMPLETION_THRESHOLD ]; then
            echo "" >&2
            echo "🎉 Project completion signal detected $completion_signal_count times consecutively!" >&2
            should_continue=false
        fi
        
        if [ "$should_continue" = "false" ]; then
            break
        fi
        
        execute_single_iteration $i
        
        sleep 1
        i=$((i + 1))
    done
}

show_completion_summary() {
    # Calculate elapsed time if start_time was set
    local elapsed_msg=""
    if [ -n "$start_time" ]; then
        local current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))
        elapsed_msg=" (elapsed: $(format_duration $elapsed_time))"
    fi
    
    # Show completion signal message if that's why we stopped
    if [ $completion_signal_count -ge $COMPLETION_THRESHOLD ]; then
        if [ -n "$total_cost" ] && [ "$(awk "BEGIN {print ($total_cost > 0)}")" = "1" ]; then
            printf "✨ Project completed! Detected completion signal %d times in a row. Total cost: \$%.3f%s\n" "$completion_signal_count" "$total_cost" "$elapsed_msg"
        else
            printf "✨ Project completed! Detected completion signal %d times in a row.%s\n" "$completion_signal_count" "$elapsed_msg"
        fi
    elif [ -n "$MAX_RUNS" ] && [ $MAX_RUNS -ne 0 ] || [ -n "$MAX_COST" ] || [ -n "$MAX_DURATION" ]; then
        if [ -n "$total_cost" ] && [ "$(awk "BEGIN {print ($total_cost > 0)}")" = "1" ]; then
            printf "🎉 Done with total cost: \$%.3f%s\n" "$total_cost" "$elapsed_msg"
        else 
            printf "🎉 Done%s\n" "$elapsed_msg"
        fi
    fi
}

main() {
    # Handle "update" command before parsing arguments
    if [ "$1" = "update" ]; then
        shift
        parse_update_flags "$@"
        handle_update_command
        exit 0
    fi
    
    parse_arguments "$@"
    validate_arguments
    validate_requirements
    
    # Check for updates at startup
    check_for_updates false "$@"
    
    # Handle --list-worktrees flag
    if [ "$LIST_WORKTREES" = "true" ]; then
        list_worktrees
    fi
    
    # Setup worktree if specified
    setup_worktree
    
    ERROR_LOG=$(mktemp)
    trap "rm -f $ERROR_LOG; cleanup_worktree" EXIT
    
    main_loop
    show_completion_summary
    
    # Cleanup worktree if requested
    cleanup_worktree
}

if [ -z "$TESTING" ]; then
    main "$@"
fi
