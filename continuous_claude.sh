#!/bin/bash

ADDITIONAL_FLAGS="--dangerously-skip-permissions --output-format json"

NOTES_FILE="SHARED_TASK_NOTES.md"

PROMPT_JQ_INSTALL="Please install jq for JSON parsing"

PROMPT_COMMIT_MESSAGE="Please review the dirty files in the git repository, write a commit message with: (1) a short one-line summary, (2) two newlines, (3) then a detailed explanation. Do not include any footers or metadata like 'Generated with Claude Code' or 'Co-Authored-By'. Feel free to look at the last few commits to get a sense of the commit message style. Track all files and commit the changes using 'git commit -am \"your message\"' (don't push, just commit, no need to ask for confirmation)."

PROMPT_WORKFLOW_CONTEXT="## CONTINUOUS WORKFLOW CONTEXT

This is part of a continuous development loop where work happens incrementally across multiple iterations. You might run once, then a human developer might make changes, then you run again, and so on. This could happen daily or on any schedule.

**Important**: You don't need to complete the entire goal in one iteration. Just make meaningful progress on one thing, then leave clear notes for the next iteration (human or AI). Think of it as a relay race where you're passing the baton.

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
ENABLE_COMMITS=true
GIT_BRANCH_PREFIX="continuous-claude/"
GITHUB_OWNER=""
GITHUB_REPO=""
ERROR_LOG=""
error_count=0
extra_iterations=0
successful_iterations=0
total_cost=0
i=1

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--prompt)
                PROMPT="$2"
                shift 2
                ;;
            -m|--max-runs)
                MAX_RUNS="$2"
                shift 2
                ;;
            --git-branch-prefix)
                GIT_BRANCH_PREFIX="$2"
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
            *)
                shift
                ;;
        esac
    done
}

validate_arguments() {
    if [ -z "$PROMPT" ]; then
        echo "❌ Error: Prompt is required. Use -p to provide a prompt." >&2
        echo "Usage: $0 -p \"your prompt\" -m max_runs --owner owner --repo repo [--disable-commits]" >&2
        exit 1
    fi

    if [ -z "$MAX_RUNS" ]; then
        echo "❌ Error: MAX_RUNS is required. Use -m to provide max runs (0 for infinite)." >&2
        echo "Usage: $0 -p \"your prompt\" -m max_runs --owner owner --repo repo [--disable-commits]" >&2
        exit 1
    fi

    if ! [[ "$MAX_RUNS" =~ ^[0-9]+$ ]]; then
        echo "❌ Error: MAX_RUNS must be a non-negative integer" >&2
        exit 1
    fi

    if [ -z "$GITHUB_OWNER" ]; then
        echo "❌ Error: GitHub owner is required. Use --owner to provide the owner." >&2
        echo "Usage: $0 -p \"your prompt\" -m max_runs --owner owner --repo repo [--disable-commits]" >&2
        exit 1
    fi

    if [ -z "$GITHUB_REPO" ]; then
        echo "❌ Error: GitHub repo is required. Use --repo to provide the repo." >&2
        echo "Usage: $0 -p \"your prompt\" -m max_runs --owner owner --repo repo [--disable-commits]" >&2
        exit 1
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

    if ! command -v gh &> /dev/null; then
        echo "❌ Error: GitHub CLI (gh) is not installed: https://cli.github.com" >&2
        exit 1
    fi

    if ! gh auth status >/dev/null 2>&1; then
        echo "❌ Error: GitHub CLI is not authenticated. Run 'gh auth login' first." >&2
        exit 1
    fi
}

