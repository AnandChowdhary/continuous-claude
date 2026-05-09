#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

setup() {
    # Path to the script under test
    # BATS_TEST_DIRNAME is the directory containing the test file
    SCRIPT_PATH="$BATS_TEST_DIRNAME/../continuous_claude.sh"
    PS_SCRIPT_PATH="$BATS_TEST_DIRNAME/../continuous_claude.ps1"
    export TESTING="true"
}

require_pwsh() {
    if ! command -v pwsh >/dev/null 2>&1; then
        skip "pwsh is not installed"
    fi
}

@test "script has valid bash syntax" {
    run bash -n "$SCRIPT_PATH"
    assert_success
}

@test "show_help displays help message" {
    source "$SCRIPT_PATH"
    # We need to call the function directly to capture output in the current shell
    # or export it for run. Simpler to just capture output manually if run fails.
    # But let's try exporting.
    export -f show_help
    run show_help
    assert_output --partial "Continuous Claude - Run Claude Code iteratively"
    assert_output --partial "USAGE:"
}

@test "show_version displays version" {
    source "$SCRIPT_PATH"
    export -f show_version
    run show_version
    assert_output --partial "continuous-claude version"
}

@test "powershell script displays version" {
    require_pwsh

    run pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT_PATH" --version

    assert_success
    assert_output --partial "continuous-claude PowerShell version"
}

@test "powershell script displays help" {
    require_pwsh

    run pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT_PATH" --help

    assert_success
    assert_output --partial "Continuous Claude PowerShell"
    assert_output --partial "--review-prompt [text]"
}

@test "powershell dry run supports empty reviewer prompt" {
    require_pwsh

    local fake_bin="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$fake_bin"
    printf '#!/bin/sh\nexit 0\n' > "$fake_bin/claude"
    chmod +x "$fake_bin/claude"

    PATH="$fake_bin:$PATH" run pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT_PATH" \
        -p "test" -r -m 1 --disable-commits --disable-updates --dry-run

    assert_success
    assert_output --partial "Running reviewer pass"
    assert_output --partial "Review the currently changed files"
    assert_output --partial "Skipping commits"
}

@test "powershell codex dry run returns completed turn" {
    require_pwsh

    local fake_bin="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$fake_bin"
    printf '#!/bin/sh\nexit 0\n' > "$fake_bin/codex"
    chmod +x "$fake_bin/codex"

    PATH="$fake_bin:$PATH" run pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT_PATH" \
        --provider codex -p "test" -m 1 --disable-commits --disable-updates --dry-run

    assert_success
    assert_output --partial "Running Codex CLI"
    assert_output --partial "Work completed"
    assert_output --partial "Skipping commits"
}

@test "powershell codex max-cost requires token rates" {
    require_pwsh

    run pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT_PATH" \
        --provider codex -p "test" --max-cost 5 --disable-commits

    assert_failure
    assert_output --partial "Codex CLI does not report USD cost"
}

@test "powershell rejects bash-only workflow flags" {
    require_pwsh

    run pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT_PATH" \
        -p "test" -m 1 --worktree windows

    assert_failure
    assert_output --partial "--worktree is not supported by the native PowerShell runner yet"
}

@test "parse_arguments handles required flags" {
    source "$SCRIPT_PATH"
    parse_arguments -p "test prompt" -m 5 --owner user --repo repo
    
    assert_equal "$PROMPT" "test prompt"
    assert_equal "$MAX_RUNS" "5"
    assert_equal "$GITHUB_OWNER" "user"
    assert_equal "$GITHUB_REPO" "repo"
}

@test "parse_arguments handles dry-run flag" {
    source "$SCRIPT_PATH"
    parse_arguments -p "test" --dry-run
    
    assert_equal "$DRY_RUN" "true"
}

@test "parse_arguments handles provider flag" {
    source "$SCRIPT_PATH"
    parse_arguments --provider codex

    assert_equal "$AGENT_PROVIDER" "codex"
}

@test "parse_arguments forwards provider flags after separator" {
    source "$SCRIPT_PATH"
    parse_arguments --provider codex -p "test" -m 1 -- --model gpt-5.5

    assert_equal "$AGENT_PROVIDER" "codex"
    assert_equal "${EXTRA_AGENT_FLAGS[0]}" "--model"
    assert_equal "${EXTRA_AGENT_FLAGS[1]}" "gpt-5.5"
    assert_equal "${EXTRA_CLAUDE_FLAGS[0]}" "--model"
}

@test "parse_arguments handles review prompt value" {
    source "$SCRIPT_PATH"
    parse_arguments -r "Run tests and lint"

    assert_equal "$REVIEW_PROMPT" "Run tests and lint"
}

@test "parse_arguments uses default review prompt when -r has no value" {
    source "$SCRIPT_PATH"
    parse_arguments -p "test" -r -m 1

    assert_equal "$PROMPT" "test"
    assert_equal "$MAX_RUNS" "1"
    assert_equal "$REVIEW_PROMPT" "$PROMPT_DEFAULT_REVIEWER"
}

@test "parse_arguments uses default review prompt for empty equals value" {
    source "$SCRIPT_PATH"
    parse_arguments --review-prompt=

    assert_equal "$REVIEW_PROMPT" "$PROMPT_DEFAULT_REVIEWER"
}

@test "parse_arguments handles auto-update flag" {
    source "$SCRIPT_PATH"
    AUTO_UPDATE="false"
    parse_arguments --auto-update
    
    assert_equal "$AUTO_UPDATE" "true"
}

@test "parse_arguments handles disable-updates flag" {
    source "$SCRIPT_PATH"
    DISABLE_UPDATES="false"
    parse_arguments --disable-updates
    
    assert_equal "$DISABLE_UPDATES" "true"
}

@test "render_notes_prompt uses current notes-file value" {
    source "$SCRIPT_PATH"
    NOTES_FILE="CUSTOM_NOTES.md"

    run render_notes_prompt "$PROMPT_NOTES_CREATE_NEW"

    assert_success
    assert_output 'Create a `CUSTOM_NOTES.md` file with relevant context and instructions for the next iteration.'
}

@test "validate_arguments fails without prompt" {
    source "$SCRIPT_PATH"
    PROMPT=""
    run validate_arguments
    assert_failure
    assert_output --partial "Error: Prompt is required"
}

@test "validate_arguments fails without max-runs or max-cost" {
    source "$SCRIPT_PATH"
    PROMPT="test"
    MAX_RUNS=""
    MAX_COST=""
    MAX_DURATION=""
    run validate_arguments
    assert_failure
    assert_output --partial "Error: Either --max-runs, --max-cost, or --max-duration is required"
}

@test "validate_arguments passes with valid arguments" {
    source "$SCRIPT_PATH"
    PROMPT="test"
    MAX_RUNS="5"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"
    run validate_arguments
    assert_success
}

@test "validate_arguments fails with invalid provider" {
    source "$SCRIPT_PATH"
    AGENT_PROVIDER="invalid"
    PROMPT="test"
    MAX_RUNS="5"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"

    run validate_arguments
    assert_failure
    assert_output --partial "Error: --provider must be one of: claude, codex"
}

@test "validate_arguments requires Codex token rates for max-cost" {
    source "$SCRIPT_PATH"
    AGENT_PROVIDER="codex"
    PROMPT="test"
    MAX_COST="5.00"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"

    run validate_arguments
    assert_failure
    assert_output --partial "Codex CLI does not report USD cost"
}

@test "validate_arguments accepts Codex max-cost with token rates" {
    source "$SCRIPT_PATH"
    AGENT_PROVIDER="codex"
    PROMPT="test"
    MAX_COST="5.00"
    CODEX_INPUT_COST_PER_MILLION="1.25"
    CODEX_OUTPUT_COST_PER_MILLION="10.00"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"

    run validate_arguments
    assert_success
}

@test "validate_arguments limits cost-only dry runs to one iteration" {
    source "$SCRIPT_PATH"
    PROMPT="test"
    MAX_COST="5.00"
    DRY_RUN="true"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"

    validate_arguments

    assert_equal "$MAX_RUNS" "1"
}

@test "dry run mode skips execution" {
    # Mock required commands
    function claude() { echo "mock claude"; }
    function gh() { echo "mock gh"; }
    function git() { echo "mock git"; }
    export -f claude gh git
    
    source "$SCRIPT_PATH"
    
    # Set up environment for main_loop
    PROMPT="test"
    MAX_RUNS=1
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"
    DRY_RUN="true"
    ENABLE_COMMITS="true"
    
    # Create a temporary error log
    ERROR_LOG=$(mktemp)
    
    # Run the main loop (should be fast due to dry run)
    run main_loop
    
    rm -f "$ERROR_LOG"
    
    assert_success
    # We can't easily check stdout here because main_loop output might be captured or redirected
    # But success means it didn't crash
}

@test "validate_requirements fails when claude is missing" {
    # Mock command to fail for claude
    function command() {
        if [ "$2" == "claude" ]; then
            return 1
        fi
        return 0
    }
    export -f command
    
    source "$SCRIPT_PATH"
    run validate_requirements
    
    assert_failure
    assert_output --partial "Error: Claude Code is not installed"
}

@test "validate_requirements fails when codex is missing for codex provider" {
    function command() {
        if [ "$2" == "codex" ]; then
            return 1
        fi
        return 0
    }
    export -f command

    source "$SCRIPT_PATH"
    AGENT_PROVIDER="codex"
    run validate_requirements

    assert_failure
    assert_output --partial "Error: Codex CLI is not installed"
}

