# MONITOR

[![CI](https://github.com/prakersh/monitor/actions/workflows/ci.yml/badge.svg)](https://github.com/prakersh/monitor/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.5.9-blue.svg)](.last_version)

A distributed command execution and monitoring system with master-agent architecture, built in C++ using Redis as a message broker.

## Architecture

```
┌─────────────┐         ┌─────────────┐
│   Master    │◄───────►│   Redis     │
│  (C++)      │         │  (Broker)   │
└─────────────┘         └─────────────┘
                              │
                         ┌────┴────┐
                         │         │
                    ┌────▼──┐  ┌───▼────┐
                    │ Agent │  │ Agent  │
                    │ (C++) │  │ (C++)  │
                    └───────┘  └────────┘
```

- **Master** — central control application for managing agents
- **Agent** — daemon running on each monitored node
- **Redis** — message broker and state store between master and agents

## Features

- **Distributed Command Execution** — run commands on remote agents with full stdout/stderr/exit code capture
- **Bidirectional File Transfer** — send and receive files and directories between master and agents
- **System Metrics** — automatic collection of RAM, CPU, and load average every 60 seconds
- **Interactive Shell** — remote shell access to agents via `moni.sh`
- **Self-Extracting Installer** — single-binary deployment for agents with systemd integration
- **Static Binaries** — portable, statically linked executables
- **Structured Logging** — categorized logs with automatic 10MB rotation

## Quick Start

### Prerequisites

- Linux (Ubuntu 20.04+ recommended)
- Redis server
- Sudo access

### Build

```bash
git clone https://github.com/prakersh/monitor.git
cd monitor

sudo ./build.sh --redis-host localhost --redis-pass ""
```

This produces four artifacts in `out/`:

| File | Purpose |
|------|---------|
| `master` | Master control application |
| `agent` | Agent daemon |
| `monitor` | Self-extracting agent installer |
| `monitor.service` | Systemd service file |

### Build Options

```bash
# Specific version
sudo ./build.sh --redis-host <host> --redis-pass <pass> --version 1.5.10

# Single target
sudo ./build.sh --redis-host <host> --redis-pass <pass> --target agent
sudo ./build.sh --redis-host <host> --redis-pass <pass> --target master
```

### Run

```bash
# Terminal 1 — start agent
sudo out/agent

# Terminal 2 — use master
out/master 1                              # list agents
out/master 2 <hostname> "df -h"           # run command
out/master 3 <hostname>                   # interactive shell
out/master 4 <hostname> local.txt /tmp/   # send file
out/master 5 <hostname> /tmp/f.txt ./     # receive file
```

## Usage

### Agent

```bash
sudo ./agent          # start as daemon
sudo ./agent -k       # stop
./agent -v            # version
```

The agent daemonizes, writes its PID to `/tmp/agent.pid`, registers with Redis, and begins listening for commands and collecting metrics.

### Master

**Interactive mode** (no arguments):

```bash
./master
```

Presents a menu: list agents, send command, interactive shell, send file, receive file.

**CLI mode**:

```bash
./master 1                                    # list agents
./master 2 <hostname> "<command>"             # execute command
./master 3 <hostname>                         # interactive shell
./master 4 <hostname> <local> <remote>        # send file/dir
./master 5 <hostname> <remote> <local>        # receive file/dir
./master -v                                   # version
```

### Agent Deployment

Copy the self-extracting installer to the target machine:

```bash
scp out/monitor user@remote:/tmp/
ssh user@remote "sudo /tmp/monitor"           # install to /etc/monitor
```

Options:
- `-p <path>` — custom install path (default `/etc/monitor`)
- `-e` — extract only, skip systemd setup
- `-v` — version

After installation the agent runs as the `monitor` systemd service:

```bash
sudo systemctl status monitor
sudo systemctl restart monitor
```

## Testing

### CI Pipeline

The GitHub Actions workflow (`.github/workflows/ci.yml`) runs on every push and PR to `main`:

1. Builds all components with a Redis service container
2. Verifies binaries exist
3. Starts agent and tests connectivity, command execution, and file transfer
4. Tests the self-extracting installer and systemd service
5. Uploads build artifacts

### Local Test Suite

A comprehensive test suite with 350+ cases lives in `tests/`:

```bash
cd tests
./run_tests.sh --quick       # smoke tests
./run_tests.sh --all         # full suite
./run_tests.sh --command     # specific category
```

Categories: `--build`, `--agent`, `--master`, `--command`, `--file`, `--metrics`, `--process`, `--redis`, `--logging`, `--concurrent`, `--stress`, `--security`, `--recovery`, `--installer`, `--version`.

See [tests/README.md](tests/README.md) for details.

## Project Structure

```
monitor/
├── src/
│   ├── agent.cpp            # Agent daemon
│   ├── master.cpp           # Master control app
│   ├── monitor_inst.sh      # Self-extracting installer script
│   └── uninstall.sh         # Uninstaller
├── tests/                   # Test suite (350+ cases)
├── build.sh                 # Build script
├── .github/workflows/
│   ├── ci.yml               # CI/CD pipeline
│   └── pr.yml               # PR checks (cppcheck, clang-format)
├── CLAUDE.md                # Developer documentation
└── LICENSE                  # GPL-3.0
```

## Troubleshooting

**Agent won't connect**
```bash
sudo systemctl status redis          # Redis running?
ps aux | grep agent                  # agent process alive?
cat /var/log/moniagent.log           # agent logs
redis-cli ping                       # Redis reachable?
```

**Command execution fails**
```bash
out/master 1                         # agent listed?
out/master 2 <host> "echo test"      # simple command works?
cat master.log                       # master-side errors
```

**File transfer fails** — check disk space (`df -h`), permissions, and `grep FILE master.log`.

**Process issues** — check PID file (`cat /tmp/agent.pid`), kill stale agent (`sudo out/agent -k`).

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/name`)
3. Follow existing code style and add tests for new functionality
4. Use conventional commit messages (`feat:`, `fix:`, etc.)
5. Open a Pull Request

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).

## Author

**Prakersh Maheshwari**
- GitHub: [@prakersh](https://github.com/prakersh)
- LinkedIn: [Prakersh Maheshwari](https://www.linkedin.com/in/prakersh/)
- Email: Prakersh@live.com
