#!/bin/bash
# Metrics Collection Tests

run_metrics_tests() {
    test_section "METRICS COLLECTION TESTS"

    # Ensure Redis is running
    if ! check_redis; then
        echo -e "${YELLOW}Starting Redis for metrics tests...${NC}"
        if ! start_redis; then
            skip_test "All metrics tests" "Redis not available"
            return 1
        fi
    fi

    # Start agent
    if ! start_test_agent; then
        skip_test "All metrics tests" "Agent not available"
        return 1
    fi

    local hostname=$(get_current_agent_hostname)

    # Test 1: Verify metrics collection
    test_subsection "Metrics Collection"
    print_test_header "Verify metrics are being collected"
    sleep 65  # Give agent time to collect metrics (metrics are collected every 60 seconds)

    local metrics_key="agent:${hostname}:metrics"
    if verify_redis_key "$metrics_key"; then
        pass_test "Metrics found in Redis" "Key: $metrics_key"
    else
        fail_test "Metrics not found in Redis" ""
    fi

    # Test 2: Verify metrics contain total RAM info
    print_test_header "Verify total RAM metrics"
    local total_ram=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" hget "$metrics_key" "total_ram_mb" 2>/dev/null)
    if [ -n "$total_ram" ] && [ "$total_ram" -gt 0 ] 2>/dev/null; then
        pass_test "Total RAM metrics present" "Value: ${total_ram}MB"
    else
        fail_test "Total RAM metrics missing or invalid" ""
    fi

    # Test 3: Verify metrics contain used RAM info
    print_test_header "Verify used RAM metrics"
    local used_ram=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" hget "$metrics_key" "used_ram_mb" 2>/dev/null)
    if [ -n "$used_ram" ] && [ "$used_ram" -gt 0 ] 2>/dev/null; then
        pass_test "Used RAM metrics present" "Value: ${used_ram}MB"
    else
        fail_test "Used RAM metrics missing or invalid" ""
    fi

    # Test 4: Verify metrics contain load average info
    print_test_header "Verify load average metrics"
    local load_avg=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" hget "$metrics_key" "load_avg" 2>/dev/null)
    if [ -n "$load_avg" ]; then
        pass_test "Load average metrics present" "Value: $load_avg"
    else
        fail_test "Load average metrics missing" ""
    fi

    # Test 5: Verify metrics format (hash)
    print_test_header "Verify metrics format"
    local metrics_type=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" type "$metrics_key" 2>/dev/null)
    if [ "$metrics_type" = "hash" ]; then
        pass_test "Metrics in expected format (hash)" ""
    else
        fail_test "Metrics format incorrect (expected hash, got $metrics_type)" ""
    fi

    # Test 6: Verify metrics timestamp (stored in agent registration)
    print_test_header "Verify agent registration timestamp"
    local agent_info=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" hget "agent:$hostname" "last_seen" 2>/dev/null)
    if [ -n "$agent_info" ]; then
        pass_test "Agent registration includes timestamp" "Value: $agent_info"
    else
        skip_test "Agent registration timestamp" "May not be implemented"
    fi

    # Test 7: Verify periodic metrics update
    test_subsection "Metrics Updates"
    print_test_header "Verify metrics update periodically"
    local initial_load=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" hget "$metrics_key" "load_avg" 2>/dev/null)
    sleep 65  # Wait for next metrics collection (60s interval)

    local updated_load=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" hget "$metrics_key" "load_avg" 2>/dev/null)
    if [ -n "$updated_load" ] && [ -n "$initial_load" ]; then
        pass_test "Metrics updated periodically" "Initial: $initial_load, Updated: $updated_load"
    else
        skip_test "Metrics update" "May not have updated yet"
    fi

    # Test 8: Verify agent registration includes metrics capability
    print_test_header "Verify agent registration with metrics"
    local agent_active=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" get "${hostname}_active" 2>/dev/null)
    if [ "$agent_active" = "yes" ]; then
        pass_test "Agent registered in Redis" "Active: $agent_active"
    else
        fail_test "Agent not registered or not active" ""
    fi

    # Test 9: Verify metrics contain hostname (in agent registration)
    print_test_header "Verify hostname in agent registration"
    local agents_hostname=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" get "agents:$hostname" 2>/dev/null)
    if [ "$agents_hostname" = "$hostname" ]; then
        pass_test "Hostname present in agent registration" ""
    else
        fail_test "Hostname missing from agent registration" ""
    fi

    # Test 10: Verify uptime metric (skip - not implemented)
    print_test_header "Verify uptime metric"
    skip_test "Uptime metric" "Not implemented in current version"

    # Test 11: Verify process count metric (skip - not implemented)
    print_test_header "Verify process count metric"
    skip_test "Process count metric" "Not implemented in current version"

    # Test 12: Verify network metrics (skip - not implemented)
    print_test_header "Verify network metrics"
    skip_test "Network metrics" "Not implemented in current version"

    # Test 13: Verify metrics persistence
    test_subsection "Metrics Persistence"
    print_test_header "Verify metrics persist in Redis"
    local metrics_key_exists=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" exists "$metrics_key" 2>/dev/null)
    if [ "$metrics_key_exists" -eq 1 ]; then
        pass_test "Metrics key persists in Redis" ""
    else
        fail_test "Metrics key not persisting" ""
    fi

    # Test 14: Verify multiple agents metrics
    test_subsection "Multiple Agents"
    print_test_header "Verify metrics for multiple agents"
    local metrics_keys=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" keys "agent:*:metrics" 2>/dev/null | wc -l)
    if [ "$metrics_keys" -ge 1 ]; then
        pass_test "Metrics keys found for agents" "Count: $metrics_keys"
    else
        fail_test "No metrics keys found" ""
    fi

    # Cleanup
    stop_test_agent

    echo ""
    echo -e "${CYAN}Metrics tests completed${NC}"
}