@test "validate_requirements fails when jq is missing" {
    # Mock command to fail for jq, pass for claude
    function command() {
        if [ "$2" == "jq" ]; then
            return 1
        fi
        return 0
    }
    # Mock claude to simulate installation failure
    function claude() {
        return 0
    }
    export -f command claude
    
    source "$SCRIPT_PATH"
    run validate_requirements
    
    assert_failure
    assert_output --partial "jq is required for JSON parsing"
}

@test "validate_requirements fails when gh is missing and commits enabled" {
    # Mock command to fail for gh
    function command() {
        if [ "$2" == "gh" ]; then
            return 1
        fi
        return 0
    }
    export -f command
    
    source "$SCRIPT_PATH"
    ENABLE_COMMITS="true"
    run validate_requirements
    
    assert_failure
    assert_output --partial "Error: GitHub CLI (gh) is not installed"
}

@test "validate_requirements passes when gh is missing but commits disabled" {
    # Mock command to fail for gh
    function command() {
        if [ "$2" == "gh" ]; then
            return 1
        fi
        return 0
    }
    export -f command
    
    source "$SCRIPT_PATH"
    ENABLE_COMMITS="false"
    run validate_requirements
    
    assert_success
}

@test "get_iteration_display formats with max runs" {
    source "$SCRIPT_PATH"
    run get_iteration_display 1 5 0
    assert_output "(1/5)"
    
    run get_iteration_display 2 5 1
    assert_output "(2/6)"
}

@test "get_iteration_display formats without max runs" {
    source "$SCRIPT_PATH"
    run get_iteration_display 1 0 0
    assert_output "(1)"
}

@test "parse_claude_result handles valid success JSON" {
    source "$SCRIPT_PATH"
    run parse_claude_result '{"result": "success", "total_cost_usd": 0.1}'
    assert_success
    assert_output "success"
}

@test "parse_claude_result handles invalid JSON" {
    source "$SCRIPT_PATH"
    run parse_claude_result 'invalid json'
    assert_failure
    assert_output "invalid_json"
}

@test "parse_claude_result handles Claude error JSON" {
    source "$SCRIPT_PATH"
    run parse_claude_result '{"is_error": true, "result": "error message"}'
    assert_failure
    assert_output "claude_error"
}

@test "parse_agent_result handles Codex success JSONL" {
    source "$SCRIPT_PATH"
    AGENT_PROVIDER="codex"
    local result='{"type":"thread.started","thread_id":"abc"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"done"}}
{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":20}}'

    run parse_agent_result "$result"
    assert_success
    assert_output "success"
}

@test "parse_agent_result handles Codex error JSONL" {
    source "$SCRIPT_PATH"
    AGENT_PROVIDER="codex"
    local result='{"type":"thread.started","thread_id":"abc"}
{"type":"error","message":"authentication failed"}'

    run parse_agent_result "$result"
    assert_failure
    assert_output "codex_error"
}

@test "parse_agent_result handles Codex incomplete JSONL" {
    source "$SCRIPT_PATH"
    AGENT_PROVIDER="codex"
    local result='{"type":"thread.started","thread_id":"abc"}
{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"done"}}'

    run parse_agent_result "$result"
    assert_failure
    assert_output "codex_incomplete"
}

@test "extract_agent_result_text handles Codex agent messages" {
    source "$SCRIPT_PATH"
    AGENT_PROVIDER="codex"
    local result='{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"first"}}
{"type":"item.completed","item":{"id":"item_2","type":"agent_message","text":"second"}}
{"type":"turn.completed","usage":{"input_tokens":100,"output_tokens":20}}'

    run extract_agent_result_text "$result"
    assert_success
    assert_output $'first\nsecond'
}

@test "extract_agent_cost estimates Codex cost from usage and token rates" {
    source "$SCRIPT_PATH"
    AGENT_PROVIDER="codex"
    CODEX_INPUT_COST_PER_MILLION="1.00"
    CODEX_CACHED_INPUT_COST_PER_MILLION="0.10"
    CODEX_OUTPUT_COST_PER_MILLION="10.00"
    local result='{"type":"turn.completed","usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":100}}'

    run extract_agent_cost "$result"
    assert_success
    assert_output "0.001820"
}

@test "extract_agent_usage_summary shows Codex token usage" {
    source "$SCRIPT_PATH"
    AGENT_PROVIDER="codex"
    local result='{"type":"turn.completed","usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":100}}'

    run extract_agent_usage_summary "$result"
    assert_success
    assert_output "Tokens: input 1000, cached input 200, output 100"
}

@test "create_iteration_branch generates correct branch name" {
    source "$SCRIPT_PATH"
    GIT_BRANCH_PREFIX="test-prefix/"
    DRY_RUN="true"
    
    # Mock date to return fixed value
    function date() {
        if [ "$1" == "+%Y-%m-%d" ]; then
            echo "2024-01-01"
        else
            echo "12345678"
        fi
    }
    # Mock openssl for random hash
    function openssl() {
        echo "abcdef12"
    }
    export -f date openssl
    
    run create_iteration_branch "(1/5)" 1
    
    assert_success
    assert_output --partial "test-prefix/iteration-1/2024-01-01-abcdef12"
}

@test "parse_arguments handles completion-signal flag" {
    source "$SCRIPT_PATH"
    parse_arguments --completion-signal "CUSTOM_SIGNAL"
    
    assert_equal "$COMPLETION_SIGNAL" "CUSTOM_SIGNAL"
}

@test "parse_arguments handles completion-threshold flag" {
    source "$SCRIPT_PATH"
    parse_arguments --completion-threshold 5
    
    assert_equal "$COMPLETION_THRESHOLD" "5"
}

@test "parse_arguments sets default completion values" {
    source "$SCRIPT_PATH"
    
    assert_equal "$COMPLETION_SIGNAL" "CONTINUOUS_CLAUDE_PROJECT_COMPLETE"
    assert_equal "$COMPLETION_THRESHOLD" "3"
}

@test "validate_arguments fails with invalid completion-threshold" {
    source "$SCRIPT_PATH"
    PROMPT="test"
    MAX_RUNS="5"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"
    COMPLETION_THRESHOLD="invalid"
    
    run validate_arguments
    assert_failure
    assert_output --partial "Error: --completion-threshold must be a positive integer"
}

@test "validate_arguments fails with zero completion-threshold" {
    source "$SCRIPT_PATH"
    PROMPT="test"
    MAX_RUNS="5"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"
    COMPLETION_THRESHOLD="0"
    
    run validate_arguments
    assert_failure
    assert_output --partial "Error: --completion-threshold must be a positive integer"
}

@test "validate_arguments passes with valid completion-threshold" {
    source "$SCRIPT_PATH"
    PROMPT="test"
    MAX_RUNS="5"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"
    COMPLETION_THRESHOLD="5"
    
    run validate_arguments
    assert_success
}

@test "completion signal detection increments counter" {
    source "$SCRIPT_PATH"
    
    # Initialize variables
    completion_signal_count=0
    total_cost=0
    COMPLETION_SIGNAL="TEST_COMPLETE"
    COMPLETION_THRESHOLD=3
    ENABLE_COMMITS="false"
    
    # Mock result with completion signal
    result='{"result": "Work done. TEST_COMPLETE", "total_cost_usd": 0.1}'
    
    # Mock git commands
    function git() { return 0; }
    export -f git
    
    run handle_iteration_success "(1/3)" "$result" "" "main"
    
    assert_success
    assert_output --partial "Completion signal detected (1/3)"
    # Check that counter was incremented (we'll verify this in integration test)
}

@test "completion signal detection resets counter when not found" {
    source "$SCRIPT_PATH"
    
    # Initialize variables with existing count
    completion_signal_count=2
    total_cost=0
    COMPLETION_SIGNAL="TEST_COMPLETE"
    COMPLETION_THRESHOLD=3
    ENABLE_COMMITS="false"
    
    # Mock result without completion signal
    result='{"result": "Work in progress", "total_cost_usd": 0.1}'
    
    # Mock git commands
    function git() { return 0; }
    export -f git
    
    run handle_iteration_success "(1/3)" "$result" "" "main"
    
    assert_success
    assert_output --partial "Completion signal not found, resetting counter"
}

@test "completion signal case sensitive match" {
    source "$SCRIPT_PATH"
    
    completion_signal_count=0
    total_cost=0
    COMPLETION_SIGNAL="PROJECT_COMPLETE"
    COMPLETION_THRESHOLD=3
    ENABLE_COMMITS="false"
    
    # Test with wrong case - should NOT match
    result='{"result": "project_complete", "total_cost_usd": 0.1}'
    
    function git() { return 0; }
    export -f git
    
    run handle_iteration_success "(1/3)" "$result" "" "main"
    
    assert_success
    # Should not see the detection message
    refute_output --partial "Completion signal detected"
}

@test "completion signal partial match works" {
    source "$SCRIPT_PATH"
    
    completion_signal_count=0
    total_cost=0
    COMPLETION_SIGNAL="DONE"
    COMPLETION_THRESHOLD=3
    ENABLE_COMMITS="false"
    
    # Signal in middle of text
    result='{"result": "All work is DONE and committed", "total_cost_usd": 0.1}'
    
    function git() { return 0; }
    export -f git
    
    run handle_iteration_success "(1/3)" "$result" "" "main"
    
    assert_success
    assert_output --partial "Completion signal detected (1/3)"
}

