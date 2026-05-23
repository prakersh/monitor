# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

MONITOR is a distributed command execution and monitoring system with a master-agent architecture. It uses Redis as a message broker to enable centralized control of remote agents.

### Architecture
- **Master**: Central control application (C++) - `src/master.cpp`
- **Agent**: Distributed execution node (C++) - `src/agent.cpp`
- **Redis**: Message broker and state management (required to be running)
- **Communication**: Master ↔ Redis ↔ Agent(s)

### Key Components

**Agent (`src/agent.cpp`):**
- Daemonizes itself and writes PID to `/tmp/agent.pid`
- Registers with master via Redis keys: `agents:<hostname>`, `<hostname>_agent_id`, `<hostname>_active`
- Listens for commands via `run:<hostname>:<command>` Redis keys
- Collects system metrics (RAM, load avg) every 60s → `agent:<hostname>:metrics`
- Handles file transfers via `file_transfer:<hostname>:<uuid>` Redis hashes
- Logs to `/var/log/moniagent.log` with 10MB rotation

**Master (`src/master.cpp`):**
- Connects to Redis and manages agents
- Interactive mode (no args) or CLI mode (with args)
- Logs to `/var/log/master.log` with categories: COMMAND, FILE, CONNECTION
- Supports 5 operations via CLI:
  1. List agents (option 1)
  2. Send command (option 2): `./master 2 <hostname> <command>`
  3. Interactive shell (option 3): `./master 3 <hostname>`
  4. Send file (option 4): `./master 4 <hostname> <local_path> <remote_path>`
  5. Receive file (option 5): `./master 5 <hostname> <remote_path> <local_path>`

**Installer (`src/monitor_inst.sh`):**
- Self-extracting shell script containing agent binary and systemd service file
- Extracts to `/etc/monitor` by default (customizable with `-p`)
- Installs systemd service `monitor.service`

## Build & Development

### Prerequisites
- Linux-based OS (Ubuntu tested)
- Redis server running
- Sudo access (for dependency installation)

### Build Commands
```bash
# Build everything (creates out/agent, out/master, out/monitor)
sudo ./build.sh --redis-host <host> --redis-pass <password>

# Build specific component
sudo ./build.sh --redis-host <host> --redis-pass <password> --target agent
sudo ./build.sh --redis-host <host> --redis-pass <password> --target master

# Build with specific version
sudo ./build.sh --redis-host <host> --redis-pass <password> --version 1.5.3
```

**Build process:**
1. Installs dependencies: `build-essential cmake g++ uuid-dev libhiredis-dev`
2. Clones and builds redis-plus-plus if not present
3. Compiles with g++ C++17, static linking
4. Injects Redis connection details at build time (replaces placeholders)
5. Creates installer by packaging agent + service file

### Running Tests
The CI workflow (`.github/workflows/ci.yml`) runs integration tests:
```bash
# Start Redis first
sudo systemctl start redis  # or docker run redis

# Start agent
sudo out/agent &

# Run tests
out/master 1  # List agents
echo "test" > test.txt
host=$(out/master 1 | grep Hostname | awk '{print $3}')
out/master 4 $host test.txt /tmp/test.txt  # Send file
out/master 2 $host "ls -l /tmp/test.txt"   # Execute command
out/master 5 $host /tmp/test.txt test2.txt # Receive file

# Stop agent
sudo out/agent -k
```

### Version Management
- Version stored in `.last_version` file
- Auto-incremented if not specified: `1.5.2` → `1.5.3`
- Check version with `-v` flag: `./agent -v`, `./master -v`

## Redis Key Schema

### Agent Registration & Status
- `agents:<hostname>` → hostname (presence indicates registration)
- `<hostname>_agent_id` → numeric ID
- `<hostname>_user` → current user
- `<hostname>_active` → "yes" (expires every 50s, refreshed every 20s)

### Command Execution
- `run:<hostname>:<command>` → UUID (triggers agent to execute)
- `<uuid>` → command string
- `<uuid>:return_code` → exit code
- `<uuid>:stdout` → command stdout
- `<uuid>:stderr` → command stderr

### Metrics
- `agent:<hostname>:metrics` → hash with `total_ram_mb`, `used_ram_mb`, `load_avg`

### File Transfer
- `file_transfer:<hostname>:<uuid>` → hash with:
  - `operation`: "read", "write", or "check_type"
  - `path`: target path
  - `content`: file/directory content (binary)
  - `is_directory`: "0" or "1"
  - `status`: "completed" or "error"
  - `error`: error message (if failed)

## File Transfer Implementation

**Directory handling:**
- Directories are tarred before transfer (agent and master both use `tar -cf` / `tar -xf`)
- Uses `fork()`/`execvp()` via `execute_tar_safely()` (no shell interpretation)
- Temp files created atomically via `mkstemp()`

**Flow:**
1. Master checks if path is directory via `check_type` operation
2. For send: Master tars directory → stores in Redis → agent extracts
3. For receive: Agent tars directory → stores in Redis → master extracts

## Common Development Tasks

### Modifying Redis Connection
Redis credentials are **injected at build time** via placeholders in source:
- `REDIS_HOST_PLACEHOLDER` → actual Redis host
- `REDIS_PASS_PLACEHOLDER` → actual Redis password
- `VERSION_PLACEHOLDER` → version string

**Important:** You must rebuild after changing Redis settings.

### Adding New Command
1. Add option handling in `master.cpp` `handle_cli_input()` or interactive menu
2. Agent automatically listens via `listen_for_commands()` loop
3. Command execution happens in `execute_command()` on agent

### Adding New Metric
1. Modify `collect_and_send_metrics()` in `agent.cpp`
2. Add to Redis hash `agent:<hostname>:metrics`
3. Master can read via `redis.hget()`

### Debugging
- **Agent logs:** `/var/log/moniagent.log`
- **Master logs:** `/var/log/master.log`
- **Redis keys:** Use `redis-cli` to inspect state
- **Process management:** PID file at `/tmp/agent.pid`

### Testing Locally
```bash
# Terminal 1: Start Redis
redis-server

# Terminal 2: Build and run agent
sudo ./build.sh --redis-host localhost --redis-pass "" --target agent
sudo out/agent

# Terminal 3: Run master
./build.sh --redis-host localhost --redis-pass "" --target master
out/master 1  # List agents
```

## CI/CD Pipeline

`.github/workflows/ci.yml` runs on push/PR to main:
1. Builds with Redis service container
2. Verifies binaries exist
3. Starts agent and tests:
   - Basic connectivity
   - File transfer (send/receive)
   - Command execution
   - Service installation via installer
4. Uploads artifacts

## Important Notes

- **Static linking:** Binaries are statically linked for portability
- **Daemonization:** Agent uses double-fork to daemonize
- **Log rotation:** Both agent and master rotate at 10MB
- **Command execution:** Uses `fork()`/`execvp()` with separate stdout/stderr pipes
- **cd command:** Special handling in `execute_command()` - changes agent's working directory
- **UUID generation:** Uses libuuid (`uuid_generate()`)
- **Tar operations:** Uses `fork()`/`execvp()` to run `tar` (requires tar installed)
