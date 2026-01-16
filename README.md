# MONITOR

[![CI](https://github.com/prakersh/monitor/actions/workflows/ci.yml/badge.svg)](https://github.com/prakersh/monitor/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.5.1-blue.svg)](.last_version)

A distributed command execution and monitoring system with master-agent architecture.

![MONITOR Architecture](https://raw.githubusercontent.com/prakersh/monitor/main/.github/assets/architecture.png)

## Overview

MONITOR is a robust distributed system that enables centralized command execution and system monitoring across multiple machines. Built in C++ for performance and reliability, it uses a master-agent architecture where a central master application can control and monitor multiple agent nodes through Redis as a message broker.

### Key Features

✅ **Distributed Command Execution** - Execute commands on remote agents from a central master with full stdout, stderr, and exit code capture

✅ **Real-time Monitoring** - Track system metrics (CPU, RAM, load average) across all agents with automatic collection every 60 seconds

✅ **Secure File Transfer** - Bidirectional file and directory transfer between master and agents with integrity verification

✅ **Interactive Shell** - Remote shell access to agents via `moni.sh` for interactive command execution

✅ **Automatic Recovery** - Self-healing agent processes with automatic reconnection and crash recovery

✅ **Structured Logging** - Comprehensive logging with categories (INFO, ERROR, DEBUG) and automatic 10MB rotation

✅ **High Performance** - Static-linked C++ binaries with Redis++ for low-latency communication

✅ **Production Ready** - Systemd service support, daemonization, and process management

### Architecture

```
┌─────────────┐         ┌─────────────┐
│   Master    │◄───────►│   Redis     │
│  (C++)      │         │  (Broker)   │
└─────────────┘         └─────────────┘
                              │
                              │
                         ┌────┴────┐
                         │         │
                    ┌────▼──┐  ┌───▼────┐
                    │ Agent │  │ Agent  │
                    │ (C++) │  │ (C++)  │
                    └───────┘  └────────┘
```

**Components:**
- **Master**: Central control application written in C++
- **Agent**: Distributed execution nodes written in C++
- **Redis**: Message broker and state management
- **Communication**: Master ↔ Redis ↔ Agent(s)

### Use Cases

- **DevOps Automation**: Execute deployment scripts across multiple servers
- **System Monitoring**: Collect and analyze metrics from distributed infrastructure
- **Remote Administration**: Manage remote systems from a central location
- **Batch Operations**: Run commands on multiple machines simultaneously
- **File Synchronization**: Distribute configuration files or scripts across nodes

## Quick Start

### Prerequisites

- Linux-based OS (Ubuntu 20.04+ recommended)
- Redis server running
- Sudo access for dependency installation
- Internet connection (for initial setup)

### 1. Clone the Repository

```bash
git clone https://github.com/prakersh/monitor.git
cd monitor
```

### 2. Build the Project

```bash
# Start Redis if not running
sudo systemctl start redis

# Build with your Redis configuration
sudo ./build.sh --redis-host localhost --redis-pass ""
```

**Build Output:**
- `out/master` - Master control application
- `out/agent` - Agent daemon
- `out/monitor` - Self-extracting installer
- `out/monitor.service` - Systemd service file

### 3. Start an Agent

```bash
# Start agent as daemon
sudo out/agent

# Verify agent is running
cat /tmp/agent.pid
```

### 4. Use the Master to Control Agents

```bash
# List all connected agents
./out/master 1

# Execute a command on an agent
./out/master 2 <hostname> "ls -la /tmp"

# Open interactive shell
./out/master 3 <hostname>

# Send file to agent
./out/master 4 <hostname> local_file.txt /tmp/remote_file.txt

# Receive file from agent
./out/master 5 <hostname> /tmp/remote_file.txt received_file.txt
```

### 5. Deploy Agents to Remote Machines

```bash
# Copy installer to remote machine
scp out/monitor user@remote-host:/tmp/

# SSH and install
ssh user@remote-host
sudo /tmp/monitor

# Agent will auto-start and register with master
```

## Installation

### Build Options

```bash
# Build with default settings (auto-incremented version)
sudo ./build.sh --redis-host your.redis.host --redis-pass your_password

# Build with specific version
sudo ./build.sh --redis-host your.redis.host --redis-pass your_password --version 1.5.2

# Build specific component only
sudo ./build.sh --target agent --redis-host your.redis.host --redis-pass your_password
sudo ./build.sh --target master --redis-host your.redis.host --redis-pass your_password
```

**Build Arguments:**
- `--redis-host`: Redis server hostname (required)
- `--redis-pass`: Redis server password (required, use "" for no password)
- `--target`: Component to build (optional: all, agent, master)
- `--version`: Build version (optional, auto-increments if not specified)

### Build Process

The build script performs:
1. **Dependency Installation**: Installs `build-essential`, `cmake`, `g++`, `uuid-dev`, `libhiredis-dev`
2. **Redis++ Compilation**: Clones and builds redis-plus-plus library if not present
3. **Static Compilation**: Compiles with g++ C++17, static linking for portability
4. **Configuration Injection**: Embeds Redis connection details at build time
5. **Installer Creation**: Packages agent binary and systemd service into self-extracting installer

### Installer Usage

The `monitor` binary is a self-extracting installer for agent deployment:

```bash
# Default installation (/etc/monitor)
sudo ./out/monitor

# Custom installation path
sudo ./out/monitor -p /opt/monitor

# Extract only (no service installation)
./out/monitor -e -p /path/to/extract

# Show version
./out/monitor -v
```

**Installer Options:**
- `-p <path>`: Custom installation path (default: `/etc/monitor`)
- `-e`: Extract files only, don't install systemd service
- `-v`: Print version information

## Usage

### Agent Application

```bash
# Start agent as daemon
sudo ./out/agent

# Stop existing agent
sudo ./out/agent -k

# Check version
./out/agent -v
```

**Options:**
- No arguments: Start agent as daemon
- `-k`: Kill existing agent process and exit
- `-v`: Print version information

### Master Application

#### Interactive Mode

Launch without arguments for interactive menu:

```bash
./out/master
```

Available options:
1. **List connected agents** - Shows all active agents with hostname, ID, user
2. **Send command to agent** - Execute command and receive results
3. **Interactive shell** - Open remote shell session (moni.sh)
4. **Send file to agent** - Transfer file/directory to remote agent
5. **Receive file from agent** - Download file/directory from remote agent
6. **Exit**

#### Command Line Mode

```bash
# List all connected agents
./out/master 1

# Execute command on specific agent
./out/master 2 hostname "command"

# Open interactive shell
./out/master 3 hostname

# Transfer files/directories
./out/master 4 hostname local_path remote_path  # Send file/directory
./out/master 5 hostname remote_path local_path  # Receive file/directory

# Show version
./out/master -v
```

### Systemd Service (Agent)

After installation via the monitor installer, the agent runs as a systemd service:

```bash
# Check service status
sudo systemctl status monitor

# Start service
sudo systemctl start monitor

# Stop service
sudo systemctl stop monitor

# Enable auto-start on boot
sudo systemctl enable monitor

# View logs
sudo journalctl -u monitor -f
```

## Features in Detail

### Command Execution

The master can execute commands on any connected agent and receive:
- **Standard Output (stdout)**: Command output
- **Standard Error (stderr)**: Error messages
- **Exit Code**: Command return status

Example:
```bash
./out/master 2 server01 "df -h /"
```

**Output:**
```
Command Execution Result from server01:
Return Code: 0
STDOUT:
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1        50G   20G   28G  42% /

STDERR:
```

### File Transfer

Bidirectional file and directory transfer with:
- Automatic directory detection
- Preserved directory structure
- Binary file support
- Progress logging
- Error handling

**Send file to agent:**
```bash
./out/master 4 server01 config.conf /etc/app/config.conf
```

**Receive file from agent:**
```bash
./out/master 5 server01 /var/log/app.log ./logs/server01_app.log
```

### Metrics Collection

Agents automatically collect and report system metrics every 60 seconds:
- CPU usage
- Available RAM
- Load average (1, 5, 15 minute)
- Timestamp

Metrics are stored in Redis with key: `agent:<hostname>:metrics`

### Process Management

- Agents run as daemon processes
- PID stored in `/tmp/agent.pid`
- Automatic cleanup of existing instances
- Graceful shutdown support
- Crash detection and recovery

### Logging

**Master Logs:**
- Location: `master.log` (in working directory)
- Categories: COMMAND, FILE, CONNECTION
- Rotation: 10MB
- Format: `timestamp level [category] message`

**Agent Logs:**
- Location: `agent.log` (in working directory) or `/var/log/moniagent.log`
- Levels: INFO, ERROR, DEBUG
- Rotation: 10MB
- Format: `timestamp level message`

## Testing

A comprehensive test suite is available with 350+ test cases covering all aspects of the system.

### Running Tests

```bash
cd tests

# Quick smoke tests (recommended for initial verification)
./run_tests.sh --quick

# Full test suite
./run_tests.sh --all

# Specific test categories
./run_tests.sh --build          # Build and installation
./run_tests.sh --agent          # Agent functionality
./run_tests.sh --master         # Master functionality
./run_tests.sh --command        # Command execution
./run_tests.sh --file           # File transfer
./run_tests.sh --metrics        # Metrics collection
./run_tests.sh --process        # Process management
./run_tests.sh --redis          # Redis communication
./run_tests.sh --logging        # Logging
./run_tests.sh --concurrent     # Concurrent operations
./run_tests.sh --stress         # Stress testing
./run_tests.sh --security       # Security tests
./run_tests.sh --recovery       # Recovery and resilience
./run_tests.sh --installer      # Installer functionality
./run_tests.sh --version        # Version management
```

### Test Coverage

The test suite provides comprehensive coverage:
- **Build & Installation**: 30 tests
- **Agent Core**: 25 tests
- **Master Core**: 25 tests
- **Command Execution**: 23 tests
- **File Transfer**: 20 tests
- **Metrics**: 15 tests
- **Process Management**: 15 tests
- **Redis Communication**: 23 tests
- **Logging**: 26 tests
- **Concurrent Operations**: 10 tests
- **Stress Testing**: 15 tests
- **Security**: 28 tests
- **Recovery**: 15 tests
- **Installer**: 35 tests
- **Version Management**: 30 tests

**Total: 355+ test cases**

For detailed test documentation, see [tests/README.md](tests/README.md).

## Redis Key Schema

The system uses Redis for communication and state management. Key patterns:

### Agent Registration & Status
- `agents:<hostname>` → hostname (presence indicates registration)
- `<hostname>_agent_id` → numeric ID
- `<hostname>_user` → current user
- `<hostname>_active` → "yes" (expires every 50s, refreshed every 20s)

### Command Execution
- `run:<hostname>:<command>` → command trigger
- `<uuid>` → command storage
- `<uuid>:return_code` → exit code
- `<uuid>:stdout` → standard output
- `<uuid>:stderr` → standard error

### Metrics
- `agent:<hostname>:metrics` → JSON metrics (CPU, RAM, load)

### File Transfer
- `file_transfer:<hostname>:<uuid>` → transfer metadata

For complete Redis key schema, see [CLAUDE.md](CLAUDE.md#redis-key-schema).

## Troubleshooting

### Common Issues

**1. Agent Connection Problems**
```bash
# Verify Redis is running
sudo systemctl status redis

# Check agent process
ps aux | grep agent

# Review agent logs
cat agent.log

# Verify Redis connectivity
redis-cli ping
```

**2. Command Execution Failures**
```bash
# Verify agent is active
./out/master 1

# Check master logs
cat master.log

# Test with simple command
./out/master 2 <hostname> "echo test"
```

**3. File Transfer Issues**
```bash
# Check disk space
df -h

# Verify permissions
ls -la <file_path>

# Review transfer logs
grep "FILE" master.log
```

**4. Process Management Issues**
```bash
# Check PID file
cat /tmp/agent.pid

# Verify agent is running
ps aux | grep $(cat /tmp/agent.pid)

# Kill existing agent if needed
sudo ./out/agent -k

# Check system logs
sudo journalctl -xe
```

**5. Build Failures**
```bash
# Check dependencies
sudo apt-get install build-essential cmake g++ uuid-dev libhiredis-dev

# Verify Redis++ is installed
ls -la redis-plus-plus/

# Check build logs
cat build.log
```

### Debug Mode

For detailed debugging:
```bash
# Run agent in foreground (not daemonized)
sudo ./out/agent --debug

# Enable verbose logging in master
./out/master --verbose
```

## CI/CD Pipeline

The project includes automated CI/CD using GitHub Actions:

### Workflow Triggers
- Push to main branch
- Pull request to main branch

### CI Steps
1. **Build Verification**: Compiles master and agent components
2. **Integration Testing**:
   - Starts Redis service
   - Deploys and starts agent
   - Tests connectivity
   - Validates file transfer
   - Tests command execution
   - Verifies bidirectional operations

### Test Results
View CI results at: https://github.com/prakersh/monitor/actions

## Development

### Project Structure

```
monitor/
├── src/
│   ├── agent.cpp          # Agent daemon implementation
│   ├── master.cpp         # Master control application
│   └── monitor_inst.sh    # Self-extracting installer
├── out/                   # Build output directory
├── tests/                 # Comprehensive test suite
│   ├── test_framework.sh  # Test utilities
│   ├── run_tests.sh       # Test runner
│   ├── test_*.sh          # Test categories
│   └── README.md          # Test documentation
├── build.sh               # Build script
├── .github/workflows/
│   └── ci.yml             # CI/CD workflow
├── CLAUDE.md              # Developer documentation
├── TEST_PLAN.md           # Test planning document
├── README.md              # This file
└── LICENSE                # MIT License
```

### Building from Source

For detailed build instructions and development setup, see [CLAUDE.md](CLAUDE.md#build--development).

### Version Management

- Version stored in `.last_version` file
- Auto-incremented if not specified
- Check version with `-v` flag: `./agent -v`, `./master -v`

## Contributing

We welcome contributions! Here's how to get started:

1. **Fork the Repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/monitor.git
   ```

2. **Create a Feature Branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make Changes**
   - Follow the existing code style
   - Add tests for new functionality
   - Update documentation as needed

4. **Run Tests**
   ```bash
   cd tests
   ./run_tests.sh --all
   ```

5. **Commit Changes**
   ```bash
   git commit -m "feat: add your feature description"
   ```

6. **Push and Create PR**
   ```bash
   git push origin feature/your-feature-name
   # Create Pull Request on GitHub
   ```

### Development Guidelines

- **Code Style**: Follow C++ best practices and existing patterns
- **Testing**: All new features must include test coverage
- **Documentation**: Update README and CLAUDE.md for significant changes
- **Commits**: Use conventional commits format

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

```
MIT License

Copyright (c) 2024 Prakersh Maheshwari

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Support & Contact

- **Issues**: [GitHub Issues](https://github.com/prakersh/monitor/issues)
- **Documentation**: [CLAUDE.md](CLAUDE.md) for technical details
- **Tests**: [tests/README.md](tests/README.md) for test documentation

### Author

**Prakersh Maheshwari**
Email: Prakersh@live.com
LinkedIn: [Prakersh Maheshwari](https://www.linkedin.com/in/prakersh/)
GitHub: [@prakersh](https://github.com/prakersh)

## Acknowledgments

- Redis++ library for Redis client functionality
- Hiredis for low-level Redis communication
- GitHub Actions for CI/CD pipeline
- Open source community for testing and feedback

## Roadmap

### Current Version: 1.5.1

### Planned Features
- Enhanced security with TLS support
- Web dashboard for monitoring
- Multi-master support
- Container deployment (Docker/Kubernetes)
- Advanced metrics visualization
- Alerting system
- Plugin architecture

### Contributing to Roadmap
Have ideas for new features? Open an issue with the `enhancement` label!

---

**Ready to get started?** See the [Quick Start](#quick-start) section above!

## Installation

### Prerequisites
- Linux-based OS (tested on Ubuntu)
- Redis server
- Internet connection (for initial setup)
- Sudo access

### Quick Start

1. Clone the repository:
```bash
git clone https://github.com/prakersh/monitor.git
cd monitor
```

2. Build the project:
```bash
./build.sh --redis-host your.redis.host --redis-pass your_password
```

This will create:
- `master`: Master executable
- `agent`: Agent executable
- `monitor`: Self-extracting installer for agent deployment

### Build Options

```bash
# Build with default settings (auto-incremented version)
./build.sh --redis-host your.redis.host --redis-pass your_password

# Build with specific version
./build.sh --redis-host your.redis.host --redis-pass your_password --version 1.5.2

# Build specific component
./build.sh --target agent --redis-host your.redis.host --redis-pass your_password
./build.sh --target master --redis-host your.redis.host --redis-pass your_password
```

**Arguments:**
- `--redis-host`: Redis server hostname (required)
- `--redis-pass`: Redis server password (required)
- `--target`: Component to build (optional)
  - Valid targets: all, agent, master (default: all)
- `--version`: Build version (optional)
  - If not specified, auto-increments last version number (e.g., 1.5.2 → 1.5.3)
  - Stored in .last_version file

### Version Information

All components support version checking with the `-v` flag:

```bash
# Check agent version
./agent -v

# Check master version
./master -v

# Check monitor version
./monitor -v
```

### Agent Usage
```bash
# Start agent as daemon
./agent

# Stop existing agent process
./agent -k

# Show version information
./agent -v
```

**Options:**
- `-k`: Kill existing agent process and exit
- `-v`: Print version information
- No arguments: Start agent as daemon

### Master Usage

#### Command Line Mode
```bash
# List all connected agents
./master 1

# Execute command on specific agent
./master 2 hostname "command"

# Open interactive shell
./master 3 hostname

# Transfer files/directories
./master 4 hostname local_path remote_path  # Send file/directory
./master 5 hostname remote_path local_path  # Receive file/directory

# Show version information
./master -v
```

### Installer Usage
```bash
# Default installation (/etc/monitor)
sudo ./monitor

# Custom installation path
sudo ./monitor -p /opt/monitor

# Extract only (no service installation)
./monitor -e -p /path/to/extract

# Show version information
./monitor -v
```

**Installer Options:**
- `-p <path>`: Custom installation path
- `-e`: Extract files only, don't install service
- `-v`: Print version information

## Binary Locations

After building, the following binaries will be created in the `out/` directory:

1. **Master Binary:**
   - Name: `master`
   - Location: `out/master`
   - Purpose: Central control application

2. **Agent Binary:**
   - Name: `agent`
   - Location: `out/agent`
   - Purpose: Distributed execution node

3. **Monitor Installer:**
   - Name: `monitor`
   - Location: `out/monitor`
   - Purpose: Self-extracting agent installer

4. **Service File:**
   - Name: `monitor.service`
   - Location: `out/monitor.service`
   - Purpose: Systemd service configuration

### Installation Paths

When using the monitor installer, files are placed in the following locations:

1. **Default Installation:**
   - Base Path: `/etc/monitor/`
   - Agent Binary: `/etc/monitor/agent`
   - Service File: `/etc/systemd/system/monitor.service`

2. **Custom Installation:**
   - Base Path: User specified with `-p` flag
   - Agent Binary: `<custom_path>/agent`
   - Service File: `/etc/systemd/system/monitor.service`

### Log File Locations

- Agent Log: `agent.log` in agent's working directory
- Master Log: `master.log` in master's working directory
- PID File: `/tmp/agent.pid`

### Agent Deployment

The build process creates a self-extracting installer (`monitor`) that simplifies agent deployment. This installer:
- Packages the agent executable and service file
- Handles installation and service setup
- Supports custom installation paths
- Provides extract-only option for manual setup

To deploy an agent:

1. Copy the installer to target machine:
```bash
scp monitor user@remote:/tmp/
```

2. Run the installer:
```bash
# Default installation (/etc/monitor)
sudo ./monitor

# Custom installation path
sudo ./monitor -p /opt/monitor

# Extract only (no service installation)
./monitor -e -p /path/to/extract
```

The installer will:
- Extract agent files to specified location
- Install systemd service file
- Configure automatic startup
- Start the agent service

**Installer Options:**
- `-p <path>`: Custom installation path
- `-e`: Extract files only, don't install service

### Build Process Details

The build script performs several key functions:

1. **Dependency Check:**
   - Verifies and installs required packages
   - Installs Redis++ if not present
   - Requires sudo access for package installation

2. **Compilation:**
   - Static linking for better portability
   - Injects Redis connection details at build time
   - Creates standalone executables

3. **Installer Creation:**
   - Packages agent and service files
   - Creates self-extracting installer
   - Embeds configuration and startup scripts

### CI/CD Pipeline

The project includes automated CI/CD pipeline using GitHub Actions that:

1. **Build Verification:**
   - Builds both master and agent components
   - Verifies compilation with default configuration
   - Ensures installer creation works correctly

2. **Integration Testing:**
   - Starts Redis service container
   - Deploys and starts agent process
   - Performs connectivity tests
   - Validates file transfer functionality
   - Tests command execution
   - Verifies bidirectional file operations

3. **Test Coverage:**
   - Basic connectivity validation
   - File transfer operations
   - Command execution verification
   - Process management testing

The workflow is triggered on:
- Push to main branch
- Pull request to main branch

Reference workflow file: `.github/workflows/ci.yml`

## Usage

### Starting Redis Server
Ensure Redis server is running and accessible by Master and Agents.

### Agent Application
```bash
# Start agent as daemon
./agent

# Stop existing agent
./agent -k
```

**Options:**
- `-k`: Kill existing agent process and exit
- No arguments: Start agent as daemon

### Master Application

#### Interactive Mode
Launch without arguments for interactive menu:
```bash
./master
```

Available options:
1. List connected agents
2. Send command to agent
3. Interactive shell (moni.sh)
4. Send file to agent
5. Receive file from agent
6. Exit

#### Command Line Mode
```bash
# List all connected agents
./master 1

# Execute command on specific agent
./master 2 hostname "command"

# Open interactive shell
./master 3 hostname

# Transfer files/directories
./master 4 hostname local_path remote_path  # Send file/directory
./master 5 hostname remote_path local_path  # Receive file/directory
```

## Architecture

### Communication Flow
```
Master <-> Redis <-> Agent(s)
```

### Key Components
- **Master**: Central control application
- **Agent**: Distributed execution nodes
- **Redis**: Message broker and state management

### Data Storage
Redis keys used by the system:
- `run:<hostname>:<command>`: Command tracking
- `<uuid>`: Command storage
- `<uuid>:return_code`, `<uuid>:stdout`, `<uuid>:stderr`: Command results
- `agent:<hostname>:metrics`: System metrics
- `<hostname>_agent_id`: Agent identification
- `file_transfer:<hostname>:*`: File transfer operations

## Logging

### Master Logs
- Location: `master.log`
- Categories: COMMAND, FILE, CONNECTION
- Auto-rotation: 10MB
- Format: `timestamp level [category] message`

### Agent Logs
- Location: `agent.log`
- Levels: INFO, ERROR, DEBUG
- Auto-rotation: 10MB
- Format: `timestamp level message`

## File Transfer

The system supports bidirectional file and directory transfers:

1. **Send File/Directory to Agent:**
```bash
./master 4 hostname local_path remote_path
```

2. **Receive File/Directory from Agent:**
```bash
./master 5 hostname remote_path local_path
```

Features:
- Automatic directory detection
- Preserves directory structure
- Handles binary files
- Progress logging
- Error handling with detailed messages

## Process Management

### Agent Process Control
- Runs as a daemon process
- PID stored in `/tmp/agent.pid`
- Kill existing instance with `-k` flag
- Automatic cleanup of existing instances
- Graceful shutdown support

## Troubleshooting


### Common Issues

1. **Agent Connection Problems**
   - Verify Redis server is running
   - Check agent process status: `ps aux | grep agent`
   - Review agent.log for errors
   - Ensure Redis credentials are correct

2. **Command Execution Failures**
   - Verify agent is active in master's list
   - Check command syntax
   - Review master.log for execution details
   - Ensure proper permissions on target system

3. **File Transfer Issues**
   - Verify file/directory permissions
   - Check available disk space
   - Ensure paths are correct and accessible
   - Review logs for transfer errors

4. **Process Management Issues**
   - Check agent.pid file exists and is valid
   - Verify agent process is running
   - Use `-k` flag to cleanly kill existing agent
   - Check system logs for daemon issues

## Contributing
1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License
MIT License - see LICENSE file for details

## Author
Prakersh Maheshwari  
Email: Prakersh@live.com  
LinkedIn: [Prakersh Maheshwari](https://www.linkedin.com/in/prakersh/)
