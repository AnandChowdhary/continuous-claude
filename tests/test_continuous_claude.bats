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
