# MONITOR
# Agent-Master System: Distributed Command Execution and Monitoring  

This project provides a system for managing distributed agents from a central master application. The **Master** communicates with multiple **Agents** via Redis, sending commands and retrieving execution results while monitoring system metrics.  

## Features  

### Master  
1. **Command Execution:** Send commands to agents and receive their execution results (stdout, stderr, return code).  
2. **Agent Management:** List connected agents, register new agents, and manage their states.  
3. **Logging:** Maintain logs of all sent commands and their results in `master.log`.  
4. **Interactive CLI:** Execute commands interactively or via command-line arguments.  

### Agent  
1. **Command Listener:** Listen for commands from the Master and execute them.  
2. **Metrics Collection:** Periodically send system metrics (CPU, RAM, load average) to Redis.  
3. **Self-Registration:** Automatically register itself with the Master and maintain active status.  

## System Requirements  

- **Operating System:** Linux-based (tested on Ubuntu).  
- **Redis Server:** Running and accessible by both Master and Agents.  
- **Compiler:** GCC (g++), CMake.  
- **Libraries:**  
  - [Redis++](https://github.com/sewenew/redis-plus-plus)  
  - libuuid-dev  
  - libhiredis-dev  

## Installation  

### 1. Clone the Repository  
```bash  
git clone https://github.com/your-repo-url.git  
cd your-repo-directory  
```  

### 2. Build and Install Dependencies  
Run the provided `build.sh` script:  
```bash  
chmod +x build.sh  
./build.sh  
```  

This script:  
- Installs required packages and libraries.  
- Installs Redis++ if not already installed.  
- Compiles `master.cpp` and `agent.cpp`.  

## Usage  

### Starting Redis Server  
Ensure the Redis server is running and accessible by Master and Agents.  

### 1. Running the Master Application  
```bash  
./master  
```  
**Options:**  
1. **List Connected Agents**: Displays all registered agents.  
2. **Send Command to Agent**: Enter an agent's hostname and a command to execute.  
3. **Monitor Agent (moni.sh):** Send repeated commands interactively to an agent. Exit with `exit` or `quit`.  
4. **Exit:** Quit the application.  

You can also run the Master with command-line arguments:  
```bash  
./master <option> <hostname> <command>  
```  
- `option`: `1` to list agents, `2` to send a command.  
- `hostname`: Target agent's hostname.  
- `command`: Command to execute on the agent.  

### 2. Running the Agent Application  
```bash  
./agent  
```  
The agent will:  
1. Register itself with the Master.  
2. Collect system metrics every minute.  
3. Listen for commands from the Master.  

## Logs  
- **Master Logs:** Located in `master.log`, containing records of commands sent, results received, and other events.  

## Key Redis Keys  

- `run:<hostname>:<command>`: Tracks commands sent to agents.  
- `<uuid>`: Stores the command associated with a UUID.  
- `<uuid>:return_code`, `<uuid>:stdout`, `<uuid>:stderr`: Command execution results.  
- `agent:<hostname>:metrics`: Stores system metrics for each agent.  
- `<hostname>_agent_id`: Unique agent ID.  
- `<hostname>_user`: User running the agent.  
- `<hostname>_active`: Tracks agent activity status.  

## Example  

1. **Start Redis:**  
   ```bash  
   redis-server  
   ```  

2. **Start Agent:**  
   ```bash  
   ./agent  
   ```  

3. **Start Master and Send Command:**  
   ```bash  
   ./master  
   Enter choice: 2  
   Enter agent hostname: agent1  
   Enter command: uptime  
   ```  

4. **Monitor Logs:**  
   View `master.log` for detailed execution logs.  

## Troubleshooting  

- Ensure Redis is running and accessible.  
- Check network connectivity between Master and Agents.  
- Review `master.log` for error messages.  

## Future Improvements  

- Enhance security with encrypted communication.  
- Add multi-threading support for parallel command execution.  
- Provide a web interface for managing agents.  
- Demonisation of Agent
---  
**Author:** Prakersh Maheshwari  
**License:** MIT License  
