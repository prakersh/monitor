# MONITOR
# Agent-Master System: Distributed Command Execution and Monitoring  

This project provides a system for managing distributed agents from a central master application. The **Master** communicates with multiple **Agents** via Redis, sending commands and retrieving execution results while monitoring system metrics.  

## Features  

### Master  
1. **Command Execution:** Send commands to agents and receive their execution results (stdout, stderr, return code).  
2. **Agent Management:** List connected agents, register new agents, and manage their states.  
3. **File Transfer:** Send and receive files between master and agents.
4. **Enhanced Logging:** Structured logging with categories and automatic log rotation.
5. **Interactive CLI:** Multiple operation modes including:
   - Single command execution
   - Interactive shell (moni.sh)
   - File transfer operations
6. **Command Line Interface:** Support for both interactive and CLI modes.

### Agent  
1. **Command Listener:** Listen for and execute commands from the Master.  
2. **Metrics Collection:** Periodically send system metrics (CPU, RAM, load average) to Redis.  
3. **Self-Registration:** Automatically register with the Master and maintain active status.  
4. **File Operations:** Handle file transfers (read/write) requested by Master.
5. **Daemonization:** Run as a background service with proper process management.
6. **Structured Logging:** Comprehensive logging system with different severity levels.

## System Requirements  

- **Operating System:** Linux-based (tested on Ubuntu).  
- **Redis Server:** Running and accessible by both Master and Agents.  
- **Compiler:** GCC (g++), CMake.  
- **Libraries:**  
  - [Redis++](https://github.com/sewenew/redis-plus-plus)  
  - libuuid-dev  
  - libhiredis-dev  

## Usage  

### Starting Redis Server  
Ensure Redis server is running and accessible by Master and Agents.  

### Running the Agent  
```bash  
./agent [-c]
```
**Options:**
- `-c`: Kill existing agent process and exit
- No arguments: Start agent as daemon

### Running the Master  
```bash  
./master [option] [arguments...]
```
**Interactive Mode (no arguments):**
1. List connected agents
2. Send command to agent
3. Interactive shell (moni.sh)
4. Send file to agent
5. Receive file from agent
6. Exit

**Command Line Mode:**
```bash
./master 1                                     # List agents
./master 2 <hostname> <command>                # Execute command
./master 3 <hostname>                          # Interactive shell
./master 4 <hostname> <local> <remote>         # Send file
./master 5 <hostname> <remote> <local>         # Receive file
```

## Logging

Both Master and Agent maintain structured logs:

### Master Logs
- Location: `master.log`
- Categories: COMMAND, FILE, CONNECTION
- Auto-rotation at 10MB
- Format: `timestamp level [category] message`

### Agent Logs
- Location: `agent.log`
- Levels: INFO, ERROR, DEBUG
- Format: `timestamp level message`

## File Transfer

The system now supports bidirectional file transfers:

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

## Key Redis Keys  

- `run:<hostname>:<command>`: Command tracking
- `<uuid>`: Command storage
- `<uuid>:return_code`, `<uuid>:stdout`, `<uuid>:stderr`: Command results
- `agent:<hostname>:metrics`: System metrics
- `<hostname>_agent_id`: Agent identification
- `file_transfer:<hostname>:*`: File transfer operations

## Troubleshooting  

1. **Agent Connection Issues:**
   - Check Redis connectivity
   - Verify agent process is running (`ps aux | grep agent`)
   - Review agent.log for errors

2. **File Transfer Problems:**
   - Verify file permissions
   - Check available disk space
   - Review logs for transfer status

3. **Command Execution Failures:**
   - Verify agent is active
   - Check command syntax
   - Review master.log for execution details

---  
**Author:** Prakersh Maheshwari
**Email:** Prakersh@live.com  
**License:** MIT License  
