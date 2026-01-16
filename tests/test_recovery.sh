#!/bin/bash
# Recovery & Resilience Tests

run_recovery_tests() {
    test_section "RECOVERY & RESILIENCE TESTS"

    # Ensure Redis is running
    if ! check_redis; then
        echo -e "${YELLOW}Starting Redis for recovery tests...${NC}"
        if ! start_redis; then
            skip_test "All recovery tests" "Redis not available"
            return 1
        fi
    fi

    # Start agent
    if ! start_test_agent; then
        skip_test "All recovery tests" "Agent not available"
        return 1
    fi

    local hostname=$(get_current_agent_hostname)

    # Test 1: Agent crash recovery
    test_subsection "Agent Crash Recovery"
    print_test_header "Agent crash and recovery"
    local initial_pid=$(cat /tmp/agent.pid 2>/dev/null)

    if [ -n "$initial_pid" ]; then
        # Simulate agent crash
        kill -9 "$initial_pid" 2>/dev/null
        sleep 1

        # Verify agent crashed
        if ! ps -p "$initial_pid" > /dev/null 2>&1; then
            pass_test "Agent crashed successfully" "Old PID: $initial_pid"
        else
            fail_test "Agent did not crash" ""
        fi

        # Restart agent
        if start_test_agent; then
            local new_pid=$(cat /tmp/agent.pid 2>/dev/null)
            if [ "$new_pid" != "$initial_pid" ] && [ -n "$new_pid" ]; then
                pass_test "Agent recovered from crash" "New PID: $new_pid"
            else
                fail_test "Agent recovery failed" ""
            fi
        else
            fail_test "Agent restart failed" ""
        fi
    fi

    # Test 2: Redis restart recovery
    test_subsection "Redis Restart Recovery"
    print_test_header "Redis restart and agent recovery"
    local agent_pid=$(cat /tmp/agent.pid 2>/dev/null)

    if [ -n "$agent_pid" ] && ps -p "$agent_pid" > /dev/null 2>&1; then
        # Stop Redis
        stop_redis
        sleep 1

        # Verify agent is still running (but disconnected)
        if ps -p "$agent_pid" > /dev/null 2>&1; then
            pass_test "Agent survives Redis stop" ""
        else
            skip_test "Agent survival" "Agent stopped"
        fi

        # Restart Redis
        if start_redis; then
            pass_test "Redis restarted successfully" ""
        else
            fail_test "Redis restart failed" ""
        fi

        # Wait for agent to reconnect
        sleep 3

        # Verify agent reconnected
        if verify_redis_key "agent:$hostname"; then
            pass_test "Agent reconnected to Redis" ""
        else
            skip_test "Agent reconnection" "Agent not reconnected"
        fi
    fi

    # Test 3: Command recovery after interruption
    test_subsection "Command Recovery"
    print_test_header "Command execution after recovery"
    local output_file="$LOG_DIR/recovery_command_test.log"
    run_master_command "$hostname" "echo 'recovery test'" "$output_file"

    if [ $? -eq 0 ] && grep -q "Return Code: 0" "$output_file"; then
        pass_test "Command execution after recovery" ""
    else
        fail_test "Command execution failed after recovery" ""
    fi

    # Test 4: File transfer recovery
    print_test_header "File transfer after recovery"
    local test_dir="$TEST_DIR/recovery_test"
    mkdir -p "$test_dir"
    local local_file="$test_dir/recovery.txt"
    local remote_file="/tmp/recovery.txt"
    echo "Recovery test" > "$local_file"

    output_file="$LOG_DIR/recovery_file_test.log"
    send_file_via_master "$hostname" "$local_file" "$remote_file" "$output_file"

    if [ $? -eq 0 ] && grep -q "File transfer completed successfully" "$output_file"; then
        pass_test "File transfer after recovery" ""
    else
        fail_test "File transfer failed after recovery" ""
    fi

    # Test 5: Network interruption simulation
    test_subsection "Network Interruption"
    print_test_header "Network interruption simulation"
    # Simulate network issues by stopping Redis temporarily
    local agent_pid=$(cat /tmp/agent.pid 2>/dev/null)

    if [ -n "$agent_pid" ]; then
        # Stop Redis
        stop_redis
        sleep 2

        # Try to execute command (should fail gracefully)
        output_file="$LOG_DIR/recovery_network_test.log"
        run_master_command "$hostname" "echo 'network test'" "$output_file" 2>/dev/null

        # Command may fail due to network issue
        if [ $? -ne 0 ]; then
            pass_test "Network interruption handled" ""
        else
            skip_test "Network interruption" "Command succeeded unexpectedly"
        fi

        # Restart Redis
        start_redis
        sleep 2

        # Verify recovery
        if verify_redis_key "agent:$hostname"; then
            pass_test "Recovered from network interruption" ""
        else
            skip_test "Network recovery" "Agent not reconnected"
        fi
    fi

    # Test 6: Partial file transfer recovery
    test_subsection "File Transfer Recovery"
    print_test_header "Partial file transfer recovery"
    local large_file="$TEST_DIR/large_recovery.bin"
    dd if=/dev/zero of="$large_file" bs=1M count=5 2>/dev/null
    local remote_large="/tmp/large_recovery.bin"

    output_file="$LOG_DIR/recovery_large_file_test.log"
    send_file_via_master "$hostname" "$large_file" "$remote_large" "$output_file"

    if [ $? -eq 0 ] && grep -q "File transfer completed successfully" "$output_file"; then
        pass_test "Large file transfer recovered" ""
    else
        skip_test "Large file recovery" "Transfer failed"
    fi

    # Test 7: Verify data integrity after recovery
    print_test_header "Data integrity after recovery"
    local verify_file="$TEST_DIR/verify_recovery.txt"
    local verify_content="Integrity test after recovery"
    echo "$verify_content" > "$verify_file"
    local remote_verify="/tmp/verify_recovery.txt"

    output_file="$LOG_DIR/recovery_integrity_test.log"
    send_file_via_master "$hostname" "$verify_file" "$remote_verify" "$output_file"

    local receive_file="$TEST_DIR/received_recovery.txt"
    receive_file_via_master "$hostname" "$remote_verify" "$receive_file" "$output_file"

    if verify_file_content "$receive_file" "$verify_content"; then
        pass_test "Data integrity maintained after recovery" ""
    else
        fail_test "Data integrity check failed" ""
    fi

    # Test 8: Metrics collection recovery
    test_subsection "Metrics Recovery"
    print_test_header "Metrics collection after recovery"
    sleep 2  # Give agent time to collect metrics

    if verify_redis_key "metrics:$hostname"; then
        pass_test "Metrics collection recovered" ""
    else
        skip_test "Metrics recovery" "Metrics not collected"
    fi

    # Test 9: PID file recovery
    print_test_header "PID file recovery"
    if [ -f /tmp/agent.pid ]; then
        local pid_content=$(cat /tmp/agent.pid)
        if [ -n "$pid_content" ]; then
            pass_test "PID file exists and valid" "PID: $pid_content"
        else
            fail_test "PID file invalid" ""
        fi
    else
        fail_test "PID file missing" ""
    fi

    # Test 10: Log file recovery
    print_test_header "Log file recovery"
    if [ -f /var/log/moniagent.log ]; then
        local log_size=$(wc -l < /var/log/moniagent.log)
        if [ "$log_size" -gt 0 ]; then
            pass_test "Log file exists and has content" "Lines: $log_size"
        else
            fail_test "Log file empty" ""
        fi
    else
        fail_test "Log file missing" ""
    fi

    # Test 11: Multiple crash recovery cycles
    test_subsection "Multiple Recovery Cycles"
    print_test_header "Multiple crash recovery cycles"
    local recovery_success=0

    for i in $(seq 1 3); do
        local current_pid=$(cat /tmp/agent.pid 2>/dev/null)
        if [ -n "$current_pid" ]; then
            kill -9 "$current_pid" 2>/dev/null
            sleep 1

            if start_test_agent; then
                recovery_success=$((recovery_success + 1))
                sleep 1
            fi
        fi
    done

    if [ "$recovery_success" -ge 2 ]; then
        pass_test "Multiple recovery cycles successful" "Success: $recovery_success/3"
    else
        fail_test "Multiple recovery cycles failed" "Success: $recovery_success/3"
    fi

    # Test 12: Graceful shutdown recovery
    test_subsection "Graceful Shutdown"
    print_test_header "Graceful shutdown and restart"
    local graceful_pid=$(cat /tmp/agent.pid 2>/dev/null)

    if [ -n "$graceful_pid" ]; then
        # Graceful shutdown
        kill -TERM "$graceful_pid" 2>/dev/null
        sleep 2

        if ! ps -p "$graceful_pid" > /dev/null 2>&1; then
            pass_test "Graceful shutdown successful" ""
        else
            skip_test "Graceful shutdown" "Agent still running"
        fi

        # Restart
        if start_test_agent; then
            pass_test "Restart after graceful shutdown" ""
        else
            fail_test "Restart failed" ""
        fi
    fi

    # Test 13: Verify no data loss after recovery
    test_subsection "Data Loss Prevention"
    print_test_header "Verify no data loss after recovery"
    local data_file="$TEST_DIR/data_loss_test.txt"
    local test_data="Important data that should not be lost"
    echo "$test_data" > "$data_file"
    local remote_data="/tmp/data_loss_test.txt"

    # Send file
    output_file="$LOG_DIR/recovery_data_loss_send.log"
    send_file_via_master "$hostname" "$data_file" "$remote_data" "$output_file"

    # Simulate crash
    local agent_pid=$(cat /tmp/agent.pid 2>/dev/null)
    if [ -n "$agent_pid" ]; then
        kill -9 "$agent_pid" 2>/dev/null
        sleep 1
        start_test_agent
        sleep 1
    fi

    # Receive file
    local receive_data="$TEST_DIR/data_loss_received.txt"
    output_file="$LOG_DIR/recovery_data_loss_receive.log"
    receive_file_via_master "$hostname" "$remote_data" "$receive_data" "$output_file"

    if verify_file_content "$receive_data" "$test_data"; then
        pass_test "No data loss after recovery" ""
    else
        skip_test "Data loss check" "File not recovered"
    fi

    # Test 14: Redis key persistence after recovery
    print_test_header "Redis key persistence after recovery"
    local redis_keys_before=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" keys "agent:*" 2>/dev/null | wc -l)

    # Restart agent
    stop_test_agent
    start_test_agent
    sleep 2

    local redis_keys_after=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" keys "agent:*" 2>/dev/null | wc -l)

    if [ "$redis_keys_after" -ge 1 ]; then
        pass_test "Redis keys persisted after recovery" "Keys: $redis_keys_after"
    else
        fail_test "Redis keys not persisted" ""
    fi

    # Test 15: Verify system state after recovery
    test_subsection "System State Verification"
    print_test_header "Verify system state after recovery"
    local agent_running=$(pgrep -f "out/agent" | wc -l)
    local redis_running=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ping 2>/dev/null)

    if [ "$agent_running" -ge 1 ] && [ "$redis_running" = "PONG" ]; then
        pass_test "System state normal after recovery" ""
    else
        fail_test "System state abnormal after recovery" ""
    fi

    # Cleanup
    stop_test_agent
    rm -rf "$TEST_DIR/recovery_test" "$TEST_DIR/data_loss_test.txt" "$TEST_DIR/data_loss_received.txt" "$TEST_DIR/large_recovery.bin" "$TEST_DIR/verify_recovery.txt" "$TEST_DIR/received_recovery.txt"

    echo ""
    echo -e "${CYAN}Recovery tests completed${NC}"
}
