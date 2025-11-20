#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

setup() {
    # Path to the script under test
    # BATS_TEST_DIRNAME is the directory containing the test file
    SCRIPT_PATH="$BATS_TEST_DIRNAME/../continuous_claude.sh"
    export TESTING="true"
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
    run validate_arguments
    assert_failure
    assert_output --partial "Error: Either --max-runs or --max-cost is required"
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

@test "validate_requirements fails when agent is missing" {
    # Mock command to fail for claude (default agent)
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
    assert_output --partial "Agent command 'claude' is not installed"
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

@test "parse_agent_result handles valid success JSON (backward compat)" {
    source "$SCRIPT_PATH"
    run parse_agent_result '{"result": "success", "total_cost_usd": 0.1}' 0
    assert_success
    assert_output "success"
}

@test "parse_agent_result handles plain text as success with exit 0 (backward compat)" {
    source "$SCRIPT_PATH"
    # Non-JSON should be treated as success if exit code is 0
    run parse_agent_result 'plain text output' 0
    assert_success
    assert_output "success"
}

@test "parse_agent_result handles agent error JSON (backward compat)" {
    source "$SCRIPT_PATH"
    run parse_agent_result '{"is_error": true, "result": "error message"}' 0
    assert_failure
    assert_output "agent_error"
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

@test "parse_arguments handles agent flag" {
    source "$SCRIPT_PATH"
    parse_arguments --agent "codex exec {prompt}"
    
    assert_equal "$AGENT_COMMAND" "codex exec {prompt}"
}

@test "default agent is claude with flags" {
    source "$SCRIPT_PATH"
    
    assert_equal "$AGENT_COMMAND" "claude -p {prompt} --dangerously-skip-permissions --output-format json"
}

@test "parse_arguments handles agent with multiple flags" {
    source "$SCRIPT_PATH"
    parse_arguments --agent "aider --message {prompt} --yes --model gpt-4"
    
    assert_equal "$AGENT_COMMAND" "aider --message {prompt} --yes --model gpt-4"
}

@test "validate_requirements extracts base command from agent" {
    source "$SCRIPT_PATH"
    AGENT_COMMAND="myagent -p {prompt} --flag1 --flag2"
    ENABLE_COMMITS="false"
    
    # Mock command to fail for myagent
    function command() {
        if [ "$2" == "myagent" ]; then
            return 1
        fi
        return 0
    }
    export -f command
    
    run validate_requirements
    
    assert_failure
    assert_output --partial "Agent command 'myagent' is not installed"
}

@test "validate_requirements succeeds with valid agent" {
    source "$SCRIPT_PATH"
    AGENT_COMMAND="echo -p {prompt}"
    ENABLE_COMMITS="false"
    
    function command() {
        return 0
    }
    export -f command
    
    run validate_requirements
    
    assert_success
}

@test "parse_agent_result handles valid JSON with success" {
    source "$SCRIPT_PATH"
    run parse_agent_result '{"result": "success", "total_cost_usd": 0.1}' 0
    assert_success
    assert_output "success"
}

@test "parse_agent_result handles JSON with is_error true" {
    source "$SCRIPT_PATH"
    run parse_agent_result '{"is_error": true, "result": "error message"}' 0
    assert_failure
    assert_output "agent_error"
}

@test "parse_agent_result handles non-JSON with exit code 0" {
    source "$SCRIPT_PATH"
    run parse_agent_result 'This is plain text output' 0
    assert_success
    assert_output "success"
}

@test "parse_agent_result handles non-JSON with non-zero exit code" {
    source "$SCRIPT_PATH"
    run parse_agent_result 'Error output' 1
    assert_failure
    assert_output "exit_code_error"
}

@test "parse_agent_result handles JSON without is_error field" {
    source "$SCRIPT_PATH"
    run parse_agent_result '{"output": "some result"}' 0
    assert_success
    assert_output "success"
}

@test "handle_iteration_success extracts text from JSON" {
    source "$SCRIPT_PATH"
    
    completion_signal_count=0
    total_cost=0
    COMPLETION_SIGNAL="TEST"
    COMPLETION_THRESHOLD=3
    ENABLE_COMMITS="false"
    
    result='{"result": "Task completed", "total_cost_usd": 0.5}'
    
    function git() { return 0; }
    export -f git
    
    run handle_iteration_success "(1/3)" "$result" "" "main"
    
    assert_success
    assert_output --partial "Task completed"
    assert_output --partial "Cost: \$0.500"
}

@test "handle_iteration_success handles plain text output" {
    source "$SCRIPT_PATH"
    
    completion_signal_count=0
    total_cost=0
    COMPLETION_SIGNAL="TEST"
    COMPLETION_THRESHOLD=3
    ENABLE_COMMITS="false"
    
    result='Plain text output from agent'
    
    function git() { return 0; }
    export -f git
    
    run handle_iteration_success "(1/3)" "$result" "" "main"
    
    assert_success
    assert_output --partial "Plain text output from agent"
    refute_output --partial "Cost:"
}

@test "handle_iteration_success handles JSON without cost" {
    source "$SCRIPT_PATH"
    
    completion_signal_count=0
    total_cost=0
    COMPLETION_SIGNAL="TEST"
    COMPLETION_THRESHOLD=3
    ENABLE_COMMITS="false"
    
    result='{"result": "Done"}'
    
    function git() { return 0; }
    export -f git
    
    run handle_iteration_success "(1/3)" "$result" "" "main"
    
    assert_success
    assert_output --partial "Done"
    refute_output --partial "Cost:"
}

@test "handle_iteration_success handles JSON with different schema" {
    source "$SCRIPT_PATH"
    
    completion_signal_count=0
    total_cost=0
    COMPLETION_SIGNAL="TEST"
    COMPLETION_THRESHOLD=3
    ENABLE_COMMITS="false"
    
    # JSON without .result field, should use entire output
    result='{"output": "some text", "status": "ok"}'
    
    function git() { return 0; }
    export -f git
    
    run handle_iteration_success "(1/3)" "$result" "" "main"
    
    assert_success
    assert_output --partial '{"output": "some text", "status": "ok"}'
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
