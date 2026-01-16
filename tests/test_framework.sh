#!/bin/bash
# MONITOR Test Framework
# Provides utilities for running comprehensive tests

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test configuration
TEST_DIR="/tmp/monitor_tests"
LOG_DIR="$TEST_DIR/logs"
RESULTS_DIR="$TEST_DIR/results"
REDIS_HOST="localhost"
REDIS_PORT="6379"
REDIS_PASS=""
BUILD_DIR="/root/projects/monitor"
OUT_DIR="$BUILD_DIR/out"
TIMEOUT=30

# Initialize test framework
init_test_framework() {
    echo -e "${CYAN}Initializing test framework...${NC}"
    mkdir -p "$TEST_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$RESULTS_DIR"

    # Clean up previous test artifacts
    rm -rf "$TEST_DIR"/*_test_*
    rm -f "/var/log/master.log"
    rm -f "$BUILD_DIR/agent.log"
    rm -f /var/log/moniagent.log

    echo "Test directory: $TEST_DIR"
    echo "Log directory: $LOG_DIR"
    echo "Results directory: $RESULTS_DIR"
}

# Cleanup test framework
cleanup_test_framework() {
    echo -e "${CYAN}Cleaning up test framework...${NC}"

    # Kill any running agents
    if [ -f /tmp/agent.pid ]; then
        local pid=$(cat /tmp/agent.pid)
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null
        fi
        rm -f /tmp/agent.pid
    fi

    # Kill any running masters
    pkill -f "out/master" 2>/dev/null

    # Clean up test files
    rm -rf "$TEST_DIR"/*_test_*
}

# Test result functions
pass_test() {
    local test_name="$1"
    local message="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓ PASS${NC}: $test_name"
    [ -n "$message" ] && echo "  $message"
    echo "PASS: $test_name - $message" >> "$RESULTS_DIR/test_results.log"
}

fail_test() {
    local test_name="$1"
    local message="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗ FAIL${NC}: $test_name"
    [ -n "$message" ] && echo "  $message"
    echo "FAIL: $test_name - $message" >> "$RESULTS_DIR/test_results.log"
}

skip_test() {
    local test_name="$1"
    local message="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo -e "${YELLOW}⊘ SKIP${NC}: $test_name"
    [ -n "$message" ] && echo "  $message"
    echo "SKIP: $test_name - $message" >> "$RESULTS_DIR/test_results.log"
}

# Test section header
test_section() {
    local section="$1"
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}TEST SECTION: $section${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo "SECTION: $section" >> "$RESULTS_DIR/test_results.log"
}

# Test subsection header
test_subsection() {
    local subsection="$1"
    echo ""
    echo -e "${MAGENTA}--- $subsection ---${NC}"
    echo "SUBSECTION: $subsection" >> "$RESULTS_DIR/test_results.log"
}

# Print test summary
print_summary() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}TEST SUMMARY${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo -e "Total Tests: $TESTS_RUN"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo -e "${YELLOW}Skipped: $TESTS_SKIPPED${NC}"

    if [ $TESTS_FAILED -eq 0 ] && [ $TESTS_SKIPPED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
    elif [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${YELLOW}All tests passed or skipped!${NC}"
    else
        echo -e "${RED}Some tests failed!${NC}"
    fi

    echo ""
    echo "Detailed results: $RESULTS_DIR/test_results.log"
    echo "Logs: $LOG_DIR"
}

# Check if Redis is running
check_redis() {
    if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ping 2>/dev/null | grep -q "PONG"; then
        return 0
    else
        return 1
    fi
}

# Start Redis (for testing)
start_redis() {
    echo -e "${CYAN}Starting Redis server...${NC}"
    if command -v redis-server &> /dev/null; then
        redis-server --daemonize yes --port "$REDIS_PORT"
        sleep 2
        if check_redis; then
            echo -e "${GREEN}Redis started successfully${NC}"
            return 0
        else
            echo -e "${RED}Failed to start Redis${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}Redis not installed, skipping Redis tests${NC}"
        return 1
    fi
}

# Stop Redis
stop_redis() {
    echo -e "${CYAN}Stopping Redis server...${NC}"
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" shutdown 2>/dev/null || true
    sleep 1
}

# Check if binaries exist
check_binaries() {
    local missing=()

    [ ! -f "$OUT_DIR/agent" ] && missing+=("agent")
    [ ! -f "$OUT_DIR/master" ] && missing+=("master")
    [ ! -f "$OUT_DIR/monitor" ] && missing+=("monitor")
    [ ! -f "$OUT_DIR/monitor.service" ] && missing+=("monitor.service")

    if [ ${#missing[@]} -eq 0 ]; then
        return 0
    else
        echo "Missing binaries: ${missing[*]}"
        return 1
    fi
}

# Wait for condition with timeout
wait_for_condition() {
    local condition_cmd="$1"
    local timeout="$2"
    local interval="${3:-1}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if eval "$condition_cmd" &>/dev/null; then
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    return 1
}

# Run command with timeout
run_with_timeout() {
    local cmd="$1"
    local timeout="$2"
    local output_file="$3"

    timeout "$timeout" bash -c "$cmd" > "$output_file" 2>&1
    local exit_code=$?

    if [ $exit_code -eq 124 ]; then
        echo "Command timed out after ${timeout}s"
        return 124
    fi
    return $exit_code
}

# Create test file with content
create_test_file() {
    local path="$1"
    local size="${2:-1024}"
    local content="${3:-test content}"

    mkdir -p "$(dirname "$path")"
    if [ "$size" -gt 0 ]; then
        # Create file with repeated content to reach desired size
        local repeated_content=""
        while [ ${#repeated_content} -lt $size ]; do
            repeated_content="${repeated_content}${content}"
        done
        echo -n "${repeated_content:0:$size}" > "$path"
    else
        echo "$content" > "$path"
    fi
}

# Create test directory structure
create_test_directory() {
    local path="$1"
    local depth="${2:-1}"
    local files_per_level="${3:-3}"

    mkdir -p "$path"

    for ((i=1; i<=depth; i++)); do
        local current_path="$path/level_$i"
        mkdir -p "$current_path"

        for ((j=1; j<=files_per_level; j++)); do
            create_test_file "$current_path/file_$j.txt" 100 "Test content level $i file $j"
        done
    done
}

# Verify file content
verify_file_content() {
    local file="$1"
    local expected_content="$2"

    if [ ! -f "$file" ]; then
        echo "File does not exist: $file"
        return 1
    fi

    if [ -n "$expected_content" ]; then
        if grep -q "$expected_content" "$file"; then
            return 0
        else
            echo "Expected content '$expected_content' not found in $file"
            return 1
        fi
    fi

    return 0
}

# Verify file size
verify_file_size() {
    local file="$1"
    local expected_size="$2"

    if [ ! -f "$file" ]; then
        echo "File does not exist: $file"
        return 1
    fi

    local actual_size=$(stat -c%s "$file")
    if [ "$actual_size" -eq "$expected_size" ]; then
        return 0
    else
        echo "File size mismatch. Expected: $expected_size, Actual: $actual_size"
        return 1
    fi
}

# Verify directory structure
verify_directory_structure() {
    local dir="$1"
    local expected_depth="$2"
    local expected_files_per_level="${3:-3}"

    if [ ! -d "$dir" ]; then
        echo "Directory does not exist: $dir"
        return 1
    fi

    for ((i=1; i<=expected_depth; i++)); do
        local level_dir="$dir/level_$i"
        if [ ! -d "$level_dir" ]; then
            echo "Level directory does not exist: $level_dir"
            return 1
        fi

        for ((j=1; j<=expected_files_per_level; j++)); do
            local file="$level_dir/file_$j.txt"
            if [ ! -f "$file" ]; then
                echo "File does not exist: $file"
                return 1
            fi
        done
    done

    return 0
}

# Get agent hostname from master list
get_agent_hostname() {
    local output_file="$1"
    local hostname=$(grep -oP "Hostname:\s+\K\w+" "$output_file" | head -1)
    echo "$hostname"
}

# Check if agent is registered in Redis
check_agent_registered() {
    local hostname="$1"
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" exists "agents:$hostname" 2>/dev/null | grep -q "1"
}

# Check if agent is active
check_agent_active() {
    local hostname="$1"
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" get "${hostname}_active" 2>/dev/null | grep -q "yes"
}

# Get command result from Redis
get_command_result() {
    local uuid="$1"
    local field="$2"
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" get "${uuid}:${field}" 2>/dev/null
}

# Wait for command to complete
wait_for_command() {
    local uuid="$1"
    local timeout="${2:-30}"

    wait_for_condition "redis-cli -h '$REDIS_HOST' -p '$REDIS_PORT' exists '${uuid}:return_code' '${uuid}:stdout' '${uuid}:stderr' 2>/dev/null | grep -q '3'" "$timeout" 1
}

# Wait for file transfer to complete
wait_for_file_transfer() {
    local transfer_key="$1"
    local timeout="${2:-60}"

    wait_for_condition "redis-cli -h '$REDIS_HOST' -p '$REDIS_PORT' hget '$transfer_key' status 2>/dev/null | grep -qE '(completed|error)'" "$timeout" 1
}

# Start agent for testing
start_test_agent() {
    local log_file="$LOG_DIR/agent_test.log"
    echo -e "${CYAN}Starting test agent...${NC}"

    # Kill any existing agent
    if [ -f /tmp/agent.pid ]; then
        local pid=$(cat /tmp/agent.pid)
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null
        fi
        rm -f /tmp/agent.pid
    fi

    # Start agent
    sudo "$OUT_DIR/agent" >> "$log_file" 2>&1 &
    local agent_pid=$!

    # Wait for agent to register
    sleep 3

    # Get hostname
    local hostname=$(hostname)

    # Check if agent is registered
    if wait_for_condition "check_agent_registered '$hostname'" 10 1; then
        echo -e "${GREEN}Agent started successfully (PID: $agent_pid, Hostname: $hostname)${NC}"
        echo "$hostname" > "$TEST_DIR/current_agent_hostname"
        echo "$agent_pid" > "$TEST_DIR/current_agent_pid"
        return 0
    else
        echo -e "${RED}Agent failed to register${NC}"
        return 1
    fi
}

# Stop test agent
stop_test_agent() {
    echo -e "${CYAN}Stopping test agent...${NC}"

    if [ -f /tmp/agent.pid ]; then
        local pid=$(cat /tmp/agent.pid)
        if kill -0 "$pid" 2>/dev/null; then
            # Try graceful shutdown first with SIGTERM
            sudo kill -TERM "$pid" 2>/dev/null
            # Wait up to 3 seconds for graceful shutdown
            for i in {1..30}; do
                if ! kill -0 "$pid" 2>/dev/null; then
                    break
                fi
                sleep 0.1
            done
            # Force kill if still running
            if kill -0 "$pid" 2>/dev/null; then
                sudo kill -9 "$pid" 2>/dev/null
            fi
            sleep 1
        fi
        rm -f /tmp/agent.pid
    fi

    if [ -f "$TEST_DIR/current_agent_pid" ]; then
        local pid=$(cat "$TEST_DIR/current_agent_pid")
        if kill -0 "$pid" 2>/dev/null; then
            # Try graceful shutdown first with SIGTERM
            sudo kill -TERM "$pid" 2>/dev/null
            # Wait up to 3 seconds for graceful shutdown
            for i in {1..30}; do
                if ! kill -0 "$pid" 2>/dev/null; then
                    break
                fi
                sleep 0.1
            done
            # Force kill if still running
            if kill -0 "$pid" 2>/dev/null; then
                sudo kill -9 "$pid" 2>/dev/null
            fi
        fi
    fi

    rm -f "$TEST_DIR/current_agent_hostname"
    rm -f "$TEST_DIR/current_agent_pid"

    echo -e "${GREEN}Agent stopped${NC}"
}

# Get current agent hostname
get_current_agent_hostname() {
    if [ -f "$TEST_DIR/current_agent_hostname" ]; then
        cat "$TEST_DIR/current_agent_hostname"
    else
        hostname
    fi
}

# Run a command via master and get result
run_master_command() {
    local hostname="$1"
    local command="$2"
    local output_file="$3"

    sudo "$OUT_DIR/master" 2 "$hostname" "$command" > "$output_file" 2>&1
    return $?
}

# Send file via master
send_file_via_master() {
    local hostname="$1"
    local local_path="$2"
    local remote_path="$3"
    local output_file="$4"

    sudo "$OUT_DIR/master" 4 "$hostname" "$local_path" "$remote_path" > "$output_file" 2>&1
    return $?
}

# Receive file via master
receive_file_via_master() {
    local hostname="$1"
    local remote_path="$2"
    local local_path="$3"
    local output_file="$4"

    sudo "$OUT_DIR/master" 5 "$hostname" "$remote_path" "$local_path" > "$output_file" 2>&1
    return $?
}

# List agents via master
list_agents_via_master() {
    local output_file="$1"

    sudo "$OUT_DIR/master" 1 > "$output_file" 2>&1
    return $?
}

# Verify Redis key exists
verify_redis_key() {
    local key="$1"
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" exists "$key" 2>/dev/null | grep -q "1"
}

# Verify Redis hash field
verify_redis_hash_field() {
    local key="$1"
    local field="$2"
    local expected_value="$3"

    local actual_value=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" hget "$key" "$field" 2>/dev/null)
    [ "$actual_value" = "$expected_value" ]
}

# Verify log file contains
verify_log_contains() {
    local log_file="$1"
    local pattern="$2"

    if [ ! -f "$log_file" ]; then
        echo "Log file does not exist: $log_file"
        return 1
    fi

    if grep -q "$pattern" "$log_file"; then
        return 0
    else
        echo "Pattern '$pattern' not found in $log_file"
        return 1
    fi
}

# Verify log file size
verify_log_size() {
    local log_file="$1"
    local max_size="$2"

    if [ ! -f "$log_file" ]; then
        echo "Log file does not exist: $log_file"
        return 1
    fi

    local actual_size=$(stat -c%s "$log_file")
    if [ "$actual_size" -le "$max_size" ]; then
        return 0
    else
        echo "Log file too large. Size: $actual_size, Max: $max_size"
        return 1
    fi
}

# Test with special characters
test_special_characters() {
    local test_name="$1"
    local string="$2"

    echo -e "${CYAN}Testing: $test_name${NC}"
    echo "String: $string"

    # Check for shell metacharacters
    if echo "$string" | grep -qE '[;&|$`\\]'; then
        echo "Contains shell metacharacters"
        return 1
    fi

    # Check for quotes
    if echo "$string" | grep -qE '["'"'"']'; then
        echo "Contains quotes"
        return 1
    fi

    return 0
}

# Generate random string
generate_random_string() {
    local length="$1"
    tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length"
}

# Generate random file
generate_random_file() {
    local path="$1"
    local size="$2"

    dd if=/dev/urandom of="$path" bs="$size" count=1 2>/dev/null
}

# Verify binary integrity
verify_binary_integrity() {
    local file1="$1"
    local file2="$2"

    if cmp -s "$file1" "$file2"; then
        return 0
    else
        echo "Files are different"
        return 1
    fi
}

# Print test header
print_test_header() {
    local test_name="$1"
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}TEST: $test_name${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Export functions for use in test scripts
export -f pass_test fail_test skip_test test_section test_subsection
export -f check_redis start_redis stop_redis check_binaries
export -f wait_for_condition run_with_timeout
export -f create_test_file create_test_directory
export -f verify_file_content verify_file_size verify_directory_structure
export -f get_agent_hostname check_agent_registered check_agent_active
export -f get_command_result wait_for_command wait_for_file_transfer
export -f start_test_agent stop_test_agent get_current_agent_hostname
export -f run_master_command send_file_via_master receive_file_via_master list_agents_via_master
export -f verify_redis_key verify_redis_hash_field verify_log_contains verify_log_size
export -f test_special_characters generate_random_string generate_random_file verify_binary_integrity
export -f print_test_header

# Set up environment
export REDIS_HOST REDIS_PORT REDIS_PASS
export TEST_DIR LOG_DIR RESULTS_DIR OUT_DIR