@test "completion signal detection works for Codex agent messages" {
    source "$SCRIPT_PATH"

    AGENT_PROVIDER="codex"
    completion_signal_count=0
    total_cost=0
    COMPLETION_SIGNAL="PROJECT_DONE"
    COMPLETION_THRESHOLD=2
    ENABLE_COMMITS="false"

    local result='{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"All finished PROJECT_DONE"}}
{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":20}}'

    function git() { return 0; }
    export -f git

    run handle_iteration_success "(1/2)" "$result" "" "main"

    assert_success
    assert_output --partial "Completion signal detected (1/2)"
    assert_output --partial "Tokens: input 100, cached input 0, output 20"
}

@test "show_completion_summary shows signal message" {
    source "$SCRIPT_PATH"
    
    completion_signal_count=3
    total_cost=0.5
    COMPLETION_THRESHOLD=3
    MAX_RUNS=10
    
    run show_completion_summary
    
    assert_success
    assert_output --partial "Project completed! Detected completion signal 3 times in a row"
    assert_output --partial "Total cost: \$0.500"
}

@test "show_completion_summary shows signal message without cost" {
    source "$SCRIPT_PATH"
    
    completion_signal_count=3
    total_cost=0
    COMPLETION_THRESHOLD=3
    MAX_RUNS=10
    
    run show_completion_summary
    
    assert_success
    assert_output --partial "Project completed! Detected completion signal 3 times in a row"
    refute_output --partial "Total cost"
}

@test "run_claude_iteration captures stderr to error log" {
    source "$SCRIPT_PATH"
    
    # Mock claude to output to stderr
    function claude() {
        echo "This is an error message" >&2
        return 1
    }
    export -f claude
    
    # Create temp error log
    local error_log=$(mktemp)
    
    # Run the function (should fail)
    run run_claude_iteration "test prompt" "--output-format json" "$error_log"
    
    # Should fail
    assert_failure
    
    # Error log should contain the error message
    assert [ -f "$error_log" ]
    assert [ -s "$error_log" ]
    local error_content=$(cat "$error_log")
    assert_equal "$error_content" "This is an error message"
    
    rm -f "$error_log"
}

@test "run_claude_iteration handles empty stderr on failure" {
    source "$SCRIPT_PATH"
    
    # Mock claude to fail silently
    function claude() {
        return 1
    }
    export -f claude
    
    # Create temp error log
    local error_log=$(mktemp)
    
    # Run the function (should fail)
    run run_claude_iteration "test prompt" "--output-format json" "$error_log"
    
    # Should fail
    assert_failure
    
    # Error log should contain fallback message
    assert [ -f "$error_log" ]
    assert [ -s "$error_log" ]
    
    # Check the error log file contents
    local error_content=$(cat "$error_log")
    
    # Check for the main error message
    if ! echo "$error_content" | grep -q "Claude Code exited with code 1 but produced no error output"; then
        fail "Error log should contain main error message"
    fi
    
    # Check that helpful guidance is included
    if ! echo "$error_content" | grep -q "This usually means:"; then
        fail "Error log should contain troubleshooting tips"
    fi
    
    if ! echo "$error_content" | grep -q "Try running this command directly"; then
        fail "Error log should contain command suggestion"
    fi
    
    rm -f "$error_log"
}

@test "run_claude_iteration dry run mode" {
    source "$SCRIPT_PATH"
    
    DRY_RUN="true"
    local error_log=$(mktemp)
    
    # Run in dry run mode
    run run_claude_iteration "test prompt" "--output-format json" "$error_log"
    
    # Should succeed
    assert_success
    
    # Should output dry run message to stderr
    assert_output --partial "(DRY RUN) Would run Claude Code"
    
    rm -f "$error_log"
}

@test "run_claude_iteration extracts error from JSON stdout" {
    source "$SCRIPT_PATH"
    
    # Mock claude to output JSON error to stdout (like "Session limit reached")
    function claude() {
        echo '{"type":"result","is_error":true,"result":"Session limit reached ∙ resets 7pm"}' >&1
        return 1
    }
    # Mock jq to be available
    function jq() {
        command jq "$@"
    }
    export -f claude jq
    
    # Create temp error log
    local error_log=$(mktemp)
    
    # Run the function (should fail)
    run run_claude_iteration "test prompt" "--output-format json" "$error_log"
    
    # Should fail
    assert_failure
    
    # Error log should contain the extracted error message
    assert [ -f "$error_log" ]
    assert [ -s "$error_log" ]
    
    local error_content=$(cat "$error_log")
    
    # Check that the error message was extracted from JSON
    if ! echo "$error_content" | grep -q "Session limit reached"; then
        echo "Expected error log to contain 'Session limit reached', but got:"
        echo "$error_content"
        fail "Error log should contain extracted JSON error message"
    fi
    
    rm -f "$error_log"
}

@test "run_agent_iteration executes Codex provider and returns JSONL" {
    source "$SCRIPT_PATH"
    AGENT_PROVIDER="codex"

    function codex() {
        if [ "$1" != "exec" ]; then
            echo "expected codex exec" >&2
            return 1
        fi
        echo '{"type":"thread.started","thread_id":"abc"}'
        echo '{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"hello from codex"}}'
        echo '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":20}}'
        return 0
    }
    export -f codex

    local error_log=$(mktemp)
    local display_log=$(mktemp)
    local result
    result=$(run_agent_iteration "test prompt" "$CODEX_ADDITIONAL_FLAGS" "$error_log" "(1/1)" 2>"$display_log")

    run parse_agent_result "$result"
    assert_success
    assert_output "success"

    run extract_agent_result_text "$result"
    assert_success
    assert_output "hello from codex"

    assert [ ! -s "$error_log" ]
    assert grep -q "hello from codex" "$display_log"

    rm -f "$error_log" "$display_log"
}

@test "run_agent_iteration captures Codex stderr to error log" {
    source "$SCRIPT_PATH"
    AGENT_PROVIDER="codex"

    function codex() {
        echo "Codex auth failed" >&2
        return 1
    }
    export -f codex

    local error_log=$(mktemp)

    run run_agent_iteration "test prompt" "$CODEX_ADDITIONAL_FLAGS" "$error_log" "(1/1)"

    assert_failure
    assert [ -s "$error_log" ]
    local error_content=$(cat "$error_log")
    assert_equal "$error_content" "Codex auth failed"

    rm -f "$error_log"
}

@test "run_agent_iteration clears stale Codex error log before JSON error extraction" {
    source "$SCRIPT_PATH"
    AGENT_PROVIDER="codex"

    function codex() {
        echo '{"type":"error","message":"Fresh Codex JSON failure"}'
        return 1
    }
    export -f codex

    local error_log=$(mktemp)
    echo "stale previous error" > "$error_log"

    run run_agent_iteration "test prompt" "$CODEX_ADDITIONAL_FLAGS" "$error_log" "(1/1)"

    assert_failure
    assert [ -s "$error_log" ]
    local error_content=$(cat "$error_log")
    assert_equal "$error_content" "Fresh Codex JSON failure"

    rm -f "$error_log"
}

@test "run_agent_prompt_quiet uses Codex provider" {
    source "$SCRIPT_PATH"
    AGENT_PROVIDER="codex"

    local args_file="$BATS_TEST_TMPDIR/codex_args"
    function codex() {
        printf '%s\n' "$@" > "$args_file"
        return 0
    }
    export -f codex
    export args_file

    run run_agent_prompt_quiet "commit please"

    assert_success
    assert [ -f "$args_file" ]
    run grep -q "exec" "$args_file"
    assert_success
    run grep -q "commit please" "$args_file"
    assert_success
}

@test "get_latest_version returns version when gh is available" {
    source "$SCRIPT_PATH"
    
    # Mock gh to return a properly formatted JSON for jq
    function gh() {
        if [ "$1" = "release" ] && [ "$2" = "view" ]; then
            # Return JSON with correct format that includes jq processing
            local args=("$@")
            for ((i=0; i<${#args[@]}; i++)); do
                if [ "${args[i]}" = "--jq" ]; then
                    # Return just the tagName value
                    echo "v0.10.0"
                    return 0
                fi
            done
            echo '{"tagName":"v0.10.0"}'
        fi
    }
    export -f gh
    
    run get_latest_version
    
    assert_success
    assert_output "v0.10.0"
}

@test "get_latest_version fails when gh is not available" {
    source "$SCRIPT_PATH"
    
    # Mock command to fail only for gh
    function command() {
        if [ "$2" = "gh" ]; then
            return 1
        fi
        builtin command "$@"
    }
    export -f command
    
    run get_latest_version
    
    assert_failure
}

@test "compare_versions detects equal versions" {
    source "$SCRIPT_PATH"
    
    run compare_versions "v0.9.1" "v0.9.1"
    assert [ $status -eq 0 ]
    
    run compare_versions "0.9.1" "v0.9.1"
    assert [ $status -eq 0 ]
}

@test "compare_versions detects older version" {
    source "$SCRIPT_PATH"
    
    run compare_versions "v0.9.1" "v0.10.0"
    assert [ $status -eq 1 ]
    
    run compare_versions "v0.9.1" "v0.9.2"
    assert [ $status -eq 1 ]
}

@test "compare_versions detects newer version" {
    source "$SCRIPT_PATH"
    
    run compare_versions "v0.10.0" "v0.9.1"
    assert [ $status -eq 2 ]
    
    run compare_versions "v1.0.0" "v0.9.1"
    assert [ $status -eq 2 ]
}

@test "compare_versions handles pre-release versions" {
    source "$SCRIPT_PATH"
    
    # Pre-release suffixes should be stripped for comparison
    run compare_versions "v1.0.0-beta" "v1.0.0"
    assert [ $status -eq 0 ]
    
    run compare_versions "v1.0.0-rc1" "v1.0.0-rc2"
    assert [ $status -eq 0 ]
    
    run compare_versions "v1.0.0-beta" "v1.0.1"
    assert [ $status -eq 1 ]
}

@test "get_script_path returns script path" {
    source "$SCRIPT_PATH"
    
    # Mock readlink and realpath
    function readlink() {
        if [ "$1" = "-f" ]; then
            echo "/usr/local/bin/continuous-claude"
            return 0
        fi
        return 1
    }
    export -f readlink
    
    run get_script_path
    
    assert_success
    assert_output "/usr/local/bin/continuous-claude"
}

@test "download_and_install_update downloads and replaces script" {
    source "$SCRIPT_PATH"
    
    # Create a temporary script to act as the current script
    local temp_script=$(mktemp)
    echo "#!/bin/bash" > "$temp_script"
    echo "echo 'old version'" >> "$temp_script"
    chmod +x "$temp_script"
    
    # Mock curl to write a new script and checksum file
    function curl() {
        local output_file=""
        for ((i=1; i<=$#; i++)); do
            if [ "${!i}" = "-o" ]; then
                ((i++))
                output_file="${!i}"
                break
            fi
        done
        
        if [ -n "$output_file" ]; then
            # Check if this is the checksum file or the script file
            if [[ "$output_file" == *".sha256"* ]] || [[ "${@}" == *".sha256"* ]]; then
                # Write a dummy checksum
                echo "dummychecksum123456789  continuous_claude.sh" > "$output_file"
            else
                # Write the new script
                echo "#!/bin/bash" > "$output_file"
                echo "echo 'new version'" >> "$output_file"
            fi
            return 0
        fi
        return 1
    }
    
    # Mock sha256sum to return matching checksum
    function sha256sum() {
        echo "dummychecksum123456789  $1"
    }
    
    export -f curl sha256sum
    
    run download_and_install_update "v0.10.0" "$temp_script"
    
    assert_success
    assert_output --partial "Updated to version v0.10.0"
    
    # Verify the script was replaced
    local content=$(cat "$temp_script")
    if ! echo "$content" | grep -q "new version"; then
        fail "Script was not replaced with new version"
    fi
    
    rm -f "$temp_script"
}

@test "download_and_install_update preserves execute permissions" {
    source "$SCRIPT_PATH"
    
    # Create a temporary script with execute permissions
    local temp_script=$(mktemp)
    echo "#!/bin/bash" > "$temp_script"
    echo "echo 'old version'" >> "$temp_script"
    chmod +x "$temp_script"
    
    # Verify initial permissions include execute
    if [ ! -x "$temp_script" ]; then
        fail "Initial script should be executable"
    fi
    
    # Mock curl to write a new script (without execute permissions) and checksum
    function curl() {
        local output_file=""
        for ((i=1; i<=$#; i++)); do
            if [ "${!i}" = "-o" ]; then
                ((i++))
                output_file="${!i}"
                break
            fi
        done
        
        if [ -n "$output_file" ]; then
            # Check if this is the checksum file or the script file
            if [[ "$output_file" == *".sha256"* ]] || [[ "${@}" == *".sha256"* ]]; then
                # Write a dummy checksum
                echo "dummychecksum123456789  continuous_claude.sh" > "$output_file"
            else
                # Write the new script without execute permissions
                echo "#!/bin/bash" > "$output_file"
                echo "echo 'new version'" >> "$output_file"
                # Note: curl doesn't set execute permissions
            fi
            return 0
        fi
        return 1
    }
    
    # Mock sha256sum to return matching checksum
    function sha256sum() {
        echo "dummychecksum123456789  $1"
    }
    
    export -f curl sha256sum
    
    run download_and_install_update "v0.10.0" "$temp_script"
    
    assert_success
    
    # Verify the script is still executable after update
    if [ ! -x "$temp_script" ]; then
        fail "Script should remain executable after update"
    fi
    
    rm -f "$temp_script"
}

@test "download_and_install_update fails on download error" {
    source "$SCRIPT_PATH"
    
    local temp_script=$(mktemp)
    
    # Mock curl to fail
    function curl() {
        return 1
    }
    export -f curl
    
    run download_and_install_update "v0.10.0" "$temp_script"
    
    assert_failure
    assert_output --partial "Failed to download update"
    
    rm -f "$temp_script"
}

@test "check_for_updates with skip_prompt does not prompt" {
    source "$SCRIPT_PATH"
    
    VERSION="v0.9.1"
    
    # Mock get_latest_version
    function get_latest_version() {
        echo "v0.10.0"
        return 0
    }
    export -f get_latest_version
    
    run check_for_updates true
    
    assert_success
    assert_output --partial "A new version of continuous-claude is available"
    refute_output --partial "Would you like to update now?"
}

@test "parse_update_flags handles auto-update and disable-updates" {
    source "$SCRIPT_PATH"
    AUTO_UPDATE="false"
    DISABLE_UPDATES="false"
    
    parse_update_flags --auto-update --disable-updates
    
    assert_equal "$AUTO_UPDATE" "true"
    assert_equal "$DISABLE_UPDATES" "true"
}

@test "check_for_updates skips when updates disabled" {
    source "$SCRIPT_PATH"
    
    DISABLE_UPDATES="true"
    function get_latest_version() {
        echo "should not run"
        return 1
    }
    export -f get_latest_version
    
    run check_for_updates false
    
    assert_success
    assert_output ""
}

@test "handle_update_command skips when updates disabled" {
    source "$SCRIPT_PATH"
    
    DISABLE_UPDATES="true"
    
    run handle_update_command
    
    assert_success
    assert_output --partial "Updates are disabled via --disable-updates flag"
}

@test "handle_update_command auto-updates without prompt" {
    source "$SCRIPT_PATH"
    
    AUTO_UPDATE="true"
    DISABLE_UPDATES="false"
    VERSION="v0.10.0"
    
    function get_latest_version() {
        echo "v0.11.0"
        return 0
    }
    
    local flag_file="$BATS_TEST_TMPDIR/auto_update_called"
    rm -f "$flag_file"
    
    function download_and_install_update() {
        echo "called" > "$flag_file"
        return 0
    }
    
    function get_script_path() {
        echo "/tmp/mock-script"
    }
    
    export -f get_latest_version download_and_install_update get_script_path
    
    run handle_update_command
    
    assert_success
    assert_output --partial "Update complete! Version v0.11.0 is now installed."
    refute_output --partial "Would you like to update now?"
    assert [ -f "$flag_file" ]
}

@test "handle_update_command shows already on latest when versions match" {
    source "$SCRIPT_PATH"
    
    VERSION="v0.10.0"
    
    # Mock get_latest_version
    function get_latest_version() {
        echo "v0.10.0"
        return 0
    }
    export -f get_latest_version
    
    run handle_update_command
    
    assert_success
    assert_output --partial "You're already on the latest version"
}

@test "handle_update_command shows newer version message when ahead" {
    source "$SCRIPT_PATH"
    
    VERSION="v1.0.0"
    
    # Mock get_latest_version
    function get_latest_version() {
        echo "v0.10.0"
        return 0
    }
    export -f get_latest_version
    
    run handle_update_command
    
    assert_success
    assert_output --partial "You're on a newer version"
}

@test "detect_github_repo detects HTTPS URL" {
    source "$SCRIPT_PATH"
    
    # Mock git commands
    function git() {
        if [ "$1" = "rev-parse" ] && [ "$2" = "--git-dir" ]; then
            return 0
        elif [ "$1" = "remote" ] && [ "$2" = "get-url" ] && [ "$3" = "origin" ]; then
            echo "https://github.com/testowner/testrepo.git"
            return 0
        fi
        return 1
    }
    export -f git
    
    run detect_github_repo
    
    assert_success
    assert_output "testowner testrepo"
}

@test "detect_github_repo detects HTTPS URL without .git" {
    source "$SCRIPT_PATH"
    
    # Mock git commands
    function git() {
        if [ "$1" = "rev-parse" ] && [ "$2" = "--git-dir" ]; then
            return 0
        elif [ "$1" = "remote" ] && [ "$2" = "get-url" ] && [ "$3" = "origin" ]; then
            echo "https://github.com/testowner/testrepo"
            return 0
        fi
        return 1
    }
    export -f git
    
    run detect_github_repo
    
    assert_success
    assert_output "testowner testrepo"
}

@test "detect_github_repo detects SSH URL" {
    source "$SCRIPT_PATH"
    
    # Mock git commands
    function git() {
        if [ "$1" = "rev-parse" ] && [ "$2" = "--git-dir" ]; then
            return 0
        elif [ "$1" = "remote" ] && [ "$2" = "get-url" ] && [ "$3" = "origin" ]; then
            echo "git@github.com:testowner/testrepo.git"
            return 0
        fi
        return 1
    }
    export -f git
    
    run detect_github_repo
    
    assert_success
    assert_output "testowner testrepo"
}

@test "detect_github_repo detects SSH URL without .git" {
    source "$SCRIPT_PATH"
    
    # Mock git commands
    function git() {
        if [ "$1" = "rev-parse" ] && [ "$2" = "--git-dir" ]; then
            return 0
        elif [ "$1" = "remote" ] && [ "$2" = "get-url" ] && [ "$3" = "origin" ]; then
            echo "git@github.com:testowner/testrepo"
            return 0
        fi
        return 1
    }
    export -f git
    
    run detect_github_repo
    
    assert_success
    assert_output "testowner testrepo"
}

@test "detect_github_repo fails when not in git repo" {
    source "$SCRIPT_PATH"
    
    # Mock git to fail
    function git() {
        if [ "$1" = "rev-parse" ] && [ "$2" = "--git-dir" ]; then
            return 1
        fi
        return 1
    }
    export -f git
    
    run detect_github_repo
    
    assert_failure
}

@test "detect_github_repo fails when no origin remote" {
    source "$SCRIPT_PATH"
    
    # Mock git commands
    function git() {
        if [ "$1" = "rev-parse" ] && [ "$2" = "--git-dir" ]; then
            return 0
        elif [ "$1" = "remote" ] && [ "$2" = "get-url" ] && [ "$3" = "origin" ]; then
            return 1
        fi
        return 1
    }
    export -f git
    
    run detect_github_repo
    
    assert_failure
}

@test "detect_github_repo fails for non-GitHub URL" {
    source "$SCRIPT_PATH"
    
    # Mock git commands
    function git() {
        if [ "$1" = "rev-parse" ] && [ "$2" = "--git-dir" ]; then
            return 0
        elif [ "$1" = "remote" ] && [ "$2" = "get-url" ] && [ "$3" = "origin" ]; then
            echo "https://gitlab.com/testowner/testrepo.git"
            return 0
        fi
        return 1
    }
    export -f git
    
    run detect_github_repo
    
    assert_failure
}

@test "validate_arguments auto-detects owner and repo" {
    source "$SCRIPT_PATH"
    
    # Set up environment
    PROMPT="test"
    MAX_RUNS="5"
    ENABLE_COMMITS="true"
    GITHUB_OWNER=""
    GITHUB_REPO=""
    
    # Mock detect_github_repo
    function detect_github_repo() {
        echo "autoowner autorepo"
        return 0
    }
    export -f detect_github_repo
    
    # Call validate_arguments directly (not with run) so variable changes persist
    validate_arguments
    
    assert_equal "$GITHUB_OWNER" "autoowner"
    assert_equal "$GITHUB_REPO" "autorepo"
}

@test "validate_arguments uses provided owner over auto-detect" {
    source "$SCRIPT_PATH"
    
    # Set up environment
    PROMPT="test"
    MAX_RUNS="5"
    ENABLE_COMMITS="true"
    GITHUB_OWNER="manualowner"
    GITHUB_REPO=""
    
    # Mock detect_github_repo
    function detect_github_repo() {
        echo "autoowner autorepo"
        return 0
    }
    export -f detect_github_repo
    
    # Call validate_arguments directly (not with run) so variable changes persist
    validate_arguments
    
    assert_equal "$GITHUB_OWNER" "manualowner"
    assert_equal "$GITHUB_REPO" "autorepo"
}

@test "validate_arguments uses provided repo over auto-detect" {
    source "$SCRIPT_PATH"
    
    # Set up environment
    PROMPT="test"
    MAX_RUNS="5"
    ENABLE_COMMITS="true"
    GITHUB_OWNER=""
    GITHUB_REPO="manualrepo"
    
    # Mock detect_github_repo
    function detect_github_repo() {
        echo "autoowner autorepo"
        return 0
    }
    export -f detect_github_repo
    
    # Call validate_arguments directly (not with run) so variable changes persist
    validate_arguments
    
    assert_equal "$GITHUB_OWNER" "autoowner"
    assert_equal "$GITHUB_REPO" "manualrepo"
}

@test "validate_arguments fails when auto-detect fails and no flags provided" {
    source "$SCRIPT_PATH"
    
    # Set up environment
    PROMPT="test"
    MAX_RUNS="5"
    ENABLE_COMMITS="true"
    GITHUB_OWNER=""
    GITHUB_REPO=""
    
    # Mock detect_github_repo to fail
    function detect_github_repo() {
        return 1
    }
    export -f detect_github_repo
    
    run validate_arguments
    
    assert_failure
    assert_output --partial "GitHub owner is required"
}

@test "parse_duration parses hours correctly" {
    source "$SCRIPT_PATH"
    
    run parse_duration "2h"
    assert_success
    assert_output "7200"
    
    run parse_duration "1h"
    assert_success
    assert_output "3600"
}

@test "parse_duration parses minutes correctly" {
    source "$SCRIPT_PATH"
    
    run parse_duration "30m"
    assert_success
    assert_output "1800"
    
    run parse_duration "90m"
    assert_success
    assert_output "5400"
}

@test "parse_duration parses seconds correctly" {
    source "$SCRIPT_PATH"
    
    run parse_duration "45s"
    assert_success
    assert_output "45"
    
    run parse_duration "120s"
    assert_success
    assert_output "120"
}

@test "parse_duration parses combined durations" {
    source "$SCRIPT_PATH"
    
    run parse_duration "1h30m"
    assert_success
    assert_output "5400"
    
    run parse_duration "2h15m30s"
    assert_success
    assert_output "8130"
    
    run parse_duration "45m30s"
    assert_success
    assert_output "2730"
}

@test "parse_duration handles whitespace" {
    source "$SCRIPT_PATH"
    
    run parse_duration "1h 30m"
    assert_success
    assert_output "5400"
    
    run parse_duration " 2h "
    assert_success
    assert_output "7200"
}

@test "parse_duration fails with invalid format" {
    source "$SCRIPT_PATH"
    
    run parse_duration "2x"
    assert_failure
    
    run parse_duration "abc"
    assert_failure
    
    run parse_duration ""
    assert_failure
    
    run parse_duration "0h"
    assert_failure
}

@test "parse_duration case insensitive" {
    source "$SCRIPT_PATH"
    
    run parse_duration "2H"
    assert_success
    assert_output "7200"
    
    run parse_duration "30M"
    assert_success
    assert_output "1800"
    
    run parse_duration "45S"
    assert_success
    assert_output "45"
}

@test "format_duration formats correctly" {
    source "$SCRIPT_PATH"
    
    run format_duration 7200
    assert_success
    assert_output "2h"
    
    run format_duration 1800
    assert_success
    assert_output "30m"
    
    run format_duration 45
    assert_success
    assert_output "45s"
    
    run format_duration 5400
    assert_success
    assert_output "1h30m"
    
    run format_duration 8130
    assert_success
    assert_output "2h15m30s"
}

@test "format_duration handles zero" {
    source "$SCRIPT_PATH"
    
    run format_duration 0
    assert_success
    assert_output "0s"
}

@test "parse_arguments handles max-duration flag" {
    source "$SCRIPT_PATH"
    parse_arguments --max-duration "2h"
    
    assert_equal "$MAX_DURATION" "2h"
}

@test "validate_arguments accepts max-duration" {
    source "$SCRIPT_PATH"
    PROMPT="test"
    MAX_RUNS=""
    MAX_COST=""
    MAX_DURATION="2h"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"
    
    # Call validate_arguments directly (not with run) so variable changes persist
    validate_arguments
    
    # After validation, MAX_DURATION should be converted to seconds
    assert_equal "$MAX_DURATION" "7200"
}

@test "validate_arguments fails without max-runs, max-cost, or max-duration" {
    source "$SCRIPT_PATH"
    PROMPT="test"
    MAX_RUNS=""
    MAX_COST=""
    MAX_DURATION=""
    
    run validate_arguments
    assert_failure
    assert_output --partial "Error: Either --max-runs, --max-cost, or --max-duration is required"
}

@test "validate_arguments fails with invalid max-duration format" {
    source "$SCRIPT_PATH"
    PROMPT="test"
    MAX_RUNS=""
    MAX_COST=""
    MAX_DURATION="invalid"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"
    
    run validate_arguments
    assert_failure
    assert_output --partial "Error: --max-duration must be a valid duration"
}

@test "validate_arguments accepts max-duration with max-runs" {
    source "$SCRIPT_PATH"
    PROMPT="test"
    MAX_RUNS="5"
    MAX_COST=""
    MAX_DURATION="1h"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"
    
    run validate_arguments
    assert_success
}

@test "validate_arguments accepts max-duration with max-cost" {
    source "$SCRIPT_PATH"
    PROMPT="test"
    MAX_RUNS=""
    MAX_COST="10.00"
    MAX_DURATION="30m"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"
    
    run validate_arguments
    assert_success
}

@test "continuous_claude_commit dry run shows PR merged message with placeholder" {
    source "$SCRIPT_PATH"
    
    DRY_RUN="true"
    ENABLE_COMMITS="true"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"
    
    # Mock git to return mock branch and indicate changes exist
    function git() {
        case "$1" in
            rev-parse)
                if [ "$2" = "--git-dir" ]; then
                    return 0
                elif [ "$2" = "--abbrev-ref" ]; then
                    echo "main"
                fi
                ;;
            diff)
                return 1  # Indicate there are changes (non-zero = changes exist)
                ;;
            ls-files)
                echo ""  # No untracked files
                ;;
            checkout|branch)
                return 0
                ;;
        esac
        return 0
    }
    export -f git
    
    # Run the function with test branch name and main branch
    run continuous_claude_commit "(1/1)" "test-branch" "main"
    
    assert_success
    assert_output --partial "(DRY RUN) PR merged: <commit title would appear here>"
}

@test "continuous_claude_commit creates PR when branch already has committed changes" {
    source "$SCRIPT_PATH"
    
    ENABLE_COMMITS="true"
    DRY_RUN="false"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"
    
    function git() {
        case "$1 $2 $3 $4" in
            "rev-parse --git-dir"*)
                return 0
                ;;
            "diff --quiet --ignore-submodules=dirty"*)
                return 0
                ;;
            "diff --cached --quiet --ignore-submodules=dirty"*)
                return 0
                ;;
            "ls-files --others --exclude-standard"*)
                echo ""
                ;;
            "rev-list --count main..test-branch"*)
                echo "1"
                ;;
            "log -1 --format=%B"*)
                echo "Test commit message"
                ;;
            "push -u origin test-branch"*)
                return 0
                ;;
            checkout*|branch*)
                return 0
                ;;
        esac
        return 0
    }
    export -f git
    
    function claude() {
        echo "claude should not be called when changes are already committed" >&2
        return 99
    }
    export -f claude
    
    function gh() {
        if [ "$1" = "pr" ] && [ "$2" = "create" ]; then
            echo "https://github.com/user/repo/pull/123"
            return 0
        fi
        return 1
    }
    export -f gh
    
    function wait_for_pr_checks() { return 0; }
    function merge_pr_and_cleanup() { return 0; }
    function sleep() { return 0; }
    export -f wait_for_pr_checks merge_pr_and_cleanup sleep
    
    run continuous_claude_commit "(1/1)" "test-branch" "main"
    
    assert_success
    assert_output --partial "Changes already committed on branch: test-branch (1 commit(s) ahead)"
    refute_output --partial "claude should not be called"
}

