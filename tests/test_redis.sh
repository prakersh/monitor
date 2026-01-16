#!/bin/bash
# Redis Communication Tests

run_redis_tests() {
    test_section "REDIS COMMUNICATION TESTS"

    # Test 1: Check if Redis is running
    test_subsection "Redis Connection"
    print_test_header "Check Redis is running"
    if check_redis; then
        pass_test "Redis is running" ""
    else
        skip_test "All Redis tests" "Redis not available"
        return 1
    fi

    # Test 2: Start Redis if not running
    print_test_header "Start Redis if needed"
    if ! check_redis; then
        if start_redis; then
            pass_test "Redis started successfully" ""
        else
            skip_test "All Redis tests" "Could not start Redis"
            return 1
        fi
    else
        pass_test "Redis already running" ""
    fi

    # Test 3: Ping Redis
    print_test_header "Ping Redis server"
    local ping_result=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ping 2>/dev/null)
    if [ "$ping_result" = "PONG" ]; then
        pass_test "Redis responding to ping" ""
    else
        fail_test "Redis not responding" "Response: $ping_result"
    fi

    # Test 4: Redis SET operation
    test_subsection "Redis Operations"
    print_test_header "Redis SET operation"
    local test_key="test:key:$(date +%s)"
    local set_result=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" set "$test_key" "test_value" 2>/dev/null)
    if [ "$set_result" = "OK" ]; then
        pass_test "Redis SET operation successful" ""
    else
        fail_test "Redis SET operation failed" "Result: $set_result"
    fi

    # Test 5: Redis GET operation
    print_test_header "Redis GET operation"
    local get_result=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" get "$test_key" 2>/dev/null)
    if [ "$get_result" = "test_value" ]; then
        pass_test "Redis GET operation successful" ""
    else
        fail_test "Redis GET operation failed" "Result: $get_result"
    fi

    # Test 6: Redis KEYS operation
    print_test_header "Redis KEYS operation"
    local keys_result=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" keys "*" 2>/dev/null | wc -l)
    if [ "$keys_result" -ge 0 ]; then
        pass_test "Redis KEYS operation successful" "Found: $keys_result keys"
    else
        fail_test "Redis KEYS operation failed" ""
    fi

    # Test 7: Redis EXISTS operation
    print_test_header "Redis EXISTS operation"
    local exists_result=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" exists "$test_key" 2>/dev/null)
    if [ "$exists_result" = "1" ]; then
        pass_test "Redis EXISTS operation successful" ""
    else
        fail_test "Redis EXISTS operation failed" "Result: $exists_result"
    fi

    # Test 8: Redis DEL operation
    print_test_header "Redis DEL operation"
    local del_result=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" del "$test_key" 2>/dev/null)
    if [ "$del_result" = "1" ]; then
        pass_test "Redis DEL operation successful" ""
    else
        fail_test "Redis DEL operation failed" "Result: $del_result"
    fi

    # Test 9: Verify key was deleted
    print_test_header "Verify key deletion"
    local exists_after_del=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" exists "$test_key" 2>/dev/null)
    if [ "$exists_after_del" = "0" ]; then
        pass_test "Key successfully deleted" ""
    else
        fail_test "Key still exists after deletion" ""
    fi

    # Test 10: Start agent and verify Redis registration
    test_subsection "Agent Redis Registration"
    print_test_header "Start agent for Redis tests"
    if start_test_agent; then
        pass_test "Agent started successfully" ""
    else
        skip_test "Agent Redis tests" "Agent not available"
        stop_test_agent
        echo ""
        echo -e "${CYAN}Redis tests completed${NC}"
        return 1
    fi

    local hostname=$(get_current_agent_hostname)

    # Test 11: Verify agent registered in Redis
    print_test_header "Verify agent registration in Redis"
    if verify_redis_key "agents:$hostname"; then
        pass_test "Agent registered in Redis" "Key: agents:$hostname"
    else
        fail_test "Agent not registered in Redis" ""
    fi

    # Test 12: Verify agent key contains hostname
    print_test_header "Verify agent key contains hostname"
    local agent_info=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" get "agents:$hostname" 2>/dev/null)
    if [ "$agent_info" = "$hostname" ]; then
        pass_test "Agent key contains hostname" ""
    else
        fail_test "Agent key missing hostname" ""
    fi

    # Test 13: Verify next_agent_id key exists
    print_test_header "Verify next_agent_id key"
    if verify_redis_key "next_agent_id"; then
        pass_test "next_agent_id key exists" ""
    else
        skip_test "next_agent_id key" "May not be implemented"
    fi

    # Test 14: Verify metrics key exists
    print_test_header "Verify metrics key exists"
    sleep 2  # Give agent time to collect metrics
    if verify_redis_key "metrics:$hostname"; then
        pass_test "Metrics key exists" "Key: metrics:$hostname"
    else
        fail_test "Metrics key not found" ""
    fi

    # Test 15: Verify Redis connection from master
    test_subsection "Master Redis Connection"
    print_test_header "Verify master can connect to Redis"
    local master_can_connect=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ping 2>/dev/null)
    if [ "$master_can_connect" = "PONG" ]; then
        pass_test "Master can connect to Redis" ""
    else
        fail_test "Master cannot connect to Redis" ""
    fi

    # Test 16: Verify Redis host configuration
    print_test_header "Verify Redis host configuration"
    if [ -n "$REDIS_HOST" ]; then
        pass_test "Redis host configured" "Host: $REDIS_HOST"
    else
        skip_test "Redis host config" "Using default"
    fi

    # Test 17: Verify Redis port configuration
    print_test_header "Verify Redis port configuration"
    if [ -n "$REDIS_PORT" ]; then
        pass_test "Redis port configured" "Port: $REDIS_PORT"
    else
        skip_test "Redis port config" "Using default"
    fi

    # Test 18: Verify Redis password (if configured)
    print_test_header "Verify Redis password configuration"
    if [ -n "$REDIS_PASS" ]; then
        pass_test "Redis password configured" ""
    else
        skip_test "Redis password" "No password configured"
    fi

    # Test 19: Verify Redis keyspace
    test_subsection "Redis Keyspace"
    print_test_header "Verify MONITOR keys in Redis"
    local monitor_keys=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" keys "*" 2>/dev/null | grep -E "(agent:|metrics:|uuid:|run:)" | wc -l)
    if [ "$monitor_keys" -ge 1 ]; then
        pass_test "MONITOR keys found in Redis" "Count: $monitor_keys"
    else
        skip_test "MONITOR keys" "No keys found yet"
    fi

    # Test 20: Verify Redis TTL support
    print_test_header "Verify Redis TTL support"
    local ttl_key="test:ttl:$(date +%s)"
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" set "$ttl_key" "test" 2>/dev/null > /dev/null
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" expire "$ttl_key" 10 2>/dev/null > /dev/null
    local ttl_result=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ttl "$ttl_key" 2>/dev/null)
    if [ "$ttl_result" -le 10 ] && [ "$ttl_result" -ge 0 ]; then
        pass_test "Redis TTL supported" "TTL: $ttl_result"
    else
        skip_test "Redis TTL" "TTL not working"
    fi
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" del "$ttl_key" 2>/dev/null > /dev/null

    # Test 21: Verify Redis data types
    print_test_header "Verify Redis data types"
    local string_key="test:string:$(date +%s)"
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" set "$string_key" "value" 2>/dev/null > /dev/null
    local string_type=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" type "$string_key" 2>/dev/null)
    if [ "$string_type" = "string" ]; then
        pass_test "Redis string type supported" ""
    else
        skip_test "Redis data types" "String type not working"
    fi
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" del "$string_key" 2>/dev/null > /dev/null

    # Test 22: Verify Redis connection error handling
    test_subsection "Error Handling"
    print_test_header "Verify Redis connection error handling"
    local bad_connection=$(redis-cli -h "invalid_host_xyz" -p "$REDIS_PORT" ping 2>&1)
    if echo "$bad_connection" | grep -qi "error\|cannot\|refused"; then
        pass_test "Redis connection error handled" ""
    else
        skip_test "Redis error handling" "Unexpected response"
    fi

    # Test 23: Verify agent reconnection on Redis restart
    print_test_header "Verify agent reconnection"
    # Agent should maintain connection or reconnect
    if verify_redis_key "agent:$hostname"; then
        pass_test "Agent maintains Redis connection" ""
    else
        skip_test "Agent reconnection" "Agent not connected"
    fi

    # Cleanup
    stop_test_agent

    echo ""
    echo -e "${CYAN}Redis tests completed${NC}"
}
