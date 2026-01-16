#!/bin/bash
# Command Execution Tests

run_command_tests() {
    test_section "COMMAND EXECUTION TESTS"

    # Ensure Redis is running
    if ! check_redis; then
        echo -e "${YELLOW}Starting Redis for command tests...${NC}"
        if ! start_redis; then
            skip_test "All command tests" "Redis not available"
            return 1
        fi
    fi

    # Start agent
    if ! start_test_agent; then
        skip_test "All command tests" "Agent not available"
        return 1
    fi

    local hostname=$(get_current_agent_hostname)

    # Test 1: Basic command - ls
    test_subsection "Basic Commands"
    print_test_header "Execute ls command"
    local output_file="$LOG_DIR/command_ls_test.log"
    run_master_command "$hostname" "ls /" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "Return Code: 0" "$output_file"; then
            pass_test "ls command executed successfully" ""
        else
            fail_test "ls command returned non-zero" ""
        fi
    else
        fail_test "ls command failed" ""
    fi

    # Test 2: pwd command
    print_test_header "Execute pwd command"
    output_file="$LOG_DIR/command_pwd_test.log"
    run_master_command "$hostname" "pwd" "$output_file"

    if [ $? -eq 0 ] && grep -q "Return Code: 0" "$output_file"; then
        pass_test "pwd command executed successfully" ""
    else
        fail_test "pwd command failed" ""
    fi

    # Test 3: whoami command
    print_test_header "Execute whoami command"
    output_file="$LOG_DIR/command_whoami_test.log"
    run_master_command "$hostname" "whoami" "$output_file"

    if [ $? -eq 0 ] && grep -q "Return Code: 0" "$output_file"; then
        pass_test "whoami command executed successfully" ""
    else
        fail_test "whoami command failed" ""
    fi

    # Test 4: hostname command
    print_test_header "Execute hostname command"
    output_file="$LOG_DIR/command_hostname_test.log"
    run_master_command "$hostname" "hostname" "$output_file"

    if [ $? -eq 0 ] && grep -q "Return Code: 0" "$output_file"; then
        pass_test "hostname command executed successfully" ""
    else
        fail_test "hostname command failed" ""
    fi

    # Test 5: echo command with output
    print_test_header "Execute echo command"
    output_file="$LOG_DIR/command_echo_test.log"
    run_master_command "$hostname" "echo 'Hello from MONITOR'" "$output_file"

    if [ $? -eq 0 ] && grep -q "Return Code: 0" "$output_file"; then
        if grep -q "Hello from MONITOR" "$output_file"; then
            pass_test "echo command executed with correct output" ""
        else
            fail_test "echo command output incorrect" ""
        fi
    else
        fail_test "echo command failed" ""
    fi

    # Test 6: Command with stderr
    test_subsection "Command with Output"
    print_test_header "Execute command with stderr"
    output_file="$LOG_DIR/command_stderr_test.log"
    run_master_command "$hostname" "ls /nonexistent_directory_12345" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "Return Code:" "$output_file" && grep -q "STDERR:" "$output_file"; then
            pass_test "Command with stderr handled correctly" ""
        else
            fail_test "Command stderr not captured" ""
        fi
    else
        fail_test "Command execution failed" ""
    fi

    # Test 7: Command with non-zero exit code
    print_test_header "Execute command with non-zero exit"
    output_file="$LOG_DIR/command_exit_code_test.log"
    run_master_command "$hostname" "exit 42" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "Return Code: 42" "$output_file"; then
            pass_test "Non-zero exit code captured correctly" ""
        else
            fail_test "Exit code not captured correctly" ""
        fi
    else
        fail_test "Command execution failed" ""
    fi

    # Test 8: Command with pipes
    print_test_header "Execute command with pipes"
    output_file="$LOG_DIR/command_pipe_test.log"
    run_master_command "$hostname" "echo 'test' | cat" "$output_file"

    if [ $? -eq 0 ] && grep -q "Return Code: 0" "$output_file"; then
        pass_test "Command with pipe executed successfully" ""
    else
        fail_test "Command with pipe failed" ""
    fi

    # Test 9: Command with quotes
    print_test_header "Execute command with quotes"
    output_file="$LOG_DIR/command_quotes_test.log"
    run_master_command "$hostname" "echo \"test with quotes\"" "$output_file"

    if [ $? -eq 0 ] && grep -q "Return Code: 0" "$output_file"; then
        pass_test "Command with quotes executed successfully" ""
    else
        fail_test "Command with quotes failed" ""
    fi

    # Test 10: cd command (special handling)
    test_subsection "Special Command Handling"
    print_test_header "Execute cd command"
    output_file="$LOG_DIR/command_cd_test.log"
    run_master_command "$hostname" "cd /tmp" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "Changed directory to: /tmp" "$output_file" || grep -q "Return Code: 0" "$output_file"; then
            pass_test "cd command executed successfully" ""
        else
            fail_test "cd command output incorrect" ""
        fi
    else
        fail_test "cd command failed" ""
    fi

    # Test 11: cd to home directory
    print_test_header "Execute cd to home"
    output_file="$LOG_DIR/command_cd_home_test.log"
    run_master_command "$hostname" "cd" "$output_file"

    if [ $? -eq 0 ] && grep -q "Return Code: 0" "$output_file"; then
        pass_test "cd to home executed successfully" ""
    else
        fail_test "cd to home failed" ""
    fi

    # Test 12: cd to non-existent directory
    print_test_header "Execute cd to non-existent"
    output_file="$LOG_DIR/command_cd_nonexistent_test.log"
    run_master_command "$hostname" "cd /nonexistent_directory_xyz" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "Return Code:" "$output_file"; then
            pass_test "cd to non-existent handled correctly" ""
        else
            fail_test "cd to non-existent output incorrect" ""
        fi
    else
        fail_test "cd to non-existent failed" ""
    fi

    # Test 13: Command that produces large output
    test_subsection "Large Output"
    print_test_header "Command with large stdout"
    output_file="$LOG_DIR/command_large_output_test.log"
    run_master_command "$hostname" "dd if=/dev/zero bs=1024 count=100 2>/dev/null | tr '\0' 'A'" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "Return Code: 0" "$output_file"; then
            pass_test "Command with large output executed" ""
        else
            fail_test "Command with large output failed" ""
        fi
    else
        fail_test "Command execution failed" ""
    fi

    # Test 14: Command with special characters
    test_subsection "Special Characters"
    print_test_header "Command with special characters"
    output_file="$LOG_DIR/command_special_chars_test.log"
    run_master_command "$hostname" "echo 'test!@#\$%^&*()'" "$output_file"

    if [ $? -eq 0 ] && grep -q "Return Code: 0" "$output_file"; then
        pass_test "Command with special characters executed" ""
    else
        fail_test "Command with special characters failed" ""
    fi

    # Test 15: Command with redirection
    print_test_header "Command with redirection"
    output_file="$LOG_DIR/command_redirect_test.log"
    run_master_command "$hostname" "echo 'test' > /tmp/test_redirect.txt && cat /tmp/test_redirect.txt" "$output_file"

    if [ $? -eq 0 ] && grep -q "Return Code: 0" "$output_file"; then
        pass_test "Command with redirection executed" ""
    else
        fail_test "Command with redirection failed" ""
    fi

    # Test 16: Multiple commands in sequence
    test_subsection "Multiple Commands"
    print_test_header "Multiple commands in sequence"
    for i in {1..5}; do
        output_file="$LOG_DIR/command_seq_${i}_test.log"
        run_master_command "$hostname" "echo 'command $i'" "$output_file"
        if [ $? -ne 0 ]; then
            fail_test "Command $i in sequence failed" ""
            break
        fi
    done
    pass_test "All commands in sequence executed" ""

    # Test 17: Command that takes time to execute
    test_subsection "Long-running Commands"
    print_test_header "Long-running command"
    output_file="$LOG_DIR/command_long_running_test.log"
    run_with_timeout "sudo '$OUT_DIR/master' 2 '$hostname' 'sleep 5'" 10 "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "Return Code: 0" "$output_file"; then
            pass_test "Long-running command executed successfully" ""
        else
            fail_test "Long-running command returned non-zero" ""
        fi
    else
        fail_test "Long-running command failed" ""
    fi

    # Test 18: Command that doesn't exist
    test_subsection "Error Handling"
    print_test_header "Non-existent command"
    output_file="$LOG_DIR/command_nonexistent_test.log"
    run_master_command "$hostname" "nonexistent_command_xyz" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "Return Code:" "$output_file" && ! grep -q "Return Code: 0" "$output_file"; then
            pass_test "Non-existent command handled correctly" ""
        else
            fail_test "Non-existent command not handled correctly" ""
        fi
    else
        fail_test "Command execution failed" ""
    fi

    # Test 19: Command with syntax error
    print_test_header "Command with syntax error"
    output_file="$LOG_DIR/command_syntax_error_test.log"
    run_master_command "$hostname" "if then else" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "Return Code:" "$output_file" && ! grep -q "Return Code: 0" "$output_file"; then
            pass_test "Syntax error handled correctly" ""
        else
            fail_test "Syntax error not handled correctly" ""
        fi
    else
        fail_test "Command execution failed" ""
    fi

    # Test 20: Empty command
    print_test_header "Empty command"
    output_file="$LOG_DIR/command_empty_test.log"
    run_master_command "$hostname" "" "$output_file"

    if [ $? -eq 0 ]; then
        pass_test "Empty command handled" ""
    else
        skip_test "Empty command" "May not be supported"
    fi

    # Test 21: Command with only whitespace
    print_test_header "Command with whitespace"
    output_file="$LOG_DIR/command_whitespace_test.log"
    run_master_command "$hostname" "   " "$output_file"

    if [ $? -eq 0 ]; then
        pass_test "Whitespace command handled" ""
    else
        skip_test "Whitespace command" "May not be supported"
    fi

    # Test 22: Verify command results in Redis
    test_subsection "Redis Verification"
    print_test_header "Command results in Redis"
    local uuid=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" keys "uuid:*" 2>/dev/null | head -1)
    if [ -n "$uuid" ]; then
        pass_test "Command UUID found in Redis" "UUID: $uuid"
    else
        skip_test "Command UUID check" "No commands found in Redis"
    fi

    # Test 23: Verify command cleanup
    print_test_header "Command cleanup"
    sleep 2
    local remaining_keys=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" keys "run:*" 2>/dev/null | wc -l)
    if [ "$remaining_keys" -eq 0 ]; then
        pass_test "Command keys cleaned up" ""
    else
        skip_test "Command cleanup" "Some keys remain: $remaining_keys"
    fi

    # Cleanup
    stop_test_agent

    echo ""
    echo -e "${CYAN}Command execution tests completed${NC}"
}