@test "merge_pr_and_cleanup surfaces GitHub plan restriction errors" {
    source "$SCRIPT_PATH"

    MERGE_STRATEGY="squash"

    function gh() {
        if [ "$1" = "pr" ] && [ "$2" = "update-branch" ]; then
            echo "already up-to-date"
            return 1
        fi
        if [ "$1" = "pr" ] && [ "$2" = "merge" ]; then
            echo "HTTP 403: Upgrade to GitHub Pro or make this repository public to enable this feature." >&2
            return 1
        fi
        return 1
    }
    export -f gh

    run merge_pr_and_cleanup "123" "owner" "repo" "test-branch" "(1/1)" "main"

    assert_failure
    assert_output --partial "Failed to merge PR: HTTP 403: Upgrade to GitHub Pro"
    assert_output --partial "not a merge queue failure"
}

@test "handle_iteration_success reports PR workflow failure instead of merge queue failure" {
    source "$SCRIPT_PATH"

    ENABLE_COMMITS="true"
    DISABLE_BRANCHES="false"
    error_count=0
    extra_iterations=0

    function continuous_claude_commit() {
        return 1
    }
    export -f continuous_claude_commit

    run handle_iteration_success "(1/1)" '{"result":"ok","total_cost_usd":0}' "test-branch" "main"

    assert_failure
    assert_output --partial "PR workflow failed"
    refute_output --partial "PR merge queue failed"
}

