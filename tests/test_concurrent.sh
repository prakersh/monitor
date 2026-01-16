#!/bin/bash
# Concurrent Operation Tests

run_concurrent_tests() {
    test_section "CONCURRENT OPERATION TESTS"

    # Ensure Redis is running
    if ! check_redis; then
        echo -e "${YELLOW}Starting Redis for concurrent tests...${NC}"
        if ! start_redis; then
            skip_test "All concurrent tests" "Redis not available"
            return 1
        fi
    fi

    # Test 1: Start multiple agents concurrently
    test_subsection "Multiple Agents"
    print_test_header "Start multiple agents concurrently"
    local agent_count=3
    local pids=()
    local success_count=0

    for i in $(seq 1 $agent_count); do
        # Start agent with unique hostname
        local hostname="test_agent_$i_$(date +%s)"
        sudo REDIS_HOST="$REDIS_HOST" REDIS_PORT="$REDIS_PORT" REDIS_PASS="$REDIS_PASS" \
            "$OUT_DIR/agent" -h "$hostname" > /dev/null 2>&1 &
        pids+=($!)
        sleep 0.5
    done

    # Wait for agents to start
    sleep 3

    # Check how many agents are running
    local running_agents=$(pgrep -f "out/agent" | wc -l)
    if [ "$running_agents" -ge 2 ]; then
        pass_test "Multiple agents running concurrently" "Count: $running_agents"
        success_count=$((success_count + 1))
    else
        fail_test "Not enough agents running" "Count: $running_agents"
    fi

    # Test 2: Verify all agents registered in Redis
    print_test_header "Verify multiple agents in Redis"
    local registered_agents=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" keys "agents:*" 2>/dev/null | wc -l)
    if [ "$registered_agents" -ge 2 ]; then
        pass_test "Multiple agents registered in Redis" "Count: $registered_agents"
        success_count=$((success_count + 1))
    else
        fail_test "Not enough agents registered" "Count: $registered_agents"
    fi

    # Test 3: Send commands to multiple agents concurrently
    test_subsection "Concurrent Commands"
    print_test_header "Send commands to multiple agents concurrently"
    local command_success_count=0
    local output_files=()

    for i in $(seq 1 $agent_count); do
        local hostname="test_agent_$i_$(date +%s)"
        # Try to find the actual hostname
        local actual_hostname=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" keys "agent:*" 2>/dev/null | grep -oP "agent:\\K.*" | head -1)
        if [ -n "$actual_hostname" ]; then
            output_file="$LOG_DIR/concurrent_cmd_${i}_test.log"
            run_master_command "$actual_hostname" "echo 'test $i'" "$output_file" &
            output_files+=("$output_file")
        fi
    done

    # Wait for commands to complete
    sleep 3

    # Check command results
    for output_file in "${output_files[@]}"; do
        if [ -f "$output_file" ] && grep -q "Return Code: 0" "$output_file" 2>/dev/null; then
            command_success_count=$((command_success_count + 1))
        fi
    done

    if [ "$command_success_count" -ge 1 ]; then
        pass_test "Concurrent commands executed" "Success: $command_success_count"
        success_count=$((success_count + 1))
    else
        skip_test "Concurrent commands" "No commands completed"
    fi

    # Test 4: Concurrent file transfers
    test_subsection "Concurrent File Transfers"
    print_test_header "Concurrent file transfers"
    local transfer_success_count=0
    local test_dir="$TEST_DIR/concurrent_test"
    mkdir -p "$test_dir"

    for i in $(seq 1 3); do
        local local_file="$test_dir/file_$i.txt"
        echo "Concurrent test $i" > "$local_file"
        local remote_file="/tmp/concurrent_$i.txt"
        local output_file="$LOG_DIR/concurrent_transfer_${i}_test.log"

        local actual_hostname=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" keys "agent:*" 2>/dev/null | grep -oP "agent:\\K.*" | head -1)
        if [ -n "$actual_hostname" ]; then
            send_file_via_master "$actual_hostname" "$local_file" "$remote_file" "$output_file" &
        fi
    done

    # Wait for transfers to complete
    sleep 5

    # Check transfer results
    for i in $(seq 1 3); do
        output_file="$LOG_DIR/concurrent_transfer_${i}_test.log"
        if [ -f "$output_file" ] && grep -q "File transfer completed successfully" "$output_file" 2>/dev/null; then
            transfer_success_count=$((transfer_success_count + 1))
        fi
    done

    if [ "$transfer_success_count" -ge 1 ]; then
        pass_test "Concurrent file transfers completed" "Success: $transfer_success_count"
        success_count=$((success_count + 1))
    else
        skip_test "Concurrent file transfers" "No transfers completed"
    fi

    # Test 5: Verify metrics collection from multiple agents
    test_subsection "Concurrent Metrics"
    print_test_header "Verify metrics from multiple agents"
    local metrics_count=0

    for i in $(seq 1 5); do
        sleep 1
        local agent_metrics=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" keys "metrics:*" 2>/dev/null | wc -l)
        if [ "$agent_metrics" -ge 2 ]; then
            metrics_count=$((metrics_count + 1))
        fi
    done

    if [ "$metrics_count" -ge 1 ]; then
        pass_test "Multiple agents collecting metrics" "Count: $agent_metrics"
        success_count=$((success_count + 1))
    else
        skip_test "Concurrent metrics" "Not enough metrics collected"
    fi

    # Test 6: Concurrent Redis operations
    test_subsection "Concurrent Redis Operations"
    print_test_header "Concurrent Redis operations"
    local redis_success_count=0

    for i in $(seq 1 5); do
        local key="concurrent_test_$i_$(date +%s)"
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" set "$key" "value_$i" > /dev/null 2>&1 &
    done

    # Wait for operations
    sleep 2

    # Check if keys were created
    local concurrent_keys=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" keys "concurrent_test_*" 2>/dev/null | wc -l)
    if [ "$concurrent_keys" -ge 3 ]; then
        pass_test "Concurrent Redis operations successful" "Keys: $concurrent_keys"
        success_count=$((success_count + 1))
    else
        skip_test "Concurrent Redis operations" "Keys: $concurrent_keys"
    fi

    # Cleanup concurrent keys
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" keys "concurrent_test_*" 2>/dev/null | xargs redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" del > /dev/null 2>&1

    # Test 7: Stop all test agents
    test_subsection "Cleanup"
    print_test_header "Stop all test agents"
    local initial_count=$(pgrep -f "out/agent" | wc -l)
    sudo "$OUT_DIR/agent" -k 2>/dev/null
    sleep 2
    local final_count=$(pgrep -f "out/agent" | wc -l)

    if [ "$final_count" -eq 0 ]; then
        pass_test "All test agents stopped" ""
        success_count=$((success_count + 1))
    else
        fail_test "Some agents still running" "Count: $final_count"
    fi

    # Test 8: Verify no resource leaks
    print_test_header "Verify no resource leaks"
    local agent_processes=$(pgrep -f "out/agent" | wc -l)
    local master_processes=$(pgrep -f "out/master" | wc -l)

    if [ "$agent_processes" -le 1 ] && [ "$master_processes" -le 1 ]; then
        pass_test "No resource leaks detected" "Agents: $agent_processes, Masters: $master_processes"
        success_count=$((success_count + 1))
    else
        skip_test "Resource leaks" "Agents: $agent_processes, Masters: $master_processes"
    fi

    # Test 9: Sequential vs Concurrent performance
    test_subsection "Performance Comparison"
    print_test_header "Sequential vs Concurrent execution"
    local test_hostname=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" keys "agent:*" 2>/dev/null | grep -oP "agent:\\K.*" | head -1)

    if [ -n "$test_hostname" ]; then
        # Start single agent for comparison
        start_test_agent
        test_hostname=$(get_current_agent_hostname)

        # Sequential execution
        local seq_start=$(date +%s)
        for i in $(seq 1 3); do
            output_file="$LOG_DIR/seq_${i}_test.log"
            run_master_command "$test_hostname" "echo 'seq $i'" "$output_file"
        done
        local seq_end=$(date +%s)
        local seq_time=$((seq_end - seq_start))

        # Concurrent execution
        local con_start=$(date +%s)
        for i in $(seq 1 3); do
            output_file="$LOG_DIR/con_${i}_test.log"
            run_master_command "$test_hostname" "echo 'con $i'" "$output_file" &
        done
        wait
        local con_end=$(date +%s)
        local con_time=$((con_end - con_start))

        if [ "$con_time" -le "$seq_time" ]; then
            pass_test "Concurrent execution faster or equal" "Seq: ${seq_time}s, Con: ${con_time}s"
            success_count=$((success_count + 1))
        else
            skip_test "Performance comparison" "Seq: ${seq_time}s, Con: ${con_time}s"
        fi
    fi

    # Test 10: Concurrent Redis key verification
    print_test_header "Concurrent Redis key verification"
    local verify_success=0

    for i in $(seq 1 5); do
        if verify_redis_key "agent:*"; then
            verify_success=$((verify_success + 1))
        fi
    done

    if [ "$verify_success" -ge 3 ]; then
        pass_test "Concurrent Redis verification successful" "Success: $verify_success/5"
        success_count=$((success_count + 1))
    else
        skip_test "Concurrent Redis verification" "Success: $verify_success/5"
    fi

    # Cleanup
    stop_test_agent
    rm -rf "$test_dir"

    echo ""
    echo -e "${CYAN}Concurrent tests completed${NC}"
}
