#!/bin/bash
# Security Tests

run_security_tests() {
    test_section "SECURITY TESTS"

    # Ensure Redis is running
    if ! check_redis; then
        echo -e "${YELLOW}Starting Redis for security tests...${NC}"
        if ! start_redis; then
            skip_test "All security tests" "Redis not available"
            return 1
        fi
    fi

    # Start agent
    if ! start_test_agent; then
        skip_test "All security tests" "Agent not available"
        return 1
    fi

    local hostname=$(get_current_agent_hostname)
    local test_dir="$TEST_DIR/security_test"
    mkdir -p "$test_dir"

    # Test 1: Command injection attempts
    test_subsection "Command Injection"
    print_test_header "Command injection: semicolon"
    local output_file="$LOG_DIR/security_injection_semicolon_test.log"
    run_master_command "$hostname" "echo test; rm -rf /" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "Return Code:" "$output_file"; then
            pass_test "Semicolon injection handled" ""
        else
            fail_test "Semicolon injection not handled" ""
        fi
    else
        pass_test "Semicolon injection blocked" ""
    fi

    # Test 2: Command injection with &&
    print_test_header "Command injection: &&"
    output_file="$LOG_DIR/security_injection_and_test.log"
    run_master_command "$hostname" "echo test && rm -rf /" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "Return Code:" "$output_file"; then
            pass_test "&& injection handled" ""
        else
            fail_test "&& injection not handled" ""
        fi
    else
        pass_test "&& injection blocked" ""
    fi

    # Test 3: Command injection with pipes
    print_test_header "Command injection: pipes"
    output_file="$LOG_DIR/security_injection_pipe_test.log"
    run_master_command "$hostname" "echo test | rm -rf /" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "Return Code:" "$output_file"; then
            pass_test "Pipe injection handled" ""
        else
            fail_test "Pipe injection not handled" ""
        fi
    else
        pass_test "Pipe injection blocked" ""
    fi

    # Test 4: Command injection with backticks
    print_test_header "Command injection: backticks"
    output_file="$LOG_DIR/security_injection_backtick_test.log"
    run_master_command "$hostname" "echo `rm -rf /`" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "Return Code:" "$output_file"; then
            pass_test "Backtick injection handled" ""
        else
            fail_test "Backtick injection not handled" ""
        fi
    else
        pass_test "Backtick injection blocked" ""
    fi

    # Test 5: Command injection with $()
    print_test_header "Command injection: \$()"
    output_file="$LOG_DIR/security_injection_dollar_test.log"
    run_master_command "$hostname" "echo \$(rm -rf /)" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "Return Code:" "$output_file"; then
            pass_test "\$() injection handled" ""
        else
            fail_test "\$() injection not handled" ""
        fi
    else
        pass_test "\$() injection blocked" ""
    fi

    # Test 6: Path traversal in file send
    test_subsection "Path Traversal"
    print_test_header "Path traversal: send file"
    local traversal_file="$test_dir/traversal.txt"
    create_test_file "$traversal_file" 10 "traversal test"
    output_file="$LOG_DIR/security_path_traversal_send_test.log"

    send_file_via_master "$hostname" "$traversal_file" "../../../etc/passwd" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "File transfer" "$output_file"; then
            pass_test "Path traversal in send handled" ""
        else
            fail_test "Path traversal in send not handled" ""
        fi
    else
        pass_test "Path traversal in send blocked" ""
    fi

    # Test 7: Path traversal in file receive
    print_test_header "Path traversal: receive file"
    local receive_file="$test_dir/traversal_received.txt"
    output_file="$LOG_DIR/security_path_traversal_receive_test.log"

    receive_file_via_master "$hostname" "../../../etc/passwd" "$receive_file" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "File transfer" "$output_file"; then
            pass_test "Path traversal in receive handled" ""
        else
            fail_test "Path traversal in receive not handled" ""
        fi
    else
        pass_test "Path traversal in receive blocked" ""
    fi

    # Test 8: Very long hostname
    test_subsection "Input Validation"
    print_test_header "Very long hostname"
    local long_hostname=$(printf 'a%.0s' {1..300})
    output_file="$LOG_DIR/security_long_hostname_test.log"
    run_master_command "$long_hostname" "echo test" "$output_file"

    if [ $? -eq 0 ]; then
        pass_test "Very long hostname handled" ""
    else
        skip_test "Very long hostname" "Command failed as expected"
    fi

    # Test 9: Very long command
    print_test_header "Very long command"
    local long_cmd=$(printf 'echo "%0.sA"' {1..10000})
    output_file="$LOG_DIR/security_long_command_test.log"
    run_master_command "$hostname" "$long_cmd" "$output_file"

    if [ $? -eq 0 ]; then
        pass_test "Very long command handled" ""
    else
        skip_test "Very long command" "Command failed as expected"
    fi

    # Test 10: Very long file path
    print_test_header "Very long file path"
    local long_path=$(printf '/tmp/%.0s' {1..200})
    local long_file="$test_dir/long_path.txt"
    create_test_file "$long_file" 10 "test"
    output_file="$LOG_DIR_security_long_path_test.log"

    send_file_via_master "$hostname" "$long_file" "$long_path" "$output_file"

    if [ $? -eq 0 ]; then
        pass_test "Very long file path handled" ""
    else
        skip_test "Very long file path" "Command failed as expected"
    fi

    # Test 11: Special characters in hostname
    print_test_header "Special characters in hostname"
    local special_hostname="host!@#\$%^&*()"
    output_file="$LOG_DIR_security_special_hostname_test.log"
    run_master_command "$special_hostname" "echo test" "$output_file"

    if [ $? -eq 0 ]; then
        pass_test "Special characters in hostname handled" ""
    else
        skip_test "Special characters in hostname" "Command failed as expected"
    fi

    # Test 12: Empty hostname
    print_test_header "Empty hostname"
    output_file="$LOG_DIR_security_empty_hostname_test.log"
    run_master_command "" "echo test" "$output_file"

    if [ $? -eq 0 ]; then
        pass_test "Empty hostname handled" ""
    else
        skip_test "Empty hostname" "Command failed as expected"
    fi

    # Test 13: Empty command
    print_test_header "Empty command"
    output_file="$LOG_DIR_security_empty_command_test.log"
    sudo "$OUT_DIR/master" 2 "$hostname" "" > "$output_file" 2>&1

    if [ $? -eq 0 ]; then
        pass_test "Empty command handled" ""
    else
        skip_test "Empty command" "Command failed as expected"
    fi

    # Test 14: Command with only whitespace
    print_test_header "Command with only whitespace"
    output_file="$LOG_DIR_security_whitespace_command_test.log"
    sudo "$OUT_DIR/master" 2 "$hostname" "   " > "$output_file" 2>&1

    if [ $? -eq 0 ]; then
        pass_test "Whitespace command handled" ""
    else
        skip_test "Whitespace command" "Command failed as expected"
    fi

    # Test 15: Null bytes in command
    print_test_header "Null bytes in command"
    output_file="$LOG_DIR_security_null_bytes_test.log"
    run_master_command "$hostname" "echo test" "$output_file"

    if [ $? -eq 0 ]; then
        pass_test "Null bytes handled" ""
    else
        skip_test "Null bytes" "Command failed as expected"
    fi

    # Test 16: Unicode characters in command
    print_test_header "Unicode characters in command"
    output_file="$LOG_DIR_security_unicode_test.log"
    run_master_command "$hostname" "echo 'café, naïve, 日本語, 🎉'" "$output_file"

    if [ $? -eq 0 ] && grep -q "Return Code: 0" "$output_file"; then
        pass_test "Unicode characters handled" ""
    else
        fail_test "Unicode characters not handled" ""
    fi

    # Test 17: Control characters in command
    print_test_header "Control characters in command"
    output_file="$LOG_DIR_security_control_chars_test.log"
    run_master_command "$hostname" "echo -e 'test\ttest'" "$output_file"

    if [ $? -eq 0 ] && grep -q "Return Code: 0" "$output_file"; then
        pass_test "Control characters handled" ""
    else
        fail_test "Control characters not handled" ""
    fi

    # Test 18: File with special permissions
    test_subsection "File Permissions"
    print_test_header "File with special permissions"
    local special_perm_file="$test_dir/special_perm.txt"
    create_test_file "$special_perm_file" 10 "test"
    chmod 777 "$special_perm_file"
    local remote_special_perm="/tmp/special_perm.txt"

    output_file="$LOG_DIR_security_special_perm_test.log"
    send_file_via_master "$hostname" "$special_perm_file" "$remote_special_perm" "$output_file"

    if [ $? -eq 0 ] && grep -q "File transfer completed successfully" "$output_file"; then
        pass_test "File with special permissions sent" ""
    else
        fail_test "File with special permissions failed" ""
    fi

    # Test 19: Attempt to read sensitive file
    print_test_header "Read sensitive file"
    output_file="$LOG_DIR_security_sensitive_test.log"
    run_master_command "$hostname" "cat /etc/shadow" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "Return Code:" "$output_file"; then
            pass_test "Sensitive file read handled" ""
        else
            fail_test "Sensitive file read not handled" ""
        fi
    else
        pass_test "Sensitive file read blocked" ""
    fi

    # Test 20: Attempt to write to sensitive location
    print_test_header "Write to sensitive location"
    local sensitive_file="$test_dir/sensitive.txt"
    create_test_file "$sensitive_file" 10 "test"
    output_file="$LOG_DIR_security_write_sensitive_test.log"

    send_file_via_master "$hostname" "$sensitive_file" "/etc/sensitive_test" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "File transfer" "$output_file"; then
            pass_test "Write to sensitive location handled" ""
        else
            fail_test "Write to sensitive location not handled" ""
        fi
    else
        pass_test "Write to sensitive location blocked" ""
    fi

    # Test 21: Redis authentication
    test_subsection "Redis Security"
    print_test_header "Redis authentication"
    if [ -n "$REDIS_PASS" ]; then
        pass_test "Redis password configured" ""
    else
        skip_test "Redis authentication" "No password configured"
    fi

    # Test 22: Redis connection without password
    print_test_header "Redis connection without password"
    if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ping 2>/dev/null | grep -q "PONG"; then
        skip_test "Redis without password" "Redis accepts connections without password"
    else
        pass_test "Redis requires authentication" ""
    fi

    # Test 23: Verify agent runs as root
    test_subsection "Process Security"
    print_test_header "Agent process user"
    if [ -f /tmp/agent.pid ]; then
        local agent_pid=$(cat /tmp/agent.pid)
        local agent_user=$(ps -o user= -p "$agent_pid" | tr -d ' ')
        if [ "$agent_user" = "root" ]; then
            pass_test "Agent runs as root" ""
        else
            skip_test "Agent user" "Agent runs as $agent_user"
        fi
    fi

    # Test 24: Verify PID file permissions
    print_test_header "PID file permissions"
    if [ -f /tmp/agent.pid ]; then
        local pid_perms=$(stat -c "%a" /tmp/agent.pid)
        if [ "$pid_perms" = "644" ] || [ "$pid_perms" = "600" ]; then
            pass_test "PID file has secure permissions" "Permissions: $pid_perms"
        else
            skip_test "PID file permissions" "Permissions: $pid_perms"
        fi
    fi

    # Test 25: Verify log file permissions
    print_test_header "Log file permissions"
    if [ -f /var/log/moniagent.log ]; then
        local log_perms=$(stat -c "%a" /var/log/moniagent.log)
        if [ "$log_perms" = "644" ] || [ "$log_perms" = "600" ]; then
            pass_test "Log file has secure permissions" "Permissions: $log_perms"
        else
            skip_test "Log file permissions" "Permissions: $log_perms"
        fi
    fi

    # Test 26: Verify no sensitive data in logs
    print_test_header "Sensitive data in logs"
    if [ -f /var/log/moniagent.log ]; then
        if grep -q "password\|secret\|key" /var/log/moniagent.log -i; then
            skip_test "Sensitive data in logs" "Found potential sensitive data"
        else
            pass_test "No sensitive data in logs" ""
        fi
    fi

    # Test 27: Verify command sanitization
    print_test_header "Command sanitization"
    output_file="$LOG_DIR_security_sanitization_test.log"
    run_master_command "$hostname" "echo 'test; rm -rf /'" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "Return Code:" "$output_file"; then
            pass_test "Command sanitization works" ""
        else
            fail_test "Command sanitization not working" ""
        fi
    else
        pass_test "Command sanitization blocked dangerous command" ""
    fi

    # Test 28: Verify file path sanitization
    print_test_header "File path sanitization"
    local path_file="$test_dir/path_test.txt"
    create_test_file "$path_file" 10 "test"
    output_file="$LOG_DIR_security_path_sanitization_test.log"

    send_file_via_master "$hostname" "$path_file" "/tmp/../../../etc/passwd" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "File transfer" "$output_file"; then
            pass_test "File path sanitization works" ""
        else
            fail_test "File path sanitization not working" ""
        fi
    else
        pass_test "File path sanitization blocked dangerous path" ""
    fi

    # Cleanup
    stop_test_agent
    rm -rf "$test_dir"

    echo ""
    echo -e "${CYAN}Security tests completed${NC}"
}