@test "wait_for_pr_checks prints initial waiting message once" {
    source "$SCRIPT_PATH"
    
    # Use a counter that persists across function calls
    echo "0" > "$BATS_TEST_TMPDIR/gh_call_count"
    
    # Mock gh to return empty checks for first call, then return checks to exit quickly
    function gh() {
        if [ "$1" = "pr" ] && [ "$2" = "checks" ]; then
            local count=$(cat "$BATS_TEST_TMPDIR/gh_call_count")
            count=$((count + 1))
            echo "$count" > "$BATS_TEST_TMPDIR/gh_call_count"
            
            if [ $count -eq 1 ]; then
                # First call: return empty checks to trigger waiting message
                echo "[]"
            else
                # Second call: return checks to exit quickly
                echo '[{"state": "completed", "bucket": "success"}]'
            fi
            return 0
        elif [ "$1" = "pr" ] && [ "$2" = "view" ]; then
            echo '{"reviewDecision": "APPROVED", "reviewRequests": []}'
            return 0
        fi
        return 1
    }
    
    # Mock sleep to avoid actual waiting
    function sleep() {
        return 0
    }
    
    export -f gh sleep
    
    # Run the function - it should complete quickly with mocked sleep
    run bash -c "
        source '$SCRIPT_PATH'
        wait_for_pr_checks 123 'owner' 'repo' '(1/1)' 2>&1
    "
    
    # Should contain the initial waiting message
    assert_output --partial "⏳ Waiting for checks to start"
    # Should contain at least one dot
    assert_output --partial "."
    
    rm -f "$BATS_TEST_TMPDIR/gh_call_count"
}

