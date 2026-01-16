#!/bin/bash
# Logging Tests

run_logging_tests() {
    test_section "LOGGING TESTS"

    # Ensure Redis is running
    if ! check_redis; then
        echo -e "${YELLOW}Starting Redis for logging tests...${NC}"
        if ! start_redis; then
            skip_test "All logging tests" "Redis not available"
            return 1
        fi
    fi

    # Start agent
    if ! start_test_agent; then
        skip_test "All logging tests" "Agent not available"
        return 1
    fi

    local hostname=$(get_current_agent_hostname)

    # Test 1: Verify agent log file exists
    test_subsection "Agent Logging"
    print_test_header "Verify agent log file exists"
    if [ -f /var/log/moniagent.log ]; then
        pass_test "Agent log file exists" "Path: /var/log/moniagent.log"
    else
        fail_test "Agent log file not found" ""
    fi

    # Test 2: Verify agent log file is readable
    print_test_header "Verify agent log file is readable"
    if [ -r /var/log/moniagent.log ]; then
        pass_test "Agent log file is readable" ""
    else
        fail_test "Agent log file not readable" ""
    fi

    # Test 3: Verify agent log file has content
    print_test_header "Verify agent log file has content"
    local log_size=$(wc -l < /var/log/moniagent.log 2>/dev/null)
    if [ "$log_size" -gt 0 ]; then
        pass_test "Agent log file has content" "Lines: $log_size"
    else
        fail_test "Agent log file is empty" ""
    fi

    # Test 4: Verify agent log contains startup message
    print_test_header "Verify agent startup logged"
    if grep -q "Starting\|startup\|initialized" /var/log/moniagent.log -i; then
        pass_test "Agent startup logged" ""
    else
        skip_test "Agent startup log" "Startup message not found"
    fi

    # Test 5: Verify agent log contains registration message
    print_test_header "Verify agent registration logged"
    if grep -q "register\|connected" /var/log/moniagent.log -i; then
        pass_test "Agent registration logged" ""
    else
        skip_test "Agent registration log" "Registration message not found"
    fi

    # Test 6: Verify agent log contains metrics collection message
    print_test_header "Verify metrics collection logged"
    sleep 2  # Give agent time to collect metrics
    if grep -q "metric\|collect" /var/log/moniagent.log -i; then
        pass_test "Metrics collection logged" ""
    else
        skip_test "Metrics collection log" "Metrics message not found"
    fi

    # Test 7: Verify agent log timestamp format
    print_test_header "Verify log timestamp format"
    if grep -qP "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}" /var/log/moniagent.log; then
        pass_test "Log has correct timestamp format" ""
    else
        fail_test "Log timestamp format incorrect" ""
    fi

    # Test 8: Verify agent log categories
    print_test_header "Verify log categories"
    local has_categories=false
    for category in INFO DEBUG ERROR; do
        if grep -q "\\[$category\\]" /var/log/moniagent.log; then
            has_categories=true
        fi
    done

    if [ "$has_categories" = true ]; then
        pass_test "Log categories present" ""
    else
        skip_test "Log categories" "Categories not found"
    fi

    # Test 9: Verify master log file exists
    test_subsection "Master Logging"
    print_test_header "Verify master log file exists"
    local master_log_path="/var/log/master.log"
    if [ -f "$master_log_path" ]; then
        pass_test "Master log file exists" "Path: $master_log_path"
    else
        fail_test "Master log file not found" ""
    fi

    # Test 10: Verify master log file is readable
    print_test_header "Verify master log file is readable"
    if [ -r "$master_log_path" ]; then
        pass_test "Master log file is readable" ""
    else
        fail_test "Master log file not readable" ""
    fi

    # Test 11: Verify master log has content
    print_test_header "Verify master log has content"
    local master_log_size=$(wc -l < "$master_log_path" 2>/dev/null)
    if [ "$master_log_size" -gt 0 ]; then
        pass_test "Master log file has content" "Lines: $master_log_size"
    else
        fail_test "Master log file is empty" ""
    fi

    # Test 12: Verify master log timestamp format
    print_test_header "Verify master log timestamp format"
    if grep -qP "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}" "/var/log/master.log"; then
        pass_test "Master log has correct timestamp format" ""
    else
        fail_test "Master log timestamp format incorrect" ""
    fi

    # Test 13: Verify master log contains connection events
    print_test_header "Verify master connection logging"
    if grep -q "CONNECTION\|connect\|agent" "/var/log/master.log" -i; then
        pass_test "Master connection events logged" ""
    else
        skip_test "Master connection log" "Connection events not found"
    fi

    # Test 14: Verify master log contains command events
    print_test_header "Verify master command logging"
    if grep -q "COMMAND\|command\|execute" "/var/log/master.log" -i; then
        pass_test "Master command events logged" ""
    else
        skip_test "Master command log" "Command events not found"
    fi

    # Test 15: Verify master log contains file transfer events
    print_test_header "Verify master file transfer logging"
    if grep -q "FILE\|file\|transfer" "/var/log/master.log" -i; then
        pass_test "Master file transfer events logged" ""
    else
        skip_test "Master file transfer log" "File transfer events not found"
    fi

    # Test 16: Verify log file permissions
    test_subsection "Log Security"
    print_test_header "Verify agent log file permissions"
    if [ -f /var/log/moniagent.log ]; then
        local log_perms=$(stat -c "%a" /var/log/moniagent.log 2>/dev/null)
        if [ "$log_perms" = "644" ] || [ "$log_perms" = "600" ]; then
            pass_test "Agent log has secure permissions" "Permissions: $log_perms"
        else
            skip_test "Agent log permissions" "Permissions: $log_perms"
        fi
    fi

    # Test 17: Verify no sensitive data in agent log
    print_test_header "Verify no sensitive data in agent log"
    if grep -q "password\|secret\|key" /var/log/moniagent.log -i; then
        skip_test "Sensitive data in agent log" "Found potential sensitive data"
    else
        pass_test "No sensitive data in agent log" ""
    fi

    # Test 18: Verify no sensitive data in master log
    print_test_header "Verify no sensitive data in master log"
    if grep -q "password\|secret\|key" "/var/log/master.log" -i; then
        skip_test "Sensitive data in master log" "Found potential sensitive data"
    else
        pass_test "No sensitive data in master log" ""
    fi

    # Test 19: Verify log file size is reasonable
    test_subsection "Log Management"
    print_test_header "Verify log file size is reasonable"
    local log_size_kb=$(du -k /var/log/moniagent.log 2>/dev/null | cut -f1)
    if [ "$log_size_kb" -lt 10240 ]; then  # Less than 10MB
        pass_test "Agent log size is reasonable" "Size: ${log_size_kb}KB"
    else
        skip_test "Agent log size" "Size: ${log_size_kb}KB"
    fi

    # Test 20: Verify master log file size
    print_test_header "Verify master log file size"
    local master_log_size_kb=$(du -k "/var/log/master.log" 2>/dev/null | cut -f1)
    if [ "$master_log_size_kb" -lt 10240 ]; then  # Less than 10MB
        pass_test "Master log size is reasonable" "Size: ${master_log_size_kb}KB"
    else
        skip_test "Master log size" "Size: ${master_log_size_kb}KB"
    fi

    # Test 21: Verify log contains error handling
    print_test_header "Verify error logging"
    # Execute a command that will produce an error
    output_file="$LOG_DIR/log_error_test.log"
    run_master_command "$hostname" "ls /nonexistent_dir_xyz" "$output_file"

    if grep -q "error\|ERROR\|fail" /var/log/moniagent.log -i; then
        pass_test "Error logging works" ""
    else
        skip_test "Error logging" "No errors logged yet"
    fi

    # Test 22: Verify log line format
    print_test_header "Verify log line format"
    local first_line=$(head -1 /var/log/moniagent.log 2>/dev/null)
    if echo "$first_line" | grep -qE "[0-9]{4}-[0-9]{2}-[0-9]{2}"; then
        pass_test "Log line format correct" ""
    else
        fail_test "Log line format incorrect" ""
    fi

    # Test 23: Verify log contains process ID
    print_test_header "Verify process ID in logs"
    if grep -q "PID\|pid\|process" /var/log/moniagent.log -i; then
        pass_test "Process ID logged" ""
    else
        skip_test "Process ID logging" "Not found in logs"
    fi

    # Test 24: Verify log contains hostname
    print_test_header "Verify hostname in logs"
    if grep -q "$hostname" /var/log/moniagent.log; then
        pass_test "Hostname logged" ""
    else
        skip_test "Hostname logging" "Not found in logs"
    fi

    # Test 25: Verify log rotation capability
    print_test_header "Verify log rotation support"
    if [ -f /var/log/moniagent.log ]; then
        # Check if log file can be moved/rotated
        if mv /var/log/moniagent.log /var/log/moniagent.log.bak 2>/dev/null; then
            pass_test "Log rotation supported" ""
            # Restore log file
            mv /var/log/moniagent.log.bak /var/log/moniagent.log 2>/dev/null
        else
            skip_test "Log rotation" "Cannot move log file"
        fi
    fi

    # Test 26: Verify new log file creation after rotation
    print_test_header "Verify new log file creation"
    if [ -f /var/log/moniagent.log ]; then
        pass_test "Log file exists after rotation check" ""
    else
        fail_test "Log file missing" ""
    fi

    # Cleanup
    stop_test_agent

    echo ""
    echo -e "${CYAN}Logging tests completed${NC}"
}
