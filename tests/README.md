# MONITOR Test Suite

Comprehensive test suite for the MONITOR distributed command execution and monitoring system.

## Overview

This test suite provides comprehensive testing for all aspects of the MONITOR system, including:
- Build and installation
- Agent functionality
- Master functionality
- Command execution
- File transfer
- Metrics collection
- Process management
- Redis communication
- Logging
- Concurrent operations
- Stress testing
- Security
- Recovery and resilience
- Installer
- Version management

## Test Categories

### Quick Tests (Smoke Tests)
Run basic functionality tests to verify the system works:
```bash
./run_tests.sh --quick
```

### Full Test Suite
Run all available tests:
```bash
./run_tests.sh --all
```

### Individual Test Categories

You can run specific test categories:

```bash
# Build tests
./run_tests.sh --build

# Agent tests
./run_tests.sh --agent

# Master tests
./run_tests.sh --master

# Command execution tests
./run_tests.sh --command

# File transfer tests
./run_tests.sh --file

# Metrics tests
./run_tests.sh --metrics

# Process management tests
./run_tests.sh --process

# Redis communication tests
./run_tests.sh --redis

# Logging tests
./run_tests.sh --logging

# Concurrent operation tests
./run_tests.sh --concurrent

# Stress tests
./run_tests.sh --stress

# Security tests
./run_tests.sh --security

# Recovery tests
./run_tests.sh --recovery

# Installer tests
./run_tests.sh --installer

# Version management tests
./run_tests.sh --version
```

### Multiple Categories
Run multiple specific categories:
```bash
./run_tests.sh --agent --master --command
```

## Prerequisites

### System Requirements
- Linux-based OS (Ubuntu 20.04+ recommended)
- Redis server
- Root/sudo access
- At least 2GB RAM
- 10GB disk space

### Required Dependencies
- `build-essential`
- `cmake`
- `g++`
- `uuid-dev`
- `libhiredis-dev`
- `redis-plus-plus`
- `redis-server`
- `tar`
- `dd`
- `stat`
- `strings`
- `ldd`

### Build MONITOR First
Before running tests, ensure MONITOR is built:
```bash
cd /root/projects/monitor
sudo ./build.sh --redis-host localhost --redis-pass ""
```

## Test Structure

### Directory Layout
```
tests/
├── test_framework.sh      # Core test utilities
├── run_tests.sh          # Main test runner
├── test_build.sh         # Build tests
├── test_agent.sh         # Agent tests
├── test_master.sh        # Master tests
├── test_command.sh       # Command execution tests
├── test_file.sh          # File transfer tests
├── test_metrics.sh       # Metrics tests
├── test_process.sh       # Process management tests
├── test_redis.sh         # Redis communication tests
├── test_logging.sh       # Logging tests
├── test_concurrent.sh    # Concurrent operation tests
├── test_stress.sh        # Stress tests
├── test_security.sh      # Security tests
├── test_recovery.sh      # Recovery tests
├── test_installer.sh     # Installer tests
├── test_version.sh       # Version tests
└── README.md             # This file
```

### Test Output
- Test results are logged to `/tmp/monitor_tests/results/test_results.log`
- Detailed logs are stored in `/tmp/monitor_tests/logs/`
- Summary is displayed in console

## Test Framework Features

### Test Functions
- `pass_test` - Mark a test as passed
- `fail_test` - Mark a test as failed
- `skip_test` - Mark a test as skipped
- `test_section` - Create a test section header
- `test_subsection` - Create a test subsection header
- `print_test_header` - Print test name header

### Utility Functions
- `check_redis` - Check if Redis is running
- `start_redis` - Start Redis server
- `stop_redis` - Stop Redis server
- `check_binaries` - Verify all binaries exist
- `start_test_agent` - Start agent for testing
- `stop_test_agent` - Stop agent
- `run_master_command` - Execute command via master
- `send_file_via_master` - Send file via master
- `receive_file_via_master` - Receive file via master
- `list_agents_via_master` - List agents via master
- `verify_redis_key` - Verify Redis key exists
- `verify_file_content` - Verify file content
- `verify_file_size` - Verify file size
- `wait_for_condition` - Wait for condition with timeout
- `run_with_timeout` - Run command with timeout

## Test Coverage

### Build Tests (test_build.sh)
- Binary existence and permissions
- Static linking verification
- Version embedding
- Dependency checks
- Service file validation
- Installer payload verification
- Placeholder replacement

### Agent Tests (test_agent.sh)
- Startup and daemonization
- PID file management
- Redis registration
- Metrics collection
- Command listener
- Process management
- Version flag
- Kill flag
- Error handling

### Master Tests (test_master.sh)
- Version flag
- Agent listing
- CLI mode
- Interactive mode
- Command execution
- Error handling
- Logging
- Redis connection

### Command Execution Tests (test_command.sh)
- Basic commands (ls, pwd, whoami, hostname)
- Commands with output (stdout, stderr)
- Exit codes
- Special characters
- Pipes and redirection
- Long-running commands
- Error handling
- cd command (special handling)

### File Transfer Tests (test_file.sh)
- Single file transfer (text, binary)
- Large file transfer
- Empty file transfer
- File with special characters
- Directory transfer
- Empty directory transfer
- Multiple file transfers
- UTF-8 file transfer
- Path handling
- Error handling

### Security Tests (test_security.sh)
- Command injection attempts
- Path traversal attempts
- Input validation
- Special characters
- Unicode handling
- Sensitive file access
- File permissions
- Redis authentication
- Process security
- Log security

### Other Test Categories
- **Metrics**: Collection, accuracy, periodic updates
- **Process**: PID management, restart, recovery
- **Redis**: Connection, key operations, error handling
- **Logging**: Format, rotation, content
- **Concurrent**: Multiple agents, simultaneous operations
- **Stress**: Load testing, resource exhaustion
- **Recovery**: Failure scenarios, network issues
- **Installer**: Installation, extraction, service management
- **Version**: Version management, increment logic

## Running Tests

### Basic Usage
```bash
cd /root/projects/monitor/tests
chmod +x run_tests.sh test_*.sh
./run_tests.sh --quick
```

### With Custom Redis
```bash
export REDIS_HOST=your.redis.host
export REDIS_PORT=6379
export REDIS_PASS=your_password
./run_tests.sh --all
```

### Verbose Output
Tests output detailed information to console and log files:
```bash
./run_tests.sh --all 2>&1 | tee test_output.log
```

### Running as Root
Many tests require root access:
```bash
sudo ./run_tests.sh --all
```

## Test Results

### Success Criteria
- All tests pass (no failures)
- No crashes or hangs
- No data corruption
- Performance within limits
- Security vulnerabilities identified

### Test Output Example
```
========================================
TEST SECTION: BUILD & INSTALLATION TESTS
========================================

--- Binary Existence ---
TEST: Check Binaries Exist
✓ PASS: Binaries exist
  agent, master, monitor, monitor.service found

--- Binary Permissions ---
TEST: Binary Permissions
✓ PASS: agent is executable
✓ PASS: master is executable
✓ PASS: monitor is executable
✓ PASS: All binaries are executable

========================================
TEST SUMMARY
========================================
Total Tests: 100
Passed: 95
Failed: 0
Skipped: 5
All tests passed!
```

## Troubleshooting

### Redis Not Running
```bash
sudo systemctl start redis
# or
redis-server --daemonize yes
```

### Tests Fail Due to Permissions
Run with sudo:
```bash
sudo ./run_tests.sh --all
```

### Agent Won't Start
Check if another agent is running:
```bash
sudo out/agent -k
./run_tests.sh --agent
```

### Out of Disk Space
Clean up test artifacts:
```bash
rm -rf /tmp/monitor_tests/*
rm -f /var/log/moniagent.log
rm -f master.log
```

### Redis Connection Issues
Verify Redis is accessible:
```bash
redis-cli -h localhost -p 6379 ping
```

## CI/CD Integration

### GitHub Actions
The test suite is designed to work with CI/CD:
```yaml
- name: Run Tests
  run: |
    cd tests
    chmod +x run_tests.sh test_*.sh
    ./run_tests.sh --quick
```

### Docker Testing
```bash
docker run -it --rm \
  -v $(pwd):/monitor \
  -w /monitor/tests \
  ubuntu:20.04 \
  bash -c "./run_tests.sh --quick"
```

## Performance Considerations

### Test Duration
- Quick tests: ~5 minutes
- Full test suite: ~30-60 minutes
- Stress tests: ~2-4 hours

### Resource Usage
- CPU: May spike during stress tests
- Memory: ~500MB-1GB during tests
- Disk: ~100MB-500MB for test artifacts
- Network: Local Redis communication

## Contributing

### Adding New Tests
1. Create new test file: `test_new_feature.sh`
2. Implement `run_new_feature_tests()` function
3. Add to `run_tests.sh` case statement
4. Update this README

### Test Best Practices
- Use descriptive test names
- Clean up after tests
- Handle errors gracefully
- Log detailed information
- Verify results
- Skip tests when appropriate

## License

MIT License - See LICENSE file for details

## Support

For issues or questions:
- Check test logs in `/tmp/monitor_tests/logs/`
- Review test results in `/tmp/monitor_tests/results/`
- Check MONITOR documentation in parent directory