@test "wait_for_pr_checks prints dots on each waiting iteration" {
    source "$SCRIPT_PATH"
    
    # Use a counter that persists across function calls
    echo "0" > "$BATS_TEST_TMPDIR/gh_call_count"
    
    # Mock gh to return empty checks for first few calls, then checks appear
    function gh() {
        if [ "$1" = "pr" ] && [ "$2" = "checks" ]; then
            local count=$(cat "$BATS_TEST_TMPDIR/gh_call_count")
            count=$((count + 1))
            echo "$count" > "$BATS_TEST_TMPDIR/gh_call_count"
            
            if [ $count -lt 3 ]; then
                echo "[]"
            else
                # Return checks after 3 iterations
                echo '[{"state": "completed", "bucket": "success"}]'
            fi
            return 0
        elif [ "$1" = "pr" ] && [ "$2" = "view" ]; then
            echo '{"reviewDecision": "APPROVED", "reviewRequests": []}'
            return 0
        fi
        return 1
    }
    
    # Mock sleep to avoid actual waiting
    function sleep() {
        return 0
    }
    
    export -f gh sleep
    
    # Capture stderr output
    run bash -c "
        source '$SCRIPT_PATH'
        wait_for_pr_checks 123 'owner' 'repo' '(1/1)' 2>&1
    "
    
    # Should contain multiple dots (at least 2)
    local dot_count=$(echo "$output" | grep -o '\.' | wc -l | tr -d ' ')
    assert [ "$dot_count" -ge 2 ]
    
    rm -f "$BATS_TEST_TMPDIR/gh_call_count"
}

@test "wait_for_pr_checks prints newline when checks are found after waiting" {
    source "$SCRIPT_PATH"
    
    # Use a counter that persists across function calls
    echo "0" > "$BATS_TEST_TMPDIR/gh_call_count"
    
    # Mock gh to return empty checks first, then checks appear
    function gh() {
        if [ "$1" = "pr" ] && [ "$2" = "checks" ]; then
            local count=$(cat "$BATS_TEST_TMPDIR/gh_call_count")
            count=$((count + 1))
            echo "$count" > "$BATS_TEST_TMPDIR/gh_call_count"
            
            if [ $count -le 2 ]; then
                echo "[]"
            else
                # Return checks after 2 iterations
                echo '[{"state": "completed", "bucket": "success"}]'
            fi
            return 0
        elif [ "$1" = "pr" ] && [ "$2" = "view" ]; then
            echo '{"reviewDecision": "APPROVED", "reviewRequests": []}'
            return 0
        fi
        return 1
    }
    
    # Mock sleep to avoid actual waiting
    function sleep() {
        return 0
    }
    
    export -f gh sleep
    
    # Capture stderr output
    run bash -c "
        source '$SCRIPT_PATH'
        wait_for_pr_checks 123 'owner' 'repo' '(1/1)' 2>&1
    "
    
    # Should contain the waiting message followed by dots
    assert_output --partial "⏳ Waiting for checks to start"
    # Should eventually show check status (indicating newline was printed)
    assert_output --partial "Found"
    
    rm -f "$BATS_TEST_TMPDIR/gh_call_count"
}

@test "wait_for_pr_checks does not print waiting message when checks found immediately" {
    source "$SCRIPT_PATH"

    # Mock gh to return checks immediately (no waiting)
    function gh() {
        if [ "$1" = "pr" ] && [ "$2" = "checks" ]; then
            echo '[{"state": "completed", "bucket": "success"}]'
            return 0
        elif [ "$1" = "pr" ] && [ "$2" = "view" ]; then
            echo '{"reviewDecision": "APPROVED", "reviewRequests": []}'
            return 0
        fi
        return 1
    }

    # Mock sleep to avoid actual waiting
    function sleep() {
        return 0
    }

    export -f gh sleep

    # Capture stderr output
    run bash -c "
        source '$SCRIPT_PATH'
        wait_for_pr_checks 123 'owner' 'repo' '(1/1)' 2>&1
    "

    # Should NOT contain waiting message when checks are found immediately
    refute_output --partial "⏳ Waiting for checks to start"
    # Should show check status instead
    assert_output --partial "Found"
}

@test "parse_arguments sets default CI retry enabled" {
    source "$SCRIPT_PATH"

    assert_equal "$CI_RETRY_ENABLED" "true"
    assert_equal "$CI_RETRY_MAX_ATTEMPTS" "1"
}

