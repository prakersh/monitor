#!/bin/bash

# Function to check dependencies
check_dependencies() {
    echo "Checking dependencies..."
    
    # List of required packages
    local packages=("build-essential" "cmake" "g++" "uuid-dev" "libhiredis-dev")
    local missing_packages=()

    # Function to check if a package is installed
    is_installed() {
        dpkg -l "$1" &> /dev/null
    }

    # Check each package
    for package in "${packages[@]}"; do
        if ! is_installed "$package"; then
            missing_packages+=("$package")
            echo "Missing package: $package"
        fi
    done

    # Install missing packages if any
    if [ ${#missing_packages[@]} -ne 0 ]; then
        echo "Installing missing packages..."
        sudo apt install -y "${missing_packages[@]}"
    fi

    # Check and install Redis++ if needed
    REDIS_PLUS_PLUS_DIR="/usr/local/include/sw/redis++"
    if [ ! -d "$REDIS_PLUS_PLUS_DIR" ]; then
        echo "Redis++ not found. Installing Redis++..."
        git clone https://github.com/sewenew/redis-plus-plus.git
        cd redis-plus-plus || exit
        mkdir -p build && cd build || exit
        cmake .. -DCMAKE_BUILD_TYPE=Release -DREDIS_PLUS_PLUS_BUILD_SHARED=ON
        make -j$(nproc)
        sudo make install
        cd ../.. || exit
        rm -rf redis-plus-plus
    fi
}

# Function to compile a specific program
compile_program() {
    local src=$1
    local out=$2
    local redis_host=$3
    local redis_pass=$4

    echo "Compiling $src..."
    
    # Create a temporary file with modified source
    local temp_src="temp_${src}"
    cp "$src" "$temp_src"
    
    # Replace Redis connection placeholders with build-time parameters
    if [ -n "$redis_host" ]; then
        sed -i "s|REDIS_HOST_PLACEHOLDER|${redis_host}|g" "$temp_src"
        sed -i "s|REDIS_PASS_PLACEHOLDER|${redis_pass}|g" "$temp_src"
    else
        echo "Error: Redis host and password are required"
        exit 1
    fi
    # Compile with static linking
    g++ -std=c++17 -I/usr/local/include -L/usr/local/lib "$temp_src" -o "$out" -lredis++ -lhiredis -luuid -static
    local result=$?
    
    # Clean up temporary file
    rm "$temp_src"
    
    if [ $result -eq 0 ]; then
        echo "Successfully compiled $src into $out."
        return 0
    else
        echo "Failed to compile $src."
        return 1
    fi
}

# Add this function at the end of the existing build.sh
create_installer() {
    local temp_dir=$(mktemp -d)
    local installer="monitor_installer"
    
    echo "Creating installer package..."
    
    # Ensure files exist before copying
  if [ ! -f "agent" ] || [ ! -f "monitor.service" ]; then
      echo "Error: Required files not found"
      echo "Please ensure 'agent' and 'monitor.service' exist in current directory"
      rm -rf "$temp_dir"
      exit 1
  fi
    
    # Copy files to temp directory
    cp agent monitor.service "$temp_dir/"
    
    # Create tar archive
    cd "$temp_dir" || exit 1
    tar czf payload.tar.gz agent monitor.service
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create tar archive"
        cd - || exit 1
        rm -rf "$temp_dir"
        exit 1
    fi
    cd - || exit 1
    
    # Verify tar file was created
    if [ ! -f "$temp_dir/payload.tar.gz" ]; then
        echo "Error: Tar file not created"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Create self-extracting installer
    cp monitor_inst.sh "$installer"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to copy installer script"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Append payload marker and base64 encoded content
    echo "" >> "$installer"
    echo "__PAYLOAD_FOLLOWS__" >> "$installer"
    base64 "$temp_dir/payload.tar.gz" >> "$installer"
    
    chmod +x "$installer"
    rm -rf "$temp_dir"
    
    echo "Created self-extracting installer: $installer"
}

# Parse command line arguments
REDIS_HOST="prakersh.in"
REDIS_PASS="Jmnwgh87nOCVOWc6RYuQbNa/5DmDon3uQEjVAHbJ2Vj5xNeSvw4urxydZxeeEbkP4YCrGPb3OiYknuvk"
BUILD_TARGET="all"

while [[ $# -gt 0 ]]; do
    case $1 in
        --redis-host)
            REDIS_HOST="$2"
            shift 2
            ;;
        --redis-pass)
            REDIS_PASS="$2"
            shift 2
            ;;
        --target)
            BUILD_TARGET="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check dependencies first
check_dependencies

# Compile based on target
case $BUILD_TARGET in
    "all")
        compile_program "agent.cpp" "agent" "$REDIS_HOST" "$REDIS_PASS" || exit 1
        compile_program "master.cpp" "master" "$REDIS_HOST" "$REDIS_PASS" || exit 1
        
        # Create monitor.service file
        cat > monitor.service << 'EOL'
[Unit]
Description=Remote System Management Agent
After=network.target
Wants=network.target

[Service]
Type=forking
ExecStart=/etc/monitor/agent
ExecStop=/etc/monitor/agent -k
PIDFile=/tmp/agent.pid
Restart=always
RestartSec=5
StartLimitInterval=0
StartLimitBurst=100
KillMode=process
TimeoutStopSec=10
User=root

[Install]
WantedBy=multi-user.target
EOL
        
        create_installer
        ;;
    "agent")
        compile_program "agent.cpp" "agent" "$REDIS_HOST" "$REDIS_PASS" || exit 1
        ;;
    "master")
        compile_program "master.cpp" "master" "$REDIS_HOST" "$REDIS_PASS" || exit 1
        ;;
    *)
        echo "Invalid target: $BUILD_TARGET"
        echo "Valid targets are: all, agent, master"
        exit 1
        ;;
esac

echo "Build completed successfully."