wait_for_pr_checks() {
    local pr_number="$1"
    local owner="$2"
    local repo="$3"
    local iteration_display="$4"
    local max_iterations=180  # 180 * 10 seconds = 30 minutes
    local iteration=0

    while [ $iteration -lt $max_iterations ]; do
        echo "🔍 $iteration_display Checking PR status (iteration $((iteration + 1))/$max_iterations)..." >&2
        
        local checks_json
        local no_checks_configured=false
        if ! checks_json=$(gh pr checks "$pr_number" --repo "$owner/$repo" --json state,bucket 2>&1); then
            if echo "$checks_json" | grep -q "no checks"; then
                echo "   📊 No checks configured" >&2
                no_checks_configured=true
                checks_json="[]"
            else
                echo "⚠️  $iteration_display Failed to get PR checks status: $checks_json" >&2
                return 1
            fi
        fi

        local check_count=$(echo "$checks_json" | jq 'length' 2>/dev/null || echo "0")
        
        if [ "$no_checks_configured" = "false" ]; then
            echo "   📊 Found $check_count check(s)" >&2
        fi
        
        local all_completed=true
        local all_success=true
        
        if [ "$no_checks_configured" = "false" ] && [ "$check_count" -eq 0 ]; then
            all_completed=false
        fi

        if [ "$check_count" -gt 0 ]; then
            local pending_count=0
            local success_count=0
            local failed_count=0
            
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
            
            echo "   🟢 $success_count    🟡 $pending_count    🔴 $failed_count" >&2
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
        
        if [ -n "$review_decision" ] && [ "$review_decision" != "null" ]; then
            echo "   👁️  Review status: $review_decision" >&2
        elif [ "$review_requests_count" -gt 0 ]; then
            echo "   👁️  Review status: $review_requests_count review(s) requested" >&2
        else
            echo "   👁️  Review status: None" >&2
        fi

        if [ "$check_count" -eq 0 ] && [ "$checks_json" != "" ] && [ "$checks_json" != "[]" ] && [ "$no_checks_configured" = "false" ]; then
            if [ "$iteration" -lt 18 ]; then
                echo "⏳ Waiting for checks to start... (will timeout after 3 minutes)" >&2
                echo "" >&2
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
            echo "   ✅ All checks passed, but waiting for review..." >&2
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
        
        if [ ${#waiting_items[@]} -gt 0 ]; then
            echo "⏳ Waiting for: ${waiting_items[*]}" >&2
            echo "   💤 Sleeping for 10 seconds before next check..." >&2
            echo "" >&2
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

    echo "🔀 $iteration_display Merging PR #$pr_number..." >&2
    if ! gh pr merge "$pr_number" --repo "$owner/$repo" --squash >/dev/null 2>&1; then
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

continuous_claude_commit() {
    local iteration_display="$1"
    local iteration_num="$2"
    
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        return 0
    fi

    if git diff --quiet && git diff --cached --quiet; then
        echo "🫙 $iteration_display No changes detected" >&2
        return 0
    fi

    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
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
    
    if ! git checkout -b "$branch_name" >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to create branch" >&2
        return 1
    fi
    
    echo "💬 $iteration_display Committing changes..." >&2
    
    if ! claude -p "$PROMPT_COMMIT_MESSAGE" --allowedTools "Bash(git)" --dangerously-skip-permissions >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to commit changes" >&2
        git checkout "$current_branch" >/dev/null 2>&1
        return 1
    fi

    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "⚠️  $iteration_display Commit command ran but changes still present" >&2
        git checkout "$current_branch" >/dev/null 2>&1
        return 1
    fi

    echo "📦 $iteration_display Changes committed on branch: $branch_name" >&2

    local commit_message=$(git log -1 --format="%B" "$branch_name")
    local commit_title=$(echo "$commit_message" | head -n 1)
    local commit_body=$(echo "$commit_message" | tail -n +4)

    echo "📤 $iteration_display Pushing branch..." >&2
    if ! git push -u origin "$branch_name" >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to push branch" >&2
        git checkout "$current_branch" >/dev/null 2>&1
        return 1
    fi

    echo "🔨 $iteration_display Creating pull request..." >&2
    local pr_output
    if ! pr_output=$(gh pr create --repo "$GITHUB_OWNER/$GITHUB_REPO" --title "$commit_title" --body "$commit_body" --base main 2>&1); then
        echo "⚠️  $iteration_display Failed to create PR: $pr_output" >&2
        git checkout "$current_branch" >/dev/null 2>&1
        return 1
    fi

    local pr_number=$(echo "$pr_output" | grep -oE '(pull/|#)[0-9]+' | grep -oE '[0-9]+' | head -n 1)
    if [ -z "$pr_number" ]; then
        echo "⚠️  $iteration_display Failed to extract PR number from: $pr_output" >&2
        git checkout "$current_branch" >/dev/null 2>&1
        return 1
    fi

    echo "🔍 $iteration_display PR #$pr_number created, waiting 5 seconds for GitHub to set up..." >&2
    sleep 5
    if ! wait_for_pr_checks "$pr_number" "$GITHUB_OWNER" "$GITHUB_REPO" "$iteration_display"; then
        echo "⚠️  $iteration_display PR checks failed or timed out" >&2
        git checkout "$current_branch" >/dev/null 2>&1
        return 1
    fi

    if ! merge_pr_and_cleanup "$pr_number" "$GITHUB_OWNER" "$GITHUB_REPO" "$branch_name" "$iteration_display" "$current_branch"; then
        return 1
    fi

    echo "✅ $iteration_display PR merged and local branch cleaned up" >&2
    
    # Ensure we're back on the main branch
    if ! git checkout "$current_branch" >/dev/null 2>&1; then
        echo "⚠️  $iteration_display Failed to checkout $current_branch" >&2
        return 1
    fi
    
    return 0
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

    claude -p "$prompt" $flags 2> >(tee "$error_log" >&2)
}

parse_claude_result() {
    local result="$1"
    
    if ! echo "$result" | jq -e . >/dev/null 2>&1; then
        echo "invalid_json"
        return 1
    fi
    
    local is_error=$(echo "$result" | jq -r '.is_error // false')
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
            echo "❌ $iteration_display Error occurred ($error_count consecutive errors):" >&2
            cat "$ERROR_LOG" >&2
            ;;
        "invalid_json")
            echo "❌ $iteration_display Error: Invalid JSON response ($error_count consecutive errors):" >&2
            echo "$error_output" >&2
            ;;
        "claude_error")
            echo "❌ $iteration_display Error in Claude Code response ($error_count consecutive errors):" >&2
            echo "$error_output" | jq -r '.result // .' >&2
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
    local iteration_num="$3"
    
    echo "📝 $iteration_display Output:" >&2
    local result_text=$(echo "$result" | jq -r '.result // empty')
    if [ -n "$result_text" ]; then
        echo "$result_text"
    else
        echo "(no output)" >&2
    fi

    local cost=$(echo "$result" | jq -r '.total_cost_usd // empty')
    if [ -n "$cost" ]; then
        echo "" >&2
        printf "💰 $iteration_display Cost: \$%.3f\n" "$cost" >&2
        total_cost=$(awk "BEGIN {printf \"%.3f\", $total_cost + $cost}")
    fi

    echo "✅ $iteration_display Work completed" >&2
    if [ "$ENABLE_COMMITS" = "true" ]; then
        if ! continuous_claude_commit "$iteration_display" "$iteration_num"; then
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

    local enhanced_prompt="$PROMPT_WORKFLOW_CONTEXT

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

    local result
    if ! result=$(run_claude_iteration "$enhanced_prompt" "$ADDITIONAL_FLAGS" "$ERROR_LOG"); then
        handle_iteration_error "$iteration_display" "exit_code" ""
        return 1
    fi
    
    local parse_result=$(parse_claude_result "$result")
    if [ "$?" != "0" ]; then
        handle_iteration_error "$iteration_display" "$parse_result" "$result"
        return 1
    fi
    
    handle_iteration_success "$iteration_display" "$result" "$iteration_num"
    return 0
}

main_loop() {
    while [ $MAX_RUNS -eq 0 ] || [ $successful_iterations -lt $MAX_RUNS ]; do
        execute_single_iteration $i
        
        if [ $MAX_RUNS -eq 0 ] || [ $successful_iterations -lt $MAX_RUNS ]; then
            sleep 1
        fi
        
        i=$((i + 1))
    done
}

show_completion_summary() {
    if [ $MAX_RUNS -ne 0 ]; then
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
    
    ERROR_LOG=$(mktemp)
    trap "rm -f $ERROR_LOG" EXIT
    
    main_loop
    show_completion_summary
}

if [ -z "$TESTING" ]; then
    main "$@"
fi