@test "parse_arguments handles disable-ci-retry flag" {
    source "$SCRIPT_PATH"
    CI_RETRY_ENABLED="true"
    parse_arguments --disable-ci-retry

    assert_equal "$CI_RETRY_ENABLED" "false"
}

@test "parse_arguments handles ci-retry-max flag" {
    source "$SCRIPT_PATH"
    CI_RETRY_MAX_ATTEMPTS="1"
    parse_arguments --ci-retry-max 3

    assert_equal "$CI_RETRY_MAX_ATTEMPTS" "3"
}

@test "validate_arguments fails with invalid ci-retry-max" {
    source "$SCRIPT_PATH"
    PROMPT="test"
    MAX_RUNS="5"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"
    CI_RETRY_MAX_ATTEMPTS="invalid"

    run validate_arguments
    assert_failure
    assert_output --partial "Error: --ci-retry-max must be a positive integer"
}

@test "validate_arguments fails with zero ci-retry-max" {
    source "$SCRIPT_PATH"
    PROMPT="test"
    MAX_RUNS="5"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"
    CI_RETRY_MAX_ATTEMPTS="0"

    run validate_arguments
    assert_failure
    assert_output --partial "Error: --ci-retry-max must be a positive integer"
}

@test "validate_arguments passes with valid ci-retry-max" {
    source "$SCRIPT_PATH"
    PROMPT="test"
    MAX_RUNS="5"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"
    CI_RETRY_MAX_ATTEMPTS="2"

    run validate_arguments
    assert_success
}

@test "get_failed_run_id returns run ID for failed workflow" {
    source "$SCRIPT_PATH"

    # Mock gh commands - must handle --jq flag which gh processes internally
    function gh() {
        if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
            # gh pr view ... --jq '.headRefOid' returns just the value
            echo "abc123"
            return 0
        elif [ "$1" = "run" ] && [ "$2" = "list" ]; then
            # gh run list ... --jq '.[0].databaseId' returns just the value
            echo "12345"
            return 0
        fi
        return 1
    }
    export -f gh

    run get_failed_run_id 123 "owner" "repo"

    assert_success
    assert_output "12345"
}

@test "get_failed_run_id returns failure when no failed runs" {
    source "$SCRIPT_PATH"

    # Mock gh commands
    function gh() {
        if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
            echo "abc123"
            return 0
        elif [ "$1" = "run" ] && [ "$2" = "list" ]; then
            # Return null (what jq returns for .[0].databaseId on empty array)
            echo "null"
            return 0
        fi
        return 1
    }
    export -f gh

    run get_failed_run_id 123 "owner" "repo"

    assert_failure
}

@test "get_failed_run_id returns failure when pr view fails" {
    source "$SCRIPT_PATH"

    # Mock gh commands
    function gh() {
        if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
            return 1
        fi
        return 1
    }
    export -f gh

    run get_failed_run_id 123 "owner" "repo"

    assert_failure
}

@test "continuous_claude_commit succeeds with dirty submodule" {
    source "$SCRIPT_PATH"
    
    ENABLE_COMMITS="true"
    DRY_RUN="false"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"
    
    # Mock git to simulate a repository with changes in parent repo AND a dirty submodule:
    # - has_changes will detect untracked files in parent repo
    # - After claude commits, verification will pass (ignoring dirty submodule)
    # - ls-files initially returns untracked files, then returns empty after commit
    local commit_called=false
    function git() {
        case "$1 $2 $3 $4 $5" in
            "rev-parse --git-dir"*)
                return 0
                ;;
            "rev-parse --abbrev-ref"*)
                echo "test-branch"
                ;;
            "diff --quiet"*)
                return 0  # No modified files
                ;;
            "diff --cached --quiet"*)
                return 0  # No staged files
                ;;
            "ls-files --others"*)
                # Return untracked files before commit, empty after
                if [ "$commit_called" = "false" ]; then
                    echo "newfile.txt"  # Simulates untracked file in parent repo
                else
                    echo ""  # No untracked files after commit
                fi
                ;;
            "log -1 --format=%B"*)
                echo "Test commit message"
                ;;
            "log -1 --format=%s"*)
                echo "Test commit"
                ;;
            checkout*|branch*)
                return 0
                ;;
        esac
        return 0
    }
    export -f git
    
    commit_called=false
    
    # Mock claude to succeed and mark that commit was called
    function claude() {
        commit_called=true
        return 0
    }
    export -f claude
    export commit_called
    
    # Run the function - it may fail on PR creation but commit verification should pass
    run continuous_claude_commit "(1/1)" "test-branch" "main"
    
    # Verify that commit verification passed (indicated by "Changes committed" message)
    # The function may fail later on PR creation, but that's okay - we're testing
    # that the commit verification with dirty submodules passes
    assert_output --partial "Changes committed on branch: test-branch"
}


@test "commit_on_current_branch succeeds with dirty submodule" {
    source "$SCRIPT_PATH"
    
    DRY_RUN="false"
    
    # Mock git to simulate a repository with changes in parent repo AND a dirty submodule
    local commit_called=false
    function git() {
        case "$1 $2 $3 $4 $5" in
            "rev-parse --git-dir"*)
                return 0
                ;;
            "diff --quiet"*)
                return 0  # No modified files
                ;;
            "diff --cached --quiet"*)
                return 0  # No staged files
                ;;
            "ls-files --others"*)
                # Return untracked files before commit, empty after
                if [ "$commit_called" = "false" ]; then
                    echo "newfile.txt"  # Simulates untracked file in parent repo
                else
                    echo ""  # No untracked files after commit
                fi
                ;;
            "log -1 --format=%s"*)
                echo "Test commit"
                ;;
        esac
        return 0
    }
    export -f git
    
    commit_called=false
    
    # Mock claude to succeed and mark that commit was called
    function claude() {
        commit_called=true
        return 0
    }
    export -f claude
    export commit_called
    
    # Run the function
    run commit_on_current_branch "(1/1)"
    
    # Should succeed because --ignore-submodules=dirty allows dirty submodules
    assert_success
    assert_output --partial "Committed: Test commit"
}

@test "commit_on_current_branch uses Codex provider when selected" {
    source "$SCRIPT_PATH"

    AGENT_PROVIDER="codex"
    DRY_RUN="false"
    local commit_flag="$BATS_TEST_TMPDIR/codex_commit_called"
    rm -f "$commit_flag"
    export commit_flag

    function git() {
        case "$1 $2 $3 $4 $5" in
            "rev-parse --git-dir"*)
                return 0
                ;;
            "diff --quiet"*)
                return 0
                ;;
            "diff --cached --quiet"*)
                return 0
                ;;
            "ls-files --others"*)
                if [ ! -f "$commit_flag" ]; then
                    echo "newfile.txt"
                fi
                ;;
            "log -1 --format=%s"*)
                echo "Codex commit"
                ;;
        esac
        return 0
    }
    export -f git

    function codex() {
        touch "$commit_flag"
        return 0
    }
    export -f codex

    run commit_on_current_branch "(1/1)"

    assert_success
    assert_output --partial "Committed: Codex commit"
    assert [ -f "$commit_flag" ]
}

# =========================================
# Tool logging tests
# =========================================

