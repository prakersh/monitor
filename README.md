# MONITOR
A distributed command execution and monitoring system with master-agent architecture

## Overview
MONITOR is a robust distributed system that enables centralized command execution and system monitoring across multiple machines. It uses a master-agent architecture where a central master application can control and monitor multiple agent nodes through Redis.

### Key Features
- **Distributed Command Execution**: Execute commands on remote agents from a central master
- **Real-time Monitoring**: Track system metrics (CPU, RAM, load) across all agents
- **Secure File Transfer**: Bidirectional file transfer between master and agents
- **Interactive Shell**: Remote shell access to agents via moni.sh
- **Automatic Recovery**: Self-healing agent processes with automatic reconnection
- **Structured Logging**: Comprehensive logging with rotation
#### Master  
1. **Command Execution:** Send commands to agents and receive their execution results (stdout, stderr, 
return code).  
2. **Agent Management:** List connected agents, register new agents, and manage their states.  
3. **File Transfer:** Send and receive files between master and agents.
4. **Enhanced Logging:** Structured logging with categories and automatic log rotation.
5. **Interactive CLI:** Multiple operation modes including:
   - Single command execution
   - Interactive shell (moni.sh)
   - File transfer operations
6. **Command Line Interface:** Support for both interactive and CLI modes.
#### Agent  
1. **Command Listener:** Listen for and execute commands from the Master.  
2. **Metrics Collection:** Periodically send system metrics (CPU, RAM, load average) to Redis.  
3. **Self-Registration:** Automatically register with the Master and maintain active status.  
4. **File Operations:** Handle file transfers (read/write) requested by Master.
5. **Daemonization:** Run as a background service with proper process management.
6. **Structured Logging:** Comprehensive logging system with different severity levels.

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
git clone https://github.com/yourusername/monitor.git
cd monitor
```

2. Build the project:
```bash
./build.sh --redis-host your.redis.host --redis-pass your_password
```

### Build Options
```bash
# Build both master and agent
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

### Build Process
1. **Dependency Check:**
   - Automatically verifies and installs required packages
   - Installs Redis++ if not present
   - Requires sudo access for package installation

2. **Compilation:**
   - Static linking for better portability
   - Injects Redis connection details at build time
   - Creates standalone executables

3. **Output:**
   - `agent`: Agent executable
   - `master`: Master executable

## Usage

### Starting Redis Server
Ensure Redis server is running and accessible by Master and Agents.

### Agent Application
```bash
# Start agent as daemon
./agent

# Stop existing agent
./agent -c
```

**Options:**
- `-c`: Kill existing agent process and exit
- No arguments: Start agent as daemon

### Master Application

#### Interactive Mode
Launch without arguments for interactive menu:
```bash
./master
```
#### Interactive Mode (no arguments)
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

# Transfer files
./master 4 hostname local_path remote_path  # Send file
./master 5 hostname remote_path local_path  # Receive file
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
- Format: `timestamp level message`

## File Transfer

The system supports bidirectional file transfers:

1. **Send File to Agent:**
```bash
./master 4 hostname local_path remote_path
```

2. **Receive File from Agent:**
```bash
./master 5 hostname remote_path local_path
```

## Process Management

### Agent Process Control
- Runs as a daemon process
- PID stored in `/tmp/agent.pid`
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
   - Verify file permissions
   - Check available disk space
   - Ensure paths are correct
   - Review logs for transfer errors

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