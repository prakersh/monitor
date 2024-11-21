#!/bin/bash

# Script to build agent.cpp and master.cpp and install dependencies if missing.

# Check if the user has sudo privileges
if [ "$EUID" -ne 0 ]; then
  ret=1
  #echo "Please run this script as root (e.g., using sudo)."
  #exit 1
fi

# Function to check if a package is installed
is_installed() {
  dpkg -l "$1" &> /dev/null
}

echo "Checking dependencies..."
ret=1
# Install build-essential for compiler tools
if ! is_installed build-essential; then
  echo "Installing build-essential..."
  sudo apt install -y build-essential
else
  ret=0
  #echo "build-essential is already installed."
fi

# Install CMake
if ! is_installed cmake; then
  echo "Installing cmake..."
  sudo apt install -y cmake
else
  ret=0
  #echo "cmake is already installed."
fi

# Install g++
if ! is_installed g++; then
  echo "Installing g++..."
  sudo apt install -y g++
else
  ret=0
  #echo "g++ is already installed."
fi

# Install libuuid-dev
if ! is_installed uuid-dev; then
  echo "Installing uuid-dev..."
  sudo apt install -y uuid-dev
else
  ret=0
  #echo "uuid-dev is already installed."
fi

# Install libhiredis-dev
if ! is_installed libhiredis-dev; then
  echo "Installing libhiredis-dev..."
  sudo apt install -y libhiredis-dev
else
  ret=0
  #echo "libhiredis-dev is already installed."
fi

# Install Redis++ if not already installed
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
else
  echo "Redis++ is already installed."
fi

# Check if Redis is running
# if ! pgrep -x "redis-server" > /dev/null; then
#   echo "Starting Redis server..."
#   sudo service redis-server start
# else
#   echo "Redis server is already running."
# fi

# Compile the agent and master programs
echo "Compiling agent.cpp and master.cpp..."

AGENT_SRC="agent.cpp"
MASTER_SRC="master.cpp"
AGENT_OUT="agent"
MASTER_OUT="master"

# Compile Agent with static linking
g++ -std=c++17 -I/usr/local/include -L/usr/local/lib "$AGENT_SRC" -o "$AGENT_OUT" -lredis++ -lhiredis -luuid -static
if [ $? -eq 0 ]; then
  echo "Successfully compiled $AGENT_SRC into $AGENT_OUT."
else
  echo "Failed to compile $AGENT_SRC."
  exit 1
fi

# Compile Master with static linking
g++ -std=c++17 -I/usr/local/include -L/usr/local/lib "$MASTER_SRC" -o "$MASTER_OUT" -lredis++ -lhiredis -luuid -static
if [ $? -eq 0 ]; then
  echo "Successfully compiled $MASTER_SRC into $MASTER_OUT."
else
  echo "Failed to compile $MASTER_SRC."
  exit 1
fi


echo "Build completed successfully. You can now run './agent' or './master'."