@test "tool logging extracts Read tool with relative path" {
    # Test the jq expression for tool extraction with relative paths
    local json='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/home/user/project/src/file.ts"}}]}}'
    local pwd="/home/user/project"

    run bash -c "echo '$json' | jq -r --arg pwd '$pwd' '
        def relpath: if startswith(\$pwd + \"/\") then .[\$pwd | length + 1:] elif . == \$pwd then \".\" else . end;
        if .type == \"assistant\" then
            .message.content[]? |
            select(.type == \"tool_use\") |
            .name + \" \" + ((.input.file_path // \"\") | relpath)
        else empty end
    '"

    assert_success
    assert_output "Read src/file.ts"
}

@test "tool logging extracts WebFetch with URL and prompt" {
    local json='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"WebFetch","input":{"url":"https://example.com/docs","prompt":"Extract the main content from this page"}}]}}'

    run bash -c "echo '$json' | jq -r '
        if .type == \"assistant\" then
            .message.content[]? |
            select(.type == \"tool_use\") |
            (.input.url // \"\") + \" → \" + ((.input.prompt // \"\") | if length > 40 then .[0:40] + \"...\" else . end)
        else empty end
    '"

    assert_success
    assert_output "https://example.com/docs → Extract the main content from this page"
}

@test "tool logging extracts WebSearch with query" {
    local json='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"WebSearch","input":{"query":"react documentation 2026"}}]}}'

    run bash -c "echo '$json' | jq -r '
        if .type == \"assistant\" then
            .message.content[]? |
            select(.type == \"tool_use\") |
            \"\\\"\" + (.input.query // \"\") + \"\\\"\"
        else empty end
    '"

    assert_success
    assert_output '"react documentation 2026"'
}

@test "tool logging extracts Task with subagent type and description" {
    local json='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Task","input":{"subagent_type":"Explore","description":"find auth files"}}]}}'

    run bash -c "echo '$json' | jq -r '
        if .type == \"assistant\" then
            .message.content[]? |
            select(.type == \"tool_use\") |
            \"[\" + (.input.subagent_type // \"agent\") + \"] \" + (.input.description // \"\")
        else empty end
    '"

    assert_success
    assert_output "[Explore] find auth files"
}

@test "tool logging extracts Grep with pattern and path" {
    local json='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Grep","input":{"pattern":"function.*test","path":"/home/user/project/src","glob":"*.ts"}}]}}'
    local pwd="/home/user/project"

    run bash -c "echo '$json' | jq -r --arg pwd '$pwd' '
        def relpath: if startswith(\$pwd + \"/\") then .[\$pwd | length + 1:] elif . == \$pwd then \".\" else . end;
        if .type == \"assistant\" then
            .message.content[]? |
            select(.type == \"tool_use\") |
            \"\\\"\" + (.input.pattern // \"\") + \"\\\"\" + (if .input.path then \" in \" + (.input.path | relpath) else \"\" end) + (if .input.glob then \" (\" + .input.glob + \")\" else \"\" end)
        else empty end
    '"

    assert_success
    assert_output '"function.*test" in src (*.ts)'
}

@test "tool logging extracts Bash command truncated" {
    local json='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"git log --oneline --graph --all --decorate --color=always | head -20"}}]}}'

    run bash -c "echo '$json' | jq -r '
        if .type == \"assistant\" then
            .message.content[]? |
            select(.type == \"tool_use\") |
            (.input.command // \"\" | split(\"\n\")[0] | if length > 80 then .[0:80] + \"...\" else . end)
        else empty end
    '"

    assert_success
    assert_output "git log --oneline --graph --all --decorate --color=always | head -20"
}

@test "tool logging shows correct emoji for Read" {
    local json='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/test.ts"}}]}}'

    run bash -c "echo '$json' | jq -r '
        if .type == \"assistant\" then
            .message.content[]? |
            select(.type == \"tool_use\") |
            if .name == \"Read\" then \"📖\" else \"other\" end
        else empty end
    '"

    assert_success
    assert_output "📖"
}

@test "tool logging shows correct emoji for WebFetch" {
    local json='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"WebFetch","input":{"url":"https://test.com"}}]}}'

    run bash -c "echo '$json' | jq -r '
        if .type == \"assistant\" then
            .message.content[]? |
            select(.type == \"tool_use\") |
            if .name == \"WebFetch\" or (.name | startswith(\"WebFetch\")) then \"🌍\" else \"other\" end
        else empty end
    '"

    assert_success
    assert_output "🌍"
}

@test "tool logging shows correct emoji for Task tools" {
    local json='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"TaskCreate","input":{"subject":"test task"}}]}}'

    run bash -c "echo '$json' | jq -r '
        if .type == \"assistant\" then
            .message.content[]? |
            select(.type == \"tool_use\") |
            if (.name | test(\"Todo|TaskCreate|TaskUpdate|TaskList|TaskGet\"; \"i\")) then \"📝\" else \"other\" end
        else empty end
    '"

    assert_success
    assert_output "📝"
}

@test "tool logging shows correct emoji for MCP tools" {
    local json='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__ide__getDiagnostics","input":{}}]}}'

    run bash -c "echo '$json' | jq -r '
        if .type == \"assistant\" then
            .message.content[]? |
            select(.type == \"tool_use\") |
            if (.name | startswith(\"mcp__\")) then \"🔌\" else \"other\" end
        else empty end
    '"

    assert_success
    assert_output "🔌"
}

@test "tool logging extracts MCP tool name correctly" {
    local json='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__ide__getDiagnostics","input":{}}]}}'

    run bash -c "echo '$json' | jq -r '
        if .type == \"assistant\" then
            .message.content[]? |
            select(.type == \"tool_use\") |
            (.name | split(\"__\") | .[1:] | join(\"/\"))
        else empty end
    '"

    assert_success
    assert_output "ide/getDiagnostics"
}

@test "tool logging handles Read with offset" {
    local json='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/home/user/project/file.ts","offset":100}}]}}'
    local pwd="/home/user/project"

    run bash -c "echo '$json' | jq -r --arg pwd '$pwd' '
        def relpath: if startswith(\$pwd + \"/\") then .[\$pwd | length + 1:] elif . == \$pwd then \".\" else . end;
        if .type == \"assistant\" then
            .message.content[]? |
            select(.type == \"tool_use\") |
            ((.input.file_path // \"\") | relpath) + (if .input.offset then \" (line \" + (.input.offset | tostring) + \")\" else \"\" end)
        else empty end
    '"

    assert_success
    assert_output "file.ts (line 100)"
}

@test "relpath function handles exact PWD match" {
    run bash -c "echo '\"/home/user/project\"' | jq -r --arg pwd '/home/user/project' '
        def relpath: if startswith(\$pwd + \"/\") then .[\$pwd | length + 1:] elif . == \$pwd then \".\" else . end;
        . | relpath
    '"

    assert_success
    assert_output "."
}

@test "parse_arguments sets default comment review enabled" {
    source "$SCRIPT_PATH"

    assert_equal "$COMMENT_REVIEW_ENABLED" "true"
    assert_equal "$COMMENT_REVIEW_MAX_ATTEMPTS" "1"
}

@test "parse_arguments handles disable-comment-review flag" {
    source "$SCRIPT_PATH"
    COMMENT_REVIEW_ENABLED="true"
    parse_arguments --disable-comment-review

    assert_equal "$COMMENT_REVIEW_ENABLED" "false"
}

@test "parse_arguments handles comment-review-max flag" {
    source "$SCRIPT_PATH"
    COMMENT_REVIEW_MAX_ATTEMPTS="1"
    parse_arguments --comment-review-max 3

    assert_equal "$COMMENT_REVIEW_MAX_ATTEMPTS" "3"
}

@test "validate_arguments fails with invalid comment-review-max" {
    source "$SCRIPT_PATH"
    PROMPT="test"
    MAX_RUNS="5"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"
    COMMENT_REVIEW_MAX_ATTEMPTS="invalid"

    run validate_arguments
    assert_failure
    assert_output --partial "Error: --comment-review-max must be a positive integer"
}

@test "validate_arguments fails with zero comment-review-max" {
    source "$SCRIPT_PATH"
    PROMPT="test"
    MAX_RUNS="5"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"
    COMMENT_REVIEW_MAX_ATTEMPTS="0"

    run validate_arguments
    assert_failure
    assert_output --partial "Error: --comment-review-max must be a positive integer"
}

@test "validate_arguments passes with valid comment-review-max" {
    source "$SCRIPT_PATH"
    PROMPT="test"
    MAX_RUNS="5"
    GITHUB_OWNER="user"
    GITHUB_REPO="repo"
    COMMENT_REVIEW_MAX_ATTEMPTS="2"

    run validate_arguments
    assert_success
}

@test "check_pr_comments returns 0 when comments exist" {
    source "$SCRIPT_PATH"

    # Mock gh api to return comment counts
    function gh() {
        if [ "$1" = "api" ]; then
            if echo "$2" | grep -q "pulls.*comments"; then
                echo "2"
                return 0
            elif echo "$2" | grep -q "issues.*comments"; then
                echo "1"
                return 0
            fi
        fi
        return 1
    }
    export -f gh

    run check_pr_comments "123" "owner" "repo" "[1/5]"
    assert_success
    assert_output --partial "Found 3 comment(s)"
}

@test "check_pr_comments returns 1 when no comments" {
    source "$SCRIPT_PATH"

    # Mock gh api to return zero comments
    function gh() {
        if [ "$1" = "api" ]; then
            echo "0"
            return 0
        fi
        return 1
    }
    export -f gh

    run check_pr_comments "123" "owner" "repo" "[1/5]"
    assert_failure
    assert_output --partial "No comments found"
}

@test "check_pr_comments with since parameter filters old comments" {
    source "$SCRIPT_PATH"

    # Mock gh api to return zero when filtering by since
    function gh() {
        if [ "$1" = "api" ]; then
            echo "0"
            return 0
        fi
        return 1
    }
    export -f gh

    run check_pr_comments "123" "owner" "repo" "[1/5]" "2026-04-03T12:00:00Z"
    assert_failure
    assert_output --partial "No comments found"
}

@test "check_pr_comments with since parameter detects new comments" {
    source "$SCRIPT_PATH"

    # Mock gh api to return comments when filtering by since
    function gh() {
        if [ "$1" = "api" ]; then
            if echo "$2" | grep -q "pulls.*comments"; then
                echo "1"
                return 0
            elif echo "$2" | grep -q "issues.*comments"; then
                echo "0"
                return 0
            fi
        fi
        return 1
    }
    export -f gh

    run check_pr_comments "123" "owner" "repo" "[1/5]" "2026-04-03T12:00:00Z"
    assert_success
    assert_output --partial "Found 1 comment(s)"
}

@test "show_help includes comment review flags" {
    source "$SCRIPT_PATH"
    export -f show_help
    run show_help
    assert_output --partial "--disable-comment-review"
    assert_output --partial "--comment-review-max"
    assert_output --partial "--review-prompt [text]"
    assert_output --partial "Uses a comprehensive default review prompt"
}

@test "relpath function handles path outside PWD" {
    run bash -c "echo '\"/other/path/file.ts\"' | jq -r --arg pwd '/home/user/project' '
        def relpath: if startswith(\$pwd + \"/\") then .[\$pwd | length + 1:] elif . == \$pwd then \".\" else . end;
        . | relpath
    '"

    assert_success
    assert_output "/other/path/file.ts"
}
