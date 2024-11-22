#!/bin/bash

INSTALL_PATH="/etc/monitor"
EXTRACT_ONLY=false

print_usage() {
    echo "Usage: $0 [-p install_path] [-e]"
    echo "  -p: Installation path (default: /etc/monitor)"
    echo "  -e: Extract only, don't install"
    exit 1
}

while getopts "p:e" opt; do
    case $opt in
        p) INSTALL_PATH="$OPTARG" ;;
        e) EXTRACT_ONLY=true ;;
        *) print_usage ;;
    esac
done

# Create temporary directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Extract payload to temporary directory
PAYLOAD_START=$(awk '/^__PAYLOAD_FOLLOWS__/ { print NR + 1; exit 0; }' "$0")
if [ -z "$PAYLOAD_START" ]; then
    echo "Error: Payload marker not found"
    exit 1
fi

tail -n+"$PAYLOAD_START" "$0" | base64 -d > "$TEMP_DIR/payload.tar.gz"
if [ ! -f "$TEMP_DIR/payload.tar.gz" ]; then
    echo "Error: Failed to extract payload"
    exit 1
fi

# Create installation directory
mkdir -p "$INSTALL_PATH"

# Extract files
cd "$TEMP_DIR" || exit 1
tar xzf payload.tar.gz
if [ $? -ne 0 ]; then
    echo "Error: Failed to extract tar archive"
    exit 1
fi

# Copy files to installation directory
cp agent monitor.service "$INSTALL_PATH/"

if [ "$EXTRACT_ONLY" = true ]; then
    echo "Files extracted to $INSTALL_PATH"
    exit 0
fi

# Install service file
cp "$INSTALL_PATH/monitor.service" /etc/systemd/system/
sed -i "s|/etc/monitor|$INSTALL_PATH|g" /etc/systemd/system/monitor.service

# Set permissions
chmod +x "$INSTALL_PATH/agent"
systemctl daemon-reload
systemctl enable monitor
systemctl start monitor

echo "Installation complete. Agent installed at $INSTALL_PATH"
exit 0
