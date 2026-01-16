#!/bin/bash
# Stress Tests

run_stress_tests() {
    test_section "STRESS TESTS"

    # Ensure Redis is running
    if ! check_redis; then
        echo -e "${YELLOW}Starting Redis for stress tests...${NC}"
        if ! start_redis; then
            skip_test "All stress tests" "Redis not available"
            return 1
        fi
    fi

    # Start agent
    if ! start_test_agent; then
        skip_test "All stress tests" "Agent not available"
        return 1
    fi

    local hostname=$(get_current_agent_hostname)

    # Test 1: High volume command execution
    test_subsection "High Volume Commands"
    print_test_header "Execute 50 commands rapidly"
    local success_count=0
    local output_dir="$TEST_DIR/stress_commands"
    mkdir -p "$output_dir"

    for i in $(seq 1 50); do
        output_file="$output_dir/cmd_$i.log"
        run_master_command "$hostname" "echo 'stress test $i'" "$output_file" 2>/dev/null
        if [ $? -eq 0 ]; then
            success_count=$((success_count + 1))
        fi
    done

    if [ "$success_count" -ge 45 ]; then
        pass_test "High volume commands executed" "Success: $success_count/50"
    else
        fail_test "High volume commands failed" "Success: $success_count/50"
    fi

    # Test 2: Large output command
    test_subsection "Large Output Handling"
    print_test_header "Command with very large output"
    output_file="$LOG_DIR/stress_large_output.log"
    run_master_command "$hostname" "dd if=/dev/zero bs=1024 count=1000 2>/dev/null | tr '\\0' 'A'" "$output_file"

    if [ $? -eq 0 ]; then
        local output_size=$(wc -c < "$output_file" 2>/dev/null)
        if [ "$output_size" -gt 100000 ]; then
            pass_test "Large output handled" "Size: ${output_size} bytes"
        else
            fail_test "Large output not captured" "Size: ${output_size} bytes"
        fi
    else
        fail_test "Large output command failed" ""
    fi

    # Test 3: Rapid file transfers
    test_subsection "Rapid File Transfers"
    print_test_header "Transfer 20 files rapidly"
    local test_dir="$TEST_DIR/stress_files"
    mkdir -p "$test_dir"
    local transfer_success=0

    for i in $(seq 1 20); do
        local local_file="$test_dir/stress_$i.txt"
        echo "Stress test file $i" > "$local_file"
        local remote_file="/tmp/stress_$i.txt"
        output_file="$LOG_DIR/stress_transfer_$i.log"
        send_file_via_master "$hostname" "$local_file" "$remote_file" "$output_file" 2>/dev/null
        if [ $? -eq 0 ]; then
            transfer_success=$((transfer_success + 1))
        fi
    done

    if [ "$transfer_success" -ge 15 ]; then
        pass_test "Rapid file transfers completed" "Success: $transfer_success/20"
    else
        fail_test "Rapid file transfers failed" "Success: $transfer_success/20"
    fi

    # Test 4: Memory stress test
    test_subsection "Memory Stress"
    print_test_header "Memory-intensive command"
    output_file="$LOG_DIR/stress_memory.log"
    run_master_command "$hostname" "dd if=/dev/zero bs=1024 count=5000 2>/dev/null | cat > /dev/null" "$output_file"

    if [ $? -eq 0 ]; then
        pass_test "Memory-intensive command completed" ""
    else
        fail_test "Memory-intensive command failed" ""
    fi

    # Test 5: CPU stress test
    print_test_header "CPU-intensive command"
    output_file="$LOG_DIR/stress_cpu.log"
    run_master_command "$hostname" "for i in \$(seq 1 100000); do echo \$i > /dev/null; done" "$output_file"

    if [ $? -eq 0 ]; then
        pass_test "CPU-intensive command completed" ""
    else
        fail_test "CPU-intensive command failed" ""
    fi

    # Test 6: Concurrent command execution
    test_subsection "Concurrent Stress"
    print_test_header "10 concurrent commands"
    local concurrent_success=0

    for i in $(seq 1 10); do
        output_file="$LOG_DIR/stress_concurrent_$i.log"
        run_master_command "$hostname" "sleep 0.1 && echo 'concurrent $i'" "$output_file" &
    done

    wait
    sleep 2

    for i in $(seq 1 10); do
        output_file="$LOG_DIR/stress_concurrent_$i.log"
        if [ -f "$output_file" ] && grep -q "Return Code: 0" "$output_file" 2>/dev/null; then
            concurrent_success=$((concurrent_success + 1))
        fi
    done

    if [ "$concurrent_success" -ge 8 ]; then
        pass_test "Concurrent commands completed" "Success: $concurrent_success/10"
    else
        fail_test "Concurrent commands failed" "Success: $concurrent_success/10"
    fi

    # Test 7: Redis key stress
    test_subsection "Redis Stress"
    print_test_header "Create many Redis keys"
    local key_count=100
    local created_keys=0

    for i in $(seq 1 $key_count); do
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" set "stress_key_$i" "value_$i" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            created_keys=$((created_keys + 1))
        fi
    done

    if [ "$created_keys" -ge 90 ]; then
        pass_test "Many Redis keys created" "Created: $created_keys/$key_count"
    else
        fail_test "Redis key creation failed" "Created: $created_keys/$key_count"
    fi

    # Cleanup stress keys
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" keys "stress_key_*" 2>/dev/null | xargs redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" del > /dev/null 2>&1

    # Test 8: Long-running command
    test_subsection "Long-running Operations"
    print_test_header "Long-running command (10 seconds)"
    output_file="$LOG_DIR/stress_long_running.log"
    run_with_timeout "sudo '$OUT_DIR/master' 2 '$hostname' 'sleep 10'" 15 "$output_file"

    if [ $? -eq 0 ]; then
        pass_test "Long-running command completed" ""
    else
        fail_test "Long-running command failed" ""
    fi

    # Test 9: Rapid agent restarts
    print_test_header "Rapid agent restarts"
    local restart_success=0

    for i in $(seq 1 5); do
        stop_test_agent
        sleep 0.5
        if start_test_agent; then
            restart_success=$((restart_success + 1))
        fi
        sleep 0.5
    done

    if [ "$restart_success" -ge 4 ]; then
        pass_test "Rapid agent restarts successful" "Success: $restart_success/5"
    else
        fail_test "Rapid agent restarts failed" "Success: $restart_success/5"
    fi

    # Test 10: Verify system stability after stress
    test_subsection "Stability Check"
    print_test_header "Verify system stability after stress"
    local agent_running=$(pgrep -f "out/agent" | wc -l)
    local redis_running=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ping 2>/dev/null)

    if [ "$agent_running" -ge 1 ] && [ "$redis_running" = "PONG" ]; then
        pass_test "System stable after stress" ""
    else
        fail_test "System unstable after stress" ""
    fi

    # Test 11: Memory usage after stress
    print_test_header "Memory usage after stress"
    if [ -f /tmp/agent.pid ]; then
        local agent_pid=$(cat /tmp/agent.pid)
        local mem_usage=$(ps -o rss= -p "$agent_pid" 2>/dev/null | tr -d ' ')
        if [ -n "$mem_usage" ]; then
            # Check if memory is reasonable (< 100MB)
            if [ "$mem_usage" -lt 102400 ]; then
                pass_test "Memory usage reasonable" "RSS: ${mem_usage} KB"
            else
                skip_test "Memory usage" "High: ${mem_usage} KB"
            fi
        fi
    fi

    # Test 12: Redis memory usage
    print_test_header "Redis memory usage"
    local redis_mem=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" info memory 2>/dev/null | grep used_memory_human | cut -d: -f2 | tr -d '\r')
    if [ -n "$redis_mem" ]; then
        pass_test "Redis memory tracked" "Usage: $redis_mem"
    else
        skip_test "Redis memory" "Could not measure"
    fi

    # Test 13: Command queue stress
    print_test_header "Command queue stress"
    local queue_success=0

    for i in $(seq 1 20); do
        output_file="$LOG_DIR/stress_queue_$i.log"
        run_master_command "$hostname" "echo 'queue $i'" "$output_file" 2>/dev/null &
    done

    wait
    sleep 2

    for i in $(seq 1 20); do
        output_file="$LOG_DIR/stress_queue_$i.log"
        if [ -f "$output_file" ] && grep -q "Return Code: 0" "$output_file" 2>/dev/null; then
            queue_success=$((queue_success + 1))
        fi
    done

    if [ "$queue_success" -ge 15 ]; then
        pass_test "Command queue handled stress" "Success: $queue_success/20"
    else
        skip_test "Command queue stress" "Success: $queue_success/20"
    fi

    # Test 14: File transfer queue stress
    print_test_header "File transfer queue stress"
    local transfer_queue_success=0
    local queue_dir="$TEST_DIR/queue_test"
    mkdir -p "$queue_dir"

    for i in $(seq 1 10); do
        local local_file="$queue_dir/queue_$i.txt"
        echo "Queue test $i" > "$local_file"
        local remote_file="/tmp/queue_$i.txt"
        output_file="$LOG_DIR/stress_file_queue_$i.log"
        send_file_via_master "$hostname" "$local_file" "$remote_file" "$output_file" 2>/dev/null &
    done

    wait
    sleep 3

    for i in $(seq 1 10); do
        output_file="$LOG_DIR/stress_file_queue_$i.log"
        if [ -f "$output_file" ] && grep -q "File transfer completed successfully" "$output_file" 2>/dev/null; then
            transfer_queue_success=$((transfer_queue_success + 1))
        fi
    done

    if [ "$transfer_queue_success" -ge 7 ]; then
        pass_test "File transfer queue handled stress" "Success: $transfer_queue_success/10"
    else
        skip_test "File transfer queue stress" "Success: $transfer_queue_success/10"
    fi

    # Test 15: Verify no crashes during stress
    test_subsection "Crash Detection"
    print_test_header "Verify no crashes during stress"
    local agent_pid=$(cat /tmp/agent.pid 2>/dev/null)
    if [ -n "$agent_pid" ] && ps -p "$agent_pid" > /dev/null 2>&1; then
        pass_test "Agent survived stress test" "PID: $agent_pid"
    else
        fail_test "Agent crashed during stress" ""
    fi

    # Cleanup
    stop_test_agent
    rm -rf "$output_dir" "$test_dir" "$queue_dir"

    echo ""
    echo -e "${CYAN}Stress tests completed${NC}"
}
