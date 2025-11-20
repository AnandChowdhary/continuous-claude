#!/bin/bash

VERSION="v0.8.3"

AGENT_COMMAND="claude -p {prompt} --dangerously-skip-permissions --output-format json"

NOTES_FILE="SHARED_TASK_NOTES.md"

PROMPT_JQ_INSTALL="Please install jq for JSON parsing"

PROMPT_COMMIT_MESSAGE="Please review all uncommitted changes in the git repository (both modified and new files). Write a commit message with: (1) a short one-line summary, (2) two newlines, (3) then a detailed explanation. Do not include any footers or metadata like 'Generated with Claude Code' or 'Co-Authored-By'. Feel free to look at the last few commits to get a sense of the commit message style for consistency. First run 'git add .' to stage all changes including new untracked files, then commit using 'git commit -m \"your message\"' (don't push, just commit, no need to ask for confirmation)."

PROMPT_WORKFLOW_CONTEXT="## CONTINUOUS WORKFLOW CONTEXT

This is part of a continuous development loop where work happens incrementally across multiple iterations. You might run once, then a human developer might make changes, then you run again, and so on. This could happen daily or on any schedule.

**Important**: You don't need to complete the entire goal in one iteration. Just make meaningful progress on one thing, then leave clear notes for the next iteration (human or AI). Think of it as a relay race where you're passing the baton.

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

PROMPT=""
MAX_RUNS=""
MAX_COST=""
ENABLE_COMMITS=true
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

