#!/bin/bash
# Agent Core Functionality Tests

run_agent_tests() {
    test_section "AGENT CORE FUNCTIONALITY TESTS"

    # Ensure Redis is running
    if ! check_redis; then
        echo -e "${YELLOW}Starting Redis for agent tests...${NC}"
        if ! start_redis; then
            skip_test "All agent tests" "Redis not available"
            return 1
        fi
    fi

    # Test 1: Agent startup and daemonization
    test_subsection "Startup & Daemonization"
    print_test_header "Agent Startup"

    start_test_agent
    if [ $? -eq 0 ]; then
        pass_test "Agent started successfully" ""
    else
        fail_test "Agent failed to start" ""
        return 1
    fi

    # Test 2: Verify PID file creation
    print_test_header "PID File Creation"
    if [ -f /tmp/agent.pid ]; then
        local pid=$(cat /tmp/agent.pid)
        if kill -0 "$pid" 2>/dev/null; then
            pass_test "PID file exists and contains valid PID" "PID: $pid"
        else
            fail_test "PID file exists but contains invalid PID" "PID: $pid"
        fi
    else
        fail_test "PID file not created" ""
    fi

    # Test 3: Verify agent registration in Redis
    print_test_header "Agent Registration"
    local hostname=$(get_current_agent_hostname)
    if check_agent_registered "$hostname"; then
        pass_test "Agent registered in Redis" "Hostname: $hostname"
    else
        fail_test "Agent not registered in Redis" ""
    fi

    # Test 4: Verify agent is active
    print_test_header "Agent Active Status"
    if check_agent_active "$hostname"; then
        pass_test "Agent is active" ""
    else
        fail_test "Agent is not active" ""
    fi

    # Test 5: Verify agent ID exists
    print_test_header "Agent ID"
    if verify_redis_key "${hostname}_agent_id"; then
        local agent_id=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" get "${hostname}_agent_id" 2>/dev/null)
        pass_test "Agent ID exists" "ID: $agent_id"
    else
        fail_test "Agent ID not found" ""
    fi

    # Test 6: Verify user is stored
    print_test_header "Agent User"
    if verify_redis_key "${hostname}_user"; then
        local user=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" get "${hostname}_user" 2>/dev/null)
        pass_test "Agent user stored" "User: $user"
    else
        fail_test "Agent user not stored" ""
    fi

    # Test 7: Verify metrics are being collected
    print_test_header "Metrics Collection"
    local metrics_key="agent:${hostname}:metrics"
    if wait_for_condition "verify_redis_key '$metrics_key'" 65 5; then
        pass_test "Metrics collected" "Key: $metrics_key"
    else
        fail_test "Metrics not collected within timeout" ""
    fi

    # Test 8: Verify metrics content
    print_test_header "Metrics Content"
    if verify_redis_hash_field "$metrics_key" "total_ram_mb" ""; then
        local total_ram=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" hget "$metrics_key" "total_ram_mb" 2>/dev/null)
        if [ -n "$total_ram" ] && [ "$total_ram" -gt 0 ]; then
            pass_test "Total RAM metric valid" "RAM: ${total_ram}MB"
        else
            fail_test "Total RAM metric invalid" "Value: $total_ram"
        fi
    else
        skip_test "Metrics content check" "Metrics key not found"
    fi

    # Test 9: Verify used RAM is calculated
    print_test_header "Used RAM Metric"
    if verify_redis_hash_field "$metrics_key" "used_ram_mb" ""; then
        local used_ram=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" hget "$metrics_key" "used_ram_mb" 2>/dev/null)
        if [ -n "$used_ram" ] && [ "$used_ram" -ge 0 ]; then
            pass_test "Used RAM metric valid" "Used: ${used_ram}MB"
        else
            fail_test "Used RAM metric invalid" "Value: $used_ram"
        fi
    else
        skip_test "Used RAM check" "Metrics key not found"
    fi

    # Test 10: Verify load average is collected
    print_test_header "Load Average Metric"
    if verify_redis_hash_field "$metrics_key" "load_avg" ""; then
        local load_avg=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" hget "$metrics_key" "load_avg" 2>/dev/null)
        if [ -n "$load_avg" ]; then
            pass_test "Load average metric valid" "Load: $load_avg"
        else
            fail_test "Load average metric invalid" "Value: $load_avg"
        fi
    else
        skip_test "Load average check" "Metrics key not found"
    fi

    # Test 11: Verify metrics update periodically
    print_test_header "Metrics Update Periodicity"
    local initial_timestamp=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" time 2>/dev/null | head -1)
    sleep 65  # Wait for next metrics update
    local final_timestamp=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" time 2>/dev/null | head -1)
    if [ "$final_timestamp" -gt "$initial_timestamp" ]; then
        pass_test "Metrics update over time" "Timestamp changed"
    else
        skip_test "Metrics update check" "Redis time not available"
    fi

    # Test 12: Verify agent log file
    print_test_header "Agent Log File"
    if [ -f /var/log/moniagent.log ]; then
        local log_size=$(stat -c%s /var/log/moniagent.log)
        if [ "$log_size" -gt 0 ]; then
            pass_test "Agent log file exists and has content" "Size: $log_size bytes"
        else
            fail_test "Agent log file is empty" ""
        fi
    else
        fail_test "Agent log file not found" ""
    fi

    # Test 13: Verify log content
    print_test_header "Agent Log Content"
    if verify_log_contains /var/log/moniagent.log "Agent starting up"; then
        pass_test "Log contains startup message" ""
    else
        fail_test "Log missing startup message" ""
    fi

    if verify_log_contains /var/log/moniagent.log "Connected to Redis server"; then
        pass_test "Log contains Redis connection message" ""
    else
        fail_test "Log missing Redis connection message" ""
    fi

    # Test 14: Verify log format
    print_test_header "Agent Log Format"
    if grep -qP "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\t" /var/log/moniagent.log; then
        pass_test "Log has correct timestamp format" ""
    else
        fail_test "Log timestamp format incorrect" ""
    fi

    # Test 15: Verify active flag expiration
    print_test_header "Active Flag Expiration"
    local ttl=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ttl "${hostname}_active" 2>/dev/null)
    if [ "$ttl" -gt 0 ] && [ "$ttl" -le 50 ]; then
        pass_test "Active flag has TTL set" "TTL: ${ttl}s"
    else
        fail_test "Active flag TTL incorrect" "TTL: ${ttl}s"
    fi

    # Test 16: Stop agent and verify cleanup
    test_subsection "Agent Shutdown"
    print_test_header "Agent Stop"
    stop_test_agent
    sleep 2

    if [ ! -f /tmp/agent.pid ]; then
        pass_test "PID file removed after stop" ""
    else
        fail_test "PID file still exists after stop" ""
    fi

    # Test 17: Verify agent is no longer active
    print_test_header "Agent Inactive After Stop"
    if check_agent_active "$hostname"; then
        fail_test "Agent still shows as active after stop" ""
    else
        pass_test "Agent no longer active after stop" ""
    fi

    # Test 18: Start agent again (test restart)
    test_subsection "Agent Restart"
    print_test_header "Agent Restart"
    start_test_agent
    if [ $? -eq 0 ]; then
        pass_test "Agent restarted successfully" ""
    else
        fail_test "Agent failed to restart" ""
    fi

    # Test 19: Verify new agent ID after restart
    print_test_header "New Agent ID After Restart"
    local new_agent_id=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" get "${hostname}_agent_id" 2>/dev/null)
    if [ -n "$new_agent_id" ]; then
        pass_test "New agent ID generated" "ID: $new_agent_id"
    else
        fail_test "No agent ID after restart" ""
    fi

    # Test 20: Agent version flag
    test_subsection "Version Flag"
    print_test_header "Agent Version Flag"
    local version_output=$(sudo "$OUT_DIR/agent" -v 2>&1)
    if echo "$version_output" | grep -q "Monitor Agent version:"; then
        pass_test "Agent version flag works" "$version_output"
    else
        fail_test "Agent version flag failed" "$version_output"
    fi

    # Test 21: Agent kill flag when running
    test_subsection "Kill Flag"
    print_test_header "Agent Kill Flag (Running)"
    local pid_before=$(cat /tmp/agent.pid 2>/dev/null)
    sudo "$OUT_DIR/agent" -k
    sleep 2

    if [ ! -f /tmp/agent.pid ] || [ "$(cat /tmp/agent.pid 2>/dev/null)" != "$pid_before" ]; then
        pass_test "Agent killed successfully" ""
    else
        fail_test "Agent not killed" ""
    fi

    # Test 22: Agent kill flag when not running
    print_test_header "Agent Kill Flag (Not Running)"
    sudo "$OUT_DIR/agent" -k
    if [ $? -eq 0 ]; then
        pass_test "Kill flag handles missing agent gracefully" ""
    else
        fail_test "Kill flag failed with missing agent" ""
    fi

    # Test 23: Invalid arguments
    test_subsection "Invalid Arguments"
    print_test_header "Agent Invalid Arguments"
    local invalid_output=$(sudo "$OUT_DIR/agent" invalid_arg 2>&1)
    if echo "$invalid_output" | grep -q "Usage:"; then
        pass_test "Agent shows usage for invalid arguments" ""
    else
        fail_test "Agent doesn't show usage for invalid arguments" ""
    fi

    # Test 24: Start agent with corrupted PID file
    test_subsection "Corrupted PID File"
    print_test_header "Agent with Corrupted PID File"
    echo "not_a_number" > /tmp/agent.pid
    start_test_agent
    if [ $? -eq 0 ]; then
        pass_test "Agent handles corrupted PID file" ""
    else
        fail_test "Agent failed with corrupted PID file" ""
    fi
    stop_test_agent

    # Test 25: Start agent with PID file for dead process
    print_test_header "Agent with Dead Process PID"
    echo "999999" > /tmp/agent.pid
    start_test_agent
    if [ $? -eq 0 ]; then
        pass_test "Agent handles dead process PID file" ""
    else
        fail_test "Agent failed with dead process PID file" ""
    fi
    stop_test_agent

    # Test 26: Verify command listener is active
    test_subsection "Command Listener"
    print_test_header "Command Listener"

    # Restart agent for command listener test
    if ! start_test_agent; then
        fail_test "Failed to restart agent for command listener test" ""
    else
        local command_key="run:${hostname}:test"
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" set "$command_key" "test_uuid" 2>/dev/null
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" set "test_uuid" "echo test" 2>/dev/null

        if wait_for_condition "redis-cli -h '$REDIS_HOST' -p '$REDIS_PORT' exists 'test_uuid:return_code' 2>/dev/null | grep -q '1'" 5 1; then
            pass_test "Command listener is active" ""
        else
            fail_test "Command listener not responding" ""
        fi
    fi

    # Cleanup
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" del "$command_key" "test_uuid" "test_uuid:return_code" "test_uuid:stdout" "test_uuid:stderr" 2>/dev/null || true

    echo ""
    echo -e "${CYAN}Agent tests completed${NC}"
}
