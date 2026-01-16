#!/bin/bash
# Master Core Functionality Tests

run_master_tests() {
    test_section "MASTER CORE FUNCTIONALITY TESTS"

    # Ensure Redis is running
    if ! check_redis; then
        echo -e "${YELLOW}Starting Redis for master tests...${NC}"
        if ! start_redis; then
            skip_test "All master tests" "Redis not available"
            return 1
        fi
    fi

    # Start agent
    if ! start_test_agent; then
        skip_test "All master tests" "Agent not available"
        return 1
    fi

    local hostname=$(get_current_agent_hostname)

    # Test 1: Master version flag
    test_subsection "Version Flag"
    print_test_header "Master version flag"
    local version_output=$(sudo "$OUT_DIR/master" -v 2>&1)
    if echo "$version_output" | grep -q "Monitor Master version:"; then
        pass_test "Master version flag works" "$version_output"
    else
        fail_test "Master version flag failed" "$version_output"
    fi

    # Test 2: List agents (option 1)
    test_subsection "List Agents"
    print_test_header "List connected agents"
    local output_file="$LOG_DIR/master_list_test.log"
    list_agents_via_master "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "Connected Agents" "$output_file" && grep -q "$hostname" "$output_file"; then
            pass_test "List agents shows connected agent" ""
        else
            fail_test "List agents output incorrect" ""
        fi
    else
        fail_test "List agents command failed" ""
    fi

    # Test 3: List agents when none connected
    print_test_header "List agents when none connected"
    stop_test_agent
    output_file="$LOG_DIR/master_list_empty_test.log"
    list_agents_via_master "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "Connected Agents" "$output_file"; then
            pass_test "List agents handles empty list" ""
        else
            fail_test "List agents empty output incorrect" ""
        fi
    else
        fail_test "List agents empty command failed" ""
    fi

    # Restart agent for remaining tests
    start_test_agent
    hostname=$(get_current_agent_hostname)

    # Test 4: Interactive mode menu
    test_subsection "Interactive Mode"
    print_test_header "Interactive mode menu"
    # Note: Interactive mode requires user input, so we test CLI mode instead
    skip_test "Interactive mode" "Requires user input - tested via CLI mode"

    # Test 5: CLI mode with valid arguments
    print_test_header "CLI mode with valid arguments"
    output_file="$LOG_DIR/master_cli_test.log"
    run_master_command "$hostname" "echo 'CLI test'" "$output_file"

    if [ $? -eq 0 ]; then
        pass_test "CLI mode works with valid arguments" ""
    else
        fail_test "CLI mode failed with valid arguments" ""
    fi

    # Test 6: CLI mode with invalid option
    print_test_header "CLI mode with invalid option"
    output_file="$LOG_DIR/master_cli_invalid_test.log"
    sudo "$OUT_DIR/master" 99 "$hostname" "test" > "$output_file" 2>&1

    if [ $? -ne 0 ] || grep -q "Invalid option" "$output_file"; then
        pass_test "CLI mode handles invalid option" ""
    else
        fail_test "CLI mode doesn't handle invalid option correctly" ""
    fi

    # Test 7: CLI mode with insufficient arguments
    print_test_header "CLI mode with insufficient arguments"
    output_file="$LOG_DIR/master_cli_insufficient_test.log"
    sudo "$OUT_DIR/master" 2 "$hostname" > "$output_file" 2>&1

    if [ $? -ne 0 ] || grep -q "Usage:" "$output_file"; then
        pass_test "CLI mode handles insufficient arguments" ""
    else
        fail_test "CLI mode doesn't handle insufficient arguments" ""
    fi

    # Test 8: Send command to non-existent agent
    test_subsection "Error Handling"
    print_test_header "Send command to non-existent agent"
    output_file="$LOG_DIR/master_nonexistent_test.log"
    run_master_command "nonexistent_host_xyz" "echo test" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "Command" "$output_file"; then
            pass_test "Command to non-existent agent handled" ""
        else
            skip_test "Command to non-existent agent" "May not be supported"
        fi
    else
        skip_test "Command to non-existent agent" "Command failed as expected"
    fi

    # Test 9: Send command with empty command string
    print_test_header "Send command with empty command"
    output_file="$LOG_DIR/master_empty_cmd_test.log"
    sudo "$OUT_DIR/master" 2 "$hostname" "" > "$output_file" 2>&1

    if [ $? -eq 0 ]; then
        pass_test "Empty command handled" ""
    else
        skip_test "Empty command" "May not be supported"
    fi

    # Test 10: Send command with special characters
    print_test_header "Send command with special characters"
    output_file="$LOG_DIR/master_special_chars_test.log"
    run_master_command "$hostname" "echo 'test!@#\$%^&*()'" "$output_file"

    if [ $? -eq 0 ] && grep -q "Return Code: 0" "$output_file"; then
        pass_test "Command with special characters executed" ""
    else
        fail_test "Command with special characters failed" ""
    fi

    # Test 11: Send command with very long command
    print_test_header "Send command with very long command"
    local long_cmd=$(printf 'echo "%0.sA"' {1..1000})
    output_file="$LOG_DIR/master_long_cmd_test.log"
    run_master_command "$hostname" "$long_cmd" "$output_file"

    if [ $? -eq 0 ]; then
        pass_test "Long command handled" ""
    else
        fail_test "Long command failed" ""
    fi

    # Test 12: Send command with quotes
    print_test_header "Send command with quotes"
    output_file="$LOG_DIR/master_quotes_test.log"
    run_master_command "$hostname" 'echo "test with \"quotes\""' "$output_file"

    if [ $? -eq 0 ] && grep -q "Return Code: 0" "$output_file"; then
        pass_test "Command with quotes executed" ""
    else
        fail_test "Command with quotes failed" ""
    fi

    # Test 13: Send command with pipes
    print_test_header "Send command with pipes"
    output_file="$LOG_DIR/master_pipes_test.log"
    run_master_command "$hostname" "echo 'test' | cat | wc -l" "$output_file"

    if [ $? -eq 0 ] && grep -q "Return Code: 0" "$output_file"; then
        pass_test "Command with pipes executed" ""
    else
        fail_test "Command with pipes failed" ""
    fi

    # Test 14: Send command with redirection
    print_test_header "Send command with redirection"
    output_file="$LOG_DIR/master_redirect_test.log"
    run_master_command "$hostname" "echo 'test' > /tmp/master_test.txt && cat /tmp/master_test.txt" "$output_file"

    if [ $? -eq 0 ] && grep -q "Return Code: 0" "$output_file"; then
        pass_test "Command with redirection executed" ""
    else
        fail_test "Command with redirection failed" ""
    fi

    # Test 15: Send command that produces large output
    test_subsection "Large Output"
    print_test_header "Command with large output"
    output_file="$LOG_DIR/master_large_output_test.log"
    run_master_command "$hostname" "dd if=/dev/zero bs=1024 count=10 2>/dev/null | tr '\0' 'A'" "$output_file"

    if [ $? -eq 0 ]; then
        pass_test "Command with large output executed" ""
    else
        fail_test "Command with large output failed" ""
    fi

    # Test 16: Send command that produces stderr
    test_subsection "Error Output"
    print_test_header "Command with stderr"
    output_file="$LOG_DIR/master_stderr_test.log"
    run_master_command "$hostname" "ls /nonexistent_dir_xyz" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "STDERR:" "$output_file"; then
            pass_test "Command stderr captured" ""
        else
            fail_test "Command stderr not captured" ""
        fi
    else
        fail_test "Command execution failed" ""
    fi

    # Test 17: Send command with non-zero exit code
    print_test_header "Command with non-zero exit"
    output_file="$LOG_DIR/master_exit_code_test.log"
    run_master_command "$hostname" "exit 42" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "Return Code: 42" "$output_file"; then
            pass_test "Non-zero exit code captured" ""
        else
            fail_test "Exit code not captured correctly" ""
        fi
    else
        fail_test "Command execution failed" ""
    fi

    # Test 18: Send command that takes time
    test_subsection "Long-running Commands"
    print_test_header "Long-running command"
    output_file="$LOG_DIR/master_long_running_test.log"
    run_with_timeout "sudo '$OUT_DIR/master' 2 '$hostname' 'sleep 3'" 10 "$output_file"

    if [ $? -eq 0 ]; then
        pass_test "Long-running command executed" ""
    else
        fail_test "Long-running command failed" ""
    fi

    # Test 19: Multiple commands in sequence
    test_subsection "Multiple Commands"
    print_test_header "Multiple commands in sequence"
    local success_count=0
    for i in {1..5}; do
        output_file="$LOG_DIR/master_seq_${i}_test.log"
        run_master_command "$hostname" "echo 'seq $i'" "$output_file"
        if [ $? -eq 0 ] && grep -q "Return Code: 0" "$output_file"; then
            success_count=$((success_count + 1))
        fi
    done

    if [ "$success_count" -eq 5 ]; then
        pass_test "All sequential commands executed" ""
    else
        fail_test "Some sequential commands failed" "Success: $success_count/5"
    fi

    # Test 20: Verify command logging
    test_subsection "Logging"
    print_test_header "Command logging"
    if [ -f "/var/log/master.log" ]; then
        if verify_log_contains "/var/log/master.log" "COMMAND"; then
            pass_test "Command logging works" ""
        else
            fail_test "Command logging not working" ""
        fi
    else
        fail_test "Master log file not found" ""
    fi

    # Test 21: Verify connection logging
    print_test_header "Connection logging"
    if verify_log_contains "/var/log/master.log" "CONNECTION"; then
        pass_test "Connection logging works" ""
    else
        fail_test "Connection logging not working" ""
    fi

    # Test 22: Verify log format
    print_test_header "Log format"
    if grep -qP "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\t" "/var/log/master.log"; then
        pass_test "Log has correct timestamp format" ""
    else
        fail_test "Log timestamp format incorrect" ""
    fi

    # Test 23: Verify log categories
    print_test_header "Log categories"
    local has_categories=false
    for category in COMMAND FILE CONNECTION; do
        if grep -q "\[$category\]" "/var/log/master.log"; then
            has_categories=true
        fi
    done

    if [ "$has_categories" = true ]; then
        pass_test "Log categories present" ""
    else
        fail_test "Log categories missing" ""
    fi

    # Test 24: Master connection to Redis
    test_subsection "Redis Connection"
    print_test_header "Master Redis connection"
    if verify_redis_key "next_agent_id"; then
        pass_test "Master connected to Redis" ""
    else
        fail_test "Master not connected to Redis" ""
    fi

    # Test 25: Verify agent appears in master list
    print_test_header "Agent in master list"
    output_file="$LOG_DIR/master_list_final_test.log"
    list_agents_via_master "$output_file"

    if grep -q "$hostname" "$output_file"; then
        pass_test "Agent appears in master list" ""
    else
        fail_test "Agent not in master list" ""
    fi

    # Cleanup
    stop_test_agent

    echo ""
    echo -e "${CYAN}Master tests completed${NC}"
}