show_help() {
    cat << EOF
Continuous Claude - Run Claude Code iteratively with automatic PR management

USAGE:
    continuous-claude -p "prompt" (-m max-runs | --max-cost max-cost) --owner owner --repo repo [options]

REQUIRED OPTIONS:
    -p, --prompt <text>           The prompt/goal for Claude Code to work on
    -m, --max-runs <number>       Maximum number of successful iterations (use 0 for unlimited with --max-cost)
    --max-cost <dollars>          Maximum cost in USD to spend (alternative to --max-runs)
    --owner <owner>               GitHub repository owner (required unless --disable-commits)
    --repo <repo>                 GitHub repository name (required unless --disable-commits)

OPTIONAL FLAGS:
    -h, --help                    Show this help message
    -v, --version                 Show version information
    --agent <command>             AI agent command with {prompt} placeholder (default: "claude -p {prompt} --dangerously-skip-permissions --output-format json")
                                  Examples:
                                    --agent "claude -p {prompt} --json"
                                    --agent "codex exec {prompt} --full-auto"
                                    --agent "aider --message {prompt} --yes --model gpt-4"
                                  The {prompt} placeholder will be replaced with the actual prompt
    --disable-commits             Disable automatic commits and PR creation
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

EXAMPLES:
    # Run 5 iterations to fix bugs (uses Claude by default)
    continuous-claude -p "Fix all linter errors" -m 5 --owner myuser --repo myproject

    # Use OpenAI Codex instead of Claude
    continuous-claude --agent "codex exec {prompt}" -p "Add tests" -m 5 --owner myuser --repo myproject

    # Use Aider with custom model
    continuous-claude --agent "aider --message {prompt} --yes --model gpt-4" -p "Refactor code" -m 3 --owner myuser --repo myproject

    # Run with cost limit
    continuous-claude -p "Add tests" --max-cost 10.00 --owner myuser --repo myproject

    # Run without commits (testing mode)
    continuous-claude -p "Refactor code" -m 3 --disable-commits

    # Use custom branch prefix and merge strategy
    continuous-claude -p "Feature work" -m 10 --owner myuser --repo myproject \\
        --git-branch-prefix "ai/" --merge-strategy merge

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

REQUIREMENTS:
    - AI agent CLI (default: Claude Code from https://claude.ai/code, or specify with --agent)
    - GitHub CLI (gh) - authenticated with 'gh auth login' (unless --disable-commits)
    - jq - JSON parsing utility
    - Git repository (unless --disable-commits is used)

For more information, visit: https://github.com/AnandChowdhary/continuous-claude
EOF
}

show_version() {
    echo "continuous-claude version $VERSION"
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
            --agent)
                AGENT_COMMAND="$2"
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

validate_arguments() {
    if [ -z "$PROMPT" ]; then
        echo "❌ Error: Prompt is required. Use -p to provide a prompt." >&2
        echo "Run '$0 --help' for usage information." >&2
        exit 1
    fi

    if [ -z "$MAX_RUNS" ] && [ -z "$MAX_COST" ]; then
        echo "❌ Error: Either --max-runs or --max-cost is required." >&2
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

    # Only require GitHub info if commits are enabled
    if [ "$ENABLE_COMMITS" = "true" ]; then
        if [ -z "$GITHUB_OWNER" ]; then
            echo "❌ Error: GitHub owner is required. Use --owner to provide the owner." >&2
            echo "Run '$0 --help' for usage information." >&2
            exit 1
        fi

        if [ -z "$GITHUB_REPO" ]; then
            echo "❌ Error: GitHub repo is required. Use --repo to provide the repo." >&2
            echo "Run '$0 --help' for usage information." >&2
            exit 1
        fi
    fi
}

validate_requirements() {
    # Extract base command from AGENT_COMMAND (first word)
    local agent_base_cmd=$(echo "$AGENT_COMMAND" | awk '{print $1}')
    
    if ! command -v "$agent_base_cmd" &> /dev/null; then
        echo "❌ Error: Agent command '$agent_base_cmd' is not installed." >&2
        echo "   Please install the agent or specify a different one with --agent" >&2
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        echo "⚠️ jq is required for JSON parsing but is not installed. Asking agent to install it..." >&2
        # Try to use the agent to install jq
        local install_cmd="${AGENT_COMMAND//\{prompt\}/$PROMPT_JQ_INSTALL}"
        eval "$install_cmd" &> /dev/null || true
        if ! command -v jq &> /dev/null; then
            echo "❌ Error: jq is still not installed. Please install it manually." >&2
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

        if [ "$check_count" -eq 0 ] && [ "$checks_json" != "" ] && [ "$checks_json" != "[]" ] && [ "$no_checks_configured" = "false" ]; then
            if [ "$iteration" -lt 18 ]; then
                if [ "$state_changed" = "true" ]; then
                    echo "⏳ Waiting for checks to start... (will timeout after 3 minutes)" >&2
                fi
                sleep 10
                iteration=$((iteration + 1))
                continue
            else
                echo "   ⚠️  No checks found after waiting, proceeding without checks" >&2
                all_completed=true
                all_success=true
            fi
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
    local has_changes=false
    if ! git diff --quiet || ! git diff --cached --quiet; then
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
        echo "✅ $iteration_display (DRY RUN) PR merged and local branch cleaned up" >&2
        return 0
    fi
    
    echo "💬 $iteration_display Committing changes..." >&2
    
    # Use agent to create commit message, replacing {prompt} placeholder
    local escaped_commit_prompt="${PROMPT_COMMIT_MESSAGE//\"/\\\"}"
    local commit_cmd="${AGENT_COMMAND//\{prompt\}/\"$escaped_commit_prompt\"}"
    
    if ! eval "$commit_cmd" >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to commit changes" >&2
        git checkout "$main_branch" >/dev/null 2>&1
        return 1
    fi

    # Verify all changes (including untracked files) were committed
    if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
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
        echo "⚠️  $iteration_display PR checks failed or timed out, closing PR..." >&2
        gh pr close "$pr_number" --repo "$GITHUB_OWNER/$GITHUB_REPO" >/dev/null 2>&1 || true
        echo "🗑️  $iteration_display Cleaning up local branch: $branch_name" >&2
        git checkout "$main_branch" >/dev/null 2>&1
        git branch -D "$branch_name" >/dev/null 2>&1 || true
        return 1
    fi

    if ! merge_pr_and_cleanup "$pr_number" "$GITHUB_OWNER" "$GITHUB_REPO" "$branch_name" "$iteration_display" "$main_branch"; then
        # Check if PR is still open before closing (might have been merged but cleanup failed)
        local pr_state=$(gh pr view "$pr_number" --repo "$GITHUB_OWNER/$GITHUB_REPO" --json state --jq '.state' 2>/dev/null || echo "UNKNOWN")
        if [ "$pr_state" = "OPEN" ]; then
            echo "⚠️  $iteration_display Failed to merge PR, closing it..." >&2
            gh pr close "$pr_number" --repo "$GITHUB_OWNER/$GITHUB_REPO" >/dev/null 2>&1 || true
        else
            echo "⚠️  $iteration_display PR was merged but cleanup failed" >&2
        fi
        echo "🗑️  $iteration_display Cleaning up local branch: $branch_name" >&2
        git checkout "$main_branch" >/dev/null 2>&1
        git branch -D "$branch_name" >/dev/null 2>&1 || true
        return 1
    fi

    echo "✅ $iteration_display PR merged and local branch cleaned up" >&2
    
    # Ensure we're back on the main branch
    if ! git checkout "$main_branch" >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to checkout $main_branch" >&2
        return 1
    fi
    
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

run_agent_iteration() {
    local prompt="$1"
    local error_log="$2"

    if [ "$DRY_RUN" = "true" ]; then
        local agent_name=$(echo "$AGENT_COMMAND" | awk '{print $1}')
        echo "🤖 (DRY RUN) Would run $agent_name with prompt: $prompt" >&2
        echo "📝 (DRY RUN) Output: This is a simulated response from $agent_name." > "$error_log"
        return 0
    fi

    # Replace {prompt} placeholder with actual prompt (escape for shell safety)
    local escaped_prompt="${prompt//\"/\\\"}"
    local agent_cmd="${AGENT_COMMAND//\{prompt\}/\"$escaped_prompt\"}"
    
    # Execute the agent command
    eval "$agent_cmd ${EXTRA_CLAUDE_FLAGS[@]}" 2> >(tee "$error_log" >&2)
}

parse_agent_result() {
    local result="$1"
    local exit_code="$2"
    
    # Try to parse as JSON first
    if echo "$result" | jq -e . >/dev/null 2>&1; then
        # It's valid JSON - check for is_error field
        local is_error=$(echo "$result" | jq -r '.is_error // false')
        if [ "$is_error" = "true" ]; then
            echo "agent_error"
            return 1
        fi
    fi
    
    # For non-JSON or JSON without is_error, rely on exit code
    # Exit code 0 = success regardless of output format
    if [ "$exit_code" = "0" ]; then
        echo "success"
        return 0
    else
        echo "exit_code_error"
        return 1
    fi
}

handle_iteration_error() {
    local iteration_display="$1"
    local error_type="$2"
    local error_output="$3"
    
    error_count=$((error_count + 1))
    extra_iterations=$((extra_iterations + 1))
    
    case "$error_type" in
        "exit_code_error")
            echo "❌ $iteration_display Error occurred ($error_count consecutive errors):" >&2
            cat "$ERROR_LOG" >&2
            ;;
        "agent_error")
            echo "❌ $iteration_display Error in agent response ($error_count consecutive errors):" >&2
            # Try to extract result field from JSON, or show raw output
            if echo "$error_output" | jq -e . >/dev/null 2>&1; then
                echo "$error_output" | jq -r '.result // .' >&2
            else
                echo "$error_output" >&2
            fi
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
    
    echo "📝 $iteration_display Output:" >&2
    
    # Try to extract result from JSON, fall back to using entire output
    local result_text=""
    if echo "$result" | jq -e . >/dev/null 2>&1; then
        # Valid JSON - try to extract .result field
        result_text=$(echo "$result" | jq -r '.result // empty')
    fi
    
    # If JSON didn't have .result field, or wasn't JSON, use entire output
    if [ -z "$result_text" ]; then
        result_text="$result"
    fi
    
    if [ -n "$result_text" ]; then
        echo "$result_text"
    else
        echo "(no output)" >&2
    fi

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

    # Try to extract cost if available (optional, many agents don't provide this)
    if echo "$result" | jq -e . >/dev/null 2>&1; then
        local cost=$(echo "$result" | jq -r '.total_cost_usd // empty')
        if [ -n "$cost" ]; then
            echo "" >&2
            printf "💰 $iteration_display Cost: \$%.3f\n" "$cost" >&2
            total_cost=$(awk "BEGIN {printf \"%.3f\", $total_cost + $cost}")
        fi
    fi

    echo "✅ $iteration_display Work completed" >&2
    if [ "$ENABLE_COMMITS" = "true" ]; then
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
    
    if [ "$ENABLE_COMMITS" = "true" ]; then
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

    local agent_name=$(echo "$AGENT_COMMAND" | awk '{print $1}')
    echo "🤖 $iteration_display Running $agent_name..." >&2
    
    local result
    result=$(run_agent_iteration "$enhanced_prompt" "$ERROR_LOG")
    local agent_exit_code=$?
    
    local parse_result=$(parse_agent_result "$result" "$agent_exit_code")
    if [ "$?" != "0" ]; then
        # Clean up branch on error
        if [ -n "$branch_name" ] && git rev-parse --git-dir > /dev/null 2>&1; then
            git checkout "$main_branch" >/dev/null 2>&1
            git branch -D "$branch_name" >/dev/null 2>&1 || true
        fi
        handle_iteration_error "$iteration_display" "$parse_result" "$result"
        return 1
    fi
    
    handle_iteration_success "$iteration_display" "$result" "$branch_name" "$main_branch"
    return 0
}

main_loop() {
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
    # Show completion signal message if that's why we stopped
    if [ $completion_signal_count -ge $COMPLETION_THRESHOLD ]; then
        if [ -n "$total_cost" ] && [ "$(awk "BEGIN {print ($total_cost > 0)}")" = "1" ]; then
            printf "✨ Project completed! Detected completion signal %d times in a row. Total cost: \$%.3f\n" "$completion_signal_count" "$total_cost"
        else
            printf "✨ Project completed! Detected completion signal %d times in a row.\n" "$completion_signal_count"
        fi
    elif [ -n "$MAX_RUNS" ] && [ $MAX_RUNS -ne 0 ] || [ -n "$MAX_COST" ]; then
        if [ -n "$total_cost" ] && [ "$(awk "BEGIN {print ($total_cost > 0)}")" = "1" ]; then
            printf "🎉 Done with total cost: \$%.3f\n" "$total_cost"
        else 
            echo "🎉 Done"
        fi
    fi
}

main() {
    parse_arguments "$@"
    validate_arguments
    validate_requirements
    
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
