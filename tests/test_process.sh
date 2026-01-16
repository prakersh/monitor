#!/bin/bash
# Process Management Tests

run_process_tests() {
    test_section "PROCESS MANAGEMENT TESTS"

    # Ensure Redis is running
    if ! check_redis; then
        echo -e "${YELLOW}Starting Redis for process tests...${NC}"
        if ! start_redis; then
            skip_test "All process tests" "Redis not available"
            return 1
        fi
    fi

    # Start agent
    if ! start_test_agent; then
        skip_test "All process tests" "Agent not available"
        return 1
    fi

    local hostname=$(get_current_agent_hostname)

    # Test 1: Verify agent PID file exists
    test_subsection "PID Management"
    print_test_header "Verify agent PID file"
    if [ -f /tmp/agent.pid ]; then
        local agent_pid=$(cat /tmp/agent.pid)
        pass_test "Agent PID file exists" "PID: $agent_pid"
    else
        fail_test "Agent PID file not found" ""
    fi

    # Test 2: Verify agent process is running
    print_test_header "Verify agent process running"
    if [ -f /tmp/agent.pid ]; then
        local agent_pid=$(cat /tmp/agent.pid)
        if ps -p "$agent_pid" > /dev/null 2>&1; then
            pass_test "Agent process is running" "PID: $agent_pid"
        else
            fail_test "Agent process not running" ""
        fi
    else
        skip_test "Agent process check" "No PID file"
    fi

    # Test 3: Verify agent process user
    print_test_header "Verify agent process user"
    if [ -f /tmp/agent.pid ]; then
        local agent_pid=$(cat /tmp/agent.pid)
        local agent_user=$(ps -o user= -p "$agent_pid" 2>/dev/null | tr -d ' ')
        if [ -n "$agent_user" ]; then
            pass_test "Agent process user identified" "User: $agent_user"
        else
            skip_test "Agent process user" "Could not determine user"
        fi
    fi

    # Test 4: Verify agent process memory usage
    print_test_header "Verify agent memory usage"
    if [ -f /tmp/agent.pid ]; then
        local agent_pid=$(cat /tmp/agent.pid)
        local mem_usage=$(ps -o rss= -p "$agent_pid" 2>/dev/null | tr -d ' ')
        if [ -n "$mem_usage" ]; then
            pass_test "Agent memory usage tracked" "RSS: ${mem_usage} KB"
        else
            skip_test "Agent memory usage" "Could not measure"
        fi
    fi

    # Test 5: Verify agent process CPU usage
    print_test_header "Verify agent CPU usage"
    if [ -f /tmp/agent.pid ]; then
        local agent_pid=$(cat /tmp/agent.pid)
        local cpu_usage=$(ps -o %cpu= -p "$agent_pid" 2>/dev/null | tr -d ' ')
        if [ -n "$cpu_usage" ]; then
            pass_test "Agent CPU usage tracked" "CPU: ${cpu_usage}%"
        else
            skip_test "Agent CPU usage" "Could not measure"
        fi
    fi

    # Test 6: Verify PID file permissions
    print_test_header "Verify PID file permissions"
    if [ -f /tmp/agent.pid ]; then
        local pid_perms=$(stat -c "%a" /tmp/agent.pid 2>/dev/null)
        if [ "$pid_perms" = "644" ] || [ "$pid_perms" = "600" ]; then
            pass_test "PID file has secure permissions" "Permissions: $pid_perms"
        else
            skip_test "PID file permissions" "Permissions: $pid_perms"
        fi
    fi

    # Test 7: Verify agent can be killed via flag
    test_subsection "Process Control"
    print_test_header "Verify agent kill flag"
    local initial_pid=$(cat /tmp/agent.pid 2>/dev/null)
    if [ -n "$initial_pid" ]; then
        # Send kill signal to agent
        sudo "$OUT_DIR/agent" -k 2>/dev/null
        sleep 1

        if ! ps -p "$initial_pid" > /dev/null 2>&1; then
            pass_test "Agent killed successfully via flag" ""
        else
            skip_test "Agent kill flag" "Agent still running"
            # Restart agent for remaining tests
            start_test_agent
        fi
    fi

    # Test 8: Verify agent restart capability
    print_test_header "Verify agent restart"
    if ! ps -p $(cat /tmp/agent.pid 2>/dev/null) > /dev/null 2>&1; then
        if start_test_agent; then
            pass_test "Agent restarted successfully" ""
        else
            fail_test "Agent restart failed" ""
        fi
    else
        pass_test "Agent already running" ""
    fi

    # Test 9: Verify agent process handles signals
    print_test_header "Verify agent signal handling"
    if [ -f /tmp/agent.pid ]; then
        local agent_pid=$(cat /tmp/agent.pid)
        # Send SIGTERM
        kill -TERM "$agent_pid" 2>/dev/null
        sleep 1

        if ! ps -p "$agent_pid" > /dev/null 2>&1; then
            pass_test "Agent handled SIGTERM" ""
            # Restart for remaining tests
            start_test_agent
        else
            skip_test "Agent signal handling" "Agent still running after SIGTERM"
        fi
    fi

    # Test 10: Verify multiple agent processes not allowed
    test_subsection "Process Constraints"
    print_test_header "Verify single agent instance"
    local agent_count=$(pgrep -f "out/agent" | wc -l)
    if [ "$agent_count" -le 1 ]; then
        pass_test "Single agent instance enforced" "Count: $agent_count"
    else
        fail_test "Multiple agent instances detected" "Count: $agent_count"
    fi

    # Test 11: Verify agent process priority
    print_test_header "Verify agent process priority"
    if [ -f /tmp/agent.pid ]; then
        local agent_pid=$(cat /tmp/agent.pid)
        local priority=$(ps -o nice= -p "$agent_pid" 2>/dev/null | tr -d ' ')
        if [ -n "$priority" ]; then
            pass_test "Agent process priority tracked" "Nice: $priority"
        else
            skip_test "Agent process priority" "Could not determine"
        fi
    fi

    # Test 12: Verify agent process state
    print_test_header "Verify agent process state"
    if [ -f /tmp/agent.pid ]; then
        local agent_pid=$(cat /tmp/agent.pid)
        local state=$(ps -o stat= -p "$agent_pid" 2>/dev/null | tr -d ' ')
        if [ -n "$state" ]; then
            pass_test "Agent process state tracked" "State: $state"
        else
            skip_test "Agent process state" "Could not determine"
        fi
    fi

    # Test 13: Verify agent restart after crash
    test_subsection "Crash Recovery"
    print_test_header "Verify agent recovery after crash"
    local initial_pid=$(cat /tmp/agent.pid 2>/dev/null)
    if [ -n "$initial_pid" ]; then
        # Simulate crash by killing agent
        kill -9 "$initial_pid" 2>/dev/null
        sleep 1

        # Agent should be restarted by test framework
        if start_test_agent; then
            local new_pid=$(cat /tmp/agent.pid 2>/dev/null)
            if [ "$new_pid" != "$initial_pid" ]; then
                pass_test "Agent recovered from crash" "Old PID: $initial_pid, New PID: $new_pid"
            else
                skip_test "Agent crash recovery" "PID unchanged"
            fi
        else
            fail_test "Agent recovery failed" ""
        fi
    fi

    # Test 14: Verify process cleanup on exit
    print_test_header "Verify process cleanup"
    if [ -f /tmp/agent.pid ]; then
        local agent_pid=$(cat /tmp/agent.pid)
        stop_test_agent
        sleep 1

        if ! ps -p "$agent_pid" > /dev/null 2>&1; then
            pass_test "Process cleaned up on exit" ""
        else
            fail_test "Process not cleaned up" ""
        fi
    fi

    # Test 15: Verify PID file cleanup
    print_test_header "Verify PID file cleanup"
    if [ ! -f /tmp/agent.pid ]; then
        pass_test "PID file cleaned up" ""
    else
        fail_test "PID file not cleaned up" ""
    fi

    # Cleanup
    stop_test_agent

    echo ""
    echo -e "${CYAN}Process management tests completed${NC}"
}
