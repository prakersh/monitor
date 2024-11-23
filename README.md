# MONITOR
A distributed command execution and monitoring system with master-agent architecture

## Overview
MONITOR is a robust distributed system that enables centralized command execution and system monitoring across multiple machines. It uses a master-agent architecture where a central master application can control and monitor multiple agent nodes through Redis.

### Key Features
- **Distributed Command Execution**: Execute commands on remote agents from a central master
- **Real-time Monitoring**: Track system metrics (CPU, RAM, load) across all agents
- **Secure File Transfer**: Bidirectional file/directory transfer between master and agents
- **Interactive Shell**: Remote shell access to agents via moni.sh
- **Automatic Recovery**: Self-healing agent processes with automatic reconnection
- **Structured Logging**: Comprehensive logging with rotation

#### Master  
1. **Command Execution:** Send commands to agents and receive their execution results (stdout, stderr, return code)
2. **Agent Management:** List connected agents, register new agents, and manage their states
3. **File Transfer:** Send and receive files/directories between master and agents
4. **Enhanced Logging:** Structured logging with categories and automatic log rotation
5. **Interactive CLI:** Multiple operation modes including:
   - Single command execution
   - Interactive shell (moni.sh)
   - File transfer operations
6. **Command Line Interface:** Support for both interactive and CLI modes

#### Agent  
1. **Command Listener:** Listen for and execute commands from the Master
2. **Metrics Collection:** Periodically send system metrics (CPU, RAM, load average) to Redis
3. **Self-Registration:** Automatically register with the Master and maintain active status
4. **File Operations:** Handle file/directory transfers (read/write) requested by Master
5. **Daemonization:** Run as a background service with proper process management
6. **Structured Logging:** Comprehensive logging system with different severity levels

## System Requirements

- **Operating System:** Linux-based (tested on Ubuntu)
- **Redis Server:** Running and accessible by both Master and Agents
- **Internet Connection:** Required for initial build (dependency installation)
- **Sudo Access:** Required for installing dependencies

All other dependencies (GCC, CMake, Redis++, etc.) will be automatically installed by the build script if missing.

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
# Build both master and agent with installer
./build.sh --redis-host your.redis.host --redis-pass your_password

# Build specific component
./build.sh --target agent --redis-host your.redis.host --redis-pass your_password
./build.sh --target master --redis-host your.redis.host --redis-pass your_password
```

**Arguments:**
- `--redis-host`: Redis server hostname (required)
- `--redis-pass`: Redis server password (required)
- `--target`: Component to build (optional)
  - Valid targets: all, agent, master (default: all)

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
scp monitor_installer user@remote:/tmp/
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
