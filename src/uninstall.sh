#!/bin/bash

# Default installation path
INSTALL_PATH="/etc/monitor"

print_usage() {
    echo "Usage: $0 [-p install_path]"
    echo "  -p: Installation path (default: /etc/monitor)"
    exit 1
}

# Parse command line arguments
while getopts "p:" opt; do
    case $opt in
        p) INSTALL_PATH="$OPTARG" ;;
        *) print_usage ;;
    esac
done

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Please run as root"
    exit 1
fi

echo "Uninstalling Monitor..."

# Stop and disable service
echo "Stopping monitor service..."
systemctl stop monitor 2>/dev/null
systemctl disable monitor 2>/dev/null

# Remove service file
echo "Removing service file..."
rm -f /etc/systemd/system/monitor.service
systemctl daemon-reload

# Kill any running agent processes
if [ -f "/tmp/agent.pid" ]; then
    echo "Stopping agent process..."
    PID=$(cat /tmp/agent.pid)
    kill -9 "$PID" 2>/dev/null
    rm -f /tmp/agent.pid
fi

# Remove installation directory
if [ -d "$INSTALL_PATH" ]; then
    echo "Removing installation directory: $INSTALL_PATH"
    rm -rf "$INSTALL_PATH"
fi

# Clean up log files
echo "Cleaning up log files..."
rm -f /var/log/monitor.log
rm -f agent.log
rm -f master.log

echo "Monitor has been uninstalled successfully."
exit 0 