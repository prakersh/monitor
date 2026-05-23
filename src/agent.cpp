#include <sw/redis++/redis++.h>
#include <iostream>
#include <thread>
#include <chrono>
#include <sys/utsname.h>
#include <cstdlib>
#include <cstdio>
#include <sstream>
#include <sys/sysinfo.h>
#include <fstream>
#include <unistd.h>
#include <ctime>
#include <iomanip>
#include <fcntl.h>
#include <sys/stat.h>
#include <signal.h>
#include <limits.h>
#include <filesystem>
#include <uuid/uuid.h>
#include <sys/wait.h>
#include <vector>
#include <cstring>
#include <atomic>
#include <mutex>
namespace fs = std::filesystem;
// Thread-safe singleton Logger using Meyers' pattern
class Logger {
private:
    std::ofstream log_file;
    std::string log_path;
    static constexpr size_t MAX_SIZE = 10 * 1024 * 1024; // 10MB in bytes
    std::mutex log_mutex;
    
    Logger() {
        log_path = "/var/log/moniagent.log";
        log_file.open(log_path, std::ios::app);
    }

    void rotate_log() {
        if (log_file.is_open()) {
            log_file.close();
        }

        struct stat stat_buf;
        if (stat(log_path.c_str(), &stat_buf) == 0) {
            if (static_cast<size_t>(stat_buf.st_size) >= MAX_SIZE) {
                std::string backup_path = log_path + ".1";
                rename(log_path.c_str(), backup_path.c_str());
            }
        }

        log_file.open(log_path, std::ios::app);
    }

public:
    static Logger& getInstance() {
        static Logger instance;
        return instance;
    }

    std::string getCurrentTimestamp() {
        auto now = std::chrono::system_clock::now();
        auto now_c = std::chrono::system_clock::to_time_t(now);
        std::stringstream ss;
        ss << std::put_time(std::localtime(&now_c), "%Y-%m-%d %H:%M:%S");
        return ss.str();
    }

    void log(const std::string& level, const std::string& message) {
        std::lock_guard<std::mutex> lock(log_mutex);
        if (log_file.is_open()) {
            struct stat stat_buf;
            if (stat(log_path.c_str(), &stat_buf) == 0) {
                if (static_cast<size_t>(stat_buf.st_size) >= MAX_SIZE) {
                    rotate_log();
                }
            }

            log_file << getCurrentTimestamp() << "\t" << level << "\t" 
                    << message << std::endl;
            log_file.flush();
        }
    }

    void info(const std::string& message) {
        log("INFO", message);
    }

    void error(const std::string& message) {
        log("ERROR", message);
    }

    void debug(const std::string& message) {
        log("DEBUG", message);
    }

    ~Logger() {
        if (log_file.is_open()) {
            log_file.close();
        }
    }
    
    // Delete copy constructor and assignment operator
    Logger(const Logger&) = delete;
    Logger& operator=(const Logger&) = delete;
};

using namespace sw::redis;

// Atomic flag for signal handling (async-signal-safe)
std::atomic<bool> shutdown_requested{false};

// Generate a unique UUID
std::string generate_uuid() {
    uuid_t uuid;
    char uuid_str[37];
    uuid_generate(uuid);
    uuid_unparse(uuid, uuid_str);
    return std::string(uuid_str);
}

// Validate command to prevent shell injection
bool is_command_safe(const std::string& cmd) {
    // List of dangerous characters and sequences
    const std::vector<std::string> dangerous = {
        ";", "&&", "||", "|", "`", "$", "<", ">", 
        "$(", "${", "\n", "\r"
    };
    
    for (const auto& pattern : dangerous) {
        if (cmd.find(pattern) != std::string::npos) {
            return false;
        }
    }
    return true;
}

// Retrieve the hostname of the machine
std::string get_hostname() {
    struct utsname uts;
    if (uname(&uts) == 0) {
        return std::string(uts.nodename);
    }
    return "unknown";
}
// Validate path to prevent directory traversal attacks
bool is_path_traversal_safe(const std::string& path) {
    // Check for common traversal patterns
    if (path.find("..") != std::string::npos) {
        return false;
    }
    
    // Check for null bytes
    if (path.find('\0') != std::string::npos) {
        return false;
    }
    
    // Additional check: path should not start with / to prevent absolute paths
    // unless explicitly allowed (we'll be more restrictive here)
    if (path.empty()) {
        return false;
    }
    
    return true;
}

// Execute tar command safely using fork+execvp
int execute_tar_safely(const std::vector<std::string>& args) {
    pid_t pid = fork();
    if (pid == -1) {
        return -1;
    }
    
    if (pid == 0) {
        // Child process
        // Convert vector<string> to char* array
        std::vector<char*> argv;
        for (const auto& arg : args) {
            argv.push_back(const_cast<char*>(arg.c_str()));
        }
        argv.push_back(nullptr);
        
        // Execute tar
        execvp("tar", argv.data());
        
        // If execvp returns, it failed
        _exit(127);
    }
    
    // Parent process
    int status;
    if (waitpid(pid, &status, 0) == -1) {
        return -1;
    }
    
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    
    return -1;
}

// Helper function to create a tar archive of a folder
std::string create_tar_archive(const std::string& folder_path) {
    // Validate input path
    if (!is_path_traversal_safe(folder_path)) {
        throw std::runtime_error("Invalid folder path: potential directory traversal detected");
    }
    
    // Create secure temp file using mkstemp
    std::string temp_template = "/tmp/agent_tar_XXXXXX";
    std::vector<char> temp_buffer(temp_template.begin(), temp_template.end());
    temp_buffer.push_back('\0');
    
    int fd = mkstemp(temp_buffer.data());
    if (fd == -1) {
        throw std::runtime_error("Failed to create temporary file");
    }
    
    std::string temp_tar(temp_buffer.data());
    close(fd);
    
    // Add .tar extension
    std::string temp_tar_final = temp_tar + ".tar";
    if (rename(temp_tar.c_str(), temp_tar_final.c_str()) != 0) {
        std::remove(temp_tar.c_str());
        throw std::runtime_error("Failed to rename temporary file");
    }
    temp_tar = temp_tar_final;
    
    try {
        fs::path folder_fs_path(folder_path);
        std::string parent_dir = folder_fs_path.parent_path().string();
        std::string folder_name = folder_fs_path.filename().string();
        
        if (parent_dir.empty()) {
            parent_dir = ".";
        }
        
        // Build tar command arguments
        std::vector<std::string> tar_args = {
            "tar", "-cf", temp_tar, "-C", parent_dir, folder_name
        };
        
        int result = execute_tar_safely(tar_args);
        if (result != 0) {
            std::remove(temp_tar.c_str());
            throw std::runtime_error("Failed to create tar archive, exit code: " + std::to_string(result));
        }
        
        // Read the tar file into memory
        std::ifstream tar_file(temp_tar, std::ios::binary);
        if (!tar_file.is_open()) {
            std::remove(temp_tar.c_str());
            throw std::runtime_error("Failed to read tar archive");
        }
        
        std::stringstream buffer;
        buffer << tar_file.rdbuf();
        tar_file.close();
        
        // Clean up temporary tar file
        std::remove(temp_tar.c_str());
        
        return buffer.str();
    } catch (...) {
        // Ensure cleanup on any exception
        std::remove(temp_tar.c_str());
        throw;
    }
}

void extract_tar_archive(const std::string& tar_content, const std::string& dest_path) {
    // Validate destination path
    if (!is_path_traversal_safe(dest_path)) {
        throw std::runtime_error("Invalid destination path: potential directory traversal detected");
    }
    
    // Create secure temp file for tar content
    std::string temp_template = "/tmp/agent_tar_XXXXXX";
    std::vector<char> temp_buffer(temp_template.begin(), temp_template.end());
    temp_buffer.push_back('\0');
    
    int fd = mkstemp(temp_buffer.data());
    if (fd == -1) {
        throw std::runtime_error("Failed to create temporary file for extraction");
    }

    std::string temp_tar(temp_buffer.data());

    try {
        // Write tar content to temp file
        ssize_t written = write(fd, tar_content.data(), tar_content.size());
        close(fd);
        fd = -1;

        if (written != static_cast<ssize_t>(tar_content.size())) {
            std::remove(temp_tar.c_str());
            throw std::runtime_error("Failed to write tar content to temporary file");
        }

        // Get parent directory of destination path
        fs::path dest_fs_path(dest_path);
        std::string parent_dir = dest_fs_path.parent_path().string();
        if (parent_dir.empty()) {
            parent_dir = ".";
        }

        // Create parent directory
        fs::create_directories(parent_dir);

        // Build tar command arguments for extraction
        std::vector<std::string> tar_args = {
            "tar", "-xf", temp_tar, "-C", parent_dir
        };

        int result = execute_tar_safely(tar_args);

        // Clean up temporary tar file
        std::remove(temp_tar.c_str());

        if (result != 0) {
            throw std::runtime_error("Failed to extract tar archive, exit code: " + std::to_string(result));
        }
    } catch (...) {
        if (fd != -1) close(fd);
        std::remove(temp_tar.c_str());
        throw;
    }
}


// Execute a command safely using execve (no shell, prevents injection)
void execute_command(const std::string &cmd, int &return_code, std::string &stdout_data, std::string &stderr_data) {
    auto& logger = Logger::getInstance();
    logger.debug("Executing command: " + cmd);
    
    // Validate command for safety
    if (!is_command_safe(cmd)) {
        stderr_data = "Command rejected: contains potentially dangerous characters";
        return_code = -1;
        logger.error("Command rejected for security: " + cmd);
        return;
    }
    
    // Special handling for cd command - check for "cd " or exact "cd"
    if (cmd == "cd" || (cmd.length() > 2 && cmd.substr(0, 3) == "cd ")) {
        std::string dir;
        if (cmd.length() > 3) {
            dir = cmd.substr(3);
        } else {
            const char* home = getenv("HOME");
            if (!home) {
                stderr_data = "Failed to change directory: HOME environment variable not set";
                return_code = -1;
                logger.error(stderr_data);
                return;
            }
            dir = home;
        }
        return_code = chdir(dir.c_str());
        if (return_code != 0) {
            stderr_data = "Failed to change directory to " + dir;
            logger.error(stderr_data);
        } else {
            char cwd[PATH_MAX];
            if (getcwd(cwd, sizeof(cwd)) != NULL) {
                stdout_data = "Changed directory to: " + std::string(cwd);
                logger.info(stdout_data);
            }
        }
        return;
    }
    
    // Create pipes for stdout and stderr
    int stdout_pipe[2];
    int stderr_pipe[2];
    
    if (pipe(stdout_pipe) == -1 || pipe(stderr_pipe) == -1) {
        stderr_data = "Failed to create pipes";
        return_code = -1;
        logger.error("Failed to create pipes for command: " + cmd);
        return;
    }
    
    // Fork to execute command
    pid_t pid = fork();
    if (pid == -1) {
        close(stdout_pipe[0]);
        close(stdout_pipe[1]);
        close(stderr_pipe[0]);
        close(stderr_pipe[1]);
        stderr_data = "Failed to fork";
        return_code = -1;
        logger.error("Failed to fork for command: " + cmd);
        return;
    }
    
    if (pid == 0) {
        // Child process
        close(stdout_pipe[0]);
        close(stderr_pipe[0]);
        dup2(stdout_pipe[1], STDOUT_FILENO);
        dup2(stderr_pipe[1], STDERR_FILENO);
        close(stdout_pipe[1]);
        close(stderr_pipe[1]);
        
        // Parse command into arguments
        std::vector<char*> args;
        std::string cmd_copy = cmd;
        char* token = strtok(&cmd_copy[0], " ");
        while (token != nullptr) {
            args.push_back(token);
            token = strtok(nullptr, " ");
        }
        args.push_back(nullptr);
        
        // Execute command directly (no shell)
        execvp(args[0], args.data());
        
        // If execvp returns, it failed
        perror("execvp failed");
        _exit(127);
    }
    
    // Parent process
    close(stdout_pipe[1]);
    close(stderr_pipe[1]);
    
    // Read output with larger buffer
    char buffer[4096];
    ssize_t n;
    
    // Read stdout
    while ((n = read(stdout_pipe[0], buffer, sizeof(buffer) - 1)) > 0) {
        buffer[n] = '\0';
        stdout_data += buffer;
    }
    close(stdout_pipe[0]);
    
    // Read stderr
    while ((n = read(stderr_pipe[0], buffer, sizeof(buffer) - 1)) > 0) {
        buffer[n] = '\0';
        stderr_data += buffer;
    }
    close(stderr_pipe[0]);
    
    // Wait for child and get exit code
    int status;
    waitpid(pid, &status, 0);
    
    if (WIFEXITED(status)) {
        return_code = WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
        return_code = 128 + WTERMSIG(status);
        stderr_data += "\n[Process terminated by signal " + std::to_string(WTERMSIG(status)) + "]";
    } else {
        return_code = status;
    }
    
    logger.debug("Command executed. Return code: " + std::to_string(return_code));
}

// Collect comprehensive system metrics and send to Redis
void collect_and_send_metrics(Redis &redis, const std::string &hostname) {
    auto& logger = Logger::getInstance();
    logger.info("Starting metrics collection for host: " + hostname);
    
    while (true) {
        try {
            struct sysinfo info;
            if (sysinfo(&info) == 0) {
                logger.debug("Collecting system metrics");
                
                long total_ram = info.totalram / (1024 * 1024);
                long free_ram = info.freeram / (1024 * 1024);
                long used_ram = total_ram - free_ram;
                double load_avg = info.loads[0] / 65536.0;
                
                std::string metrics_info = "RAM Total: " + std::to_string(total_ram) + 
                                         "MB, Used: " + std::to_string(used_ram) + 
                                         "MB, Load Avg: " + std::to_string(load_avg);
                logger.debug("Metrics collected: " + metrics_info);
                
                std::string key = "agent:" + hostname + ":metrics";
                redis.hset(key, "total_ram_mb", std::to_string(total_ram));
                redis.hset(key, "used_ram_mb", std::to_string(used_ram));
                redis.hset(key, "load_avg", std::to_string(load_avg));
                
                logger.info("Metrics updated in Redis for " + hostname);
            } else {
                logger.error("Failed to get system info for " + hostname);
            }
        } catch (const std::exception& e) {
            logger.error("Error in metrics collection: " + std::string(e.what()));
        }
        
        // Check for shutdown request
        if (shutdown_requested.load()) {
            logger.info("Metrics collection shutting down");
            break;
        }
        
        std::this_thread::sleep_for(std::chrono::seconds(60));
    }
}
// Listen for commands and execute those targeting this agent
void listen_for_commands(Redis &redis, const std::string &hostname) {
    auto& logger = Logger::getInstance();
    std::string command_prefix = "run:" + hostname + ":";
    logger.info("Started command listener for host: " + hostname);
    
    while (true) {
        try {
            std::vector<std::string> keys;
            redis.keys(command_prefix + "*", std::back_inserter(keys));
            
            for (const auto &key : keys) {
                auto uuid = redis.get(key);
                if (uuid) {
                    auto command = redis.get(*uuid);
                    logger.info("Received command: " + *command + " (UUID: " + *uuid + ")");
                    
                    int return_code;
                    std::string stdout_data, stderr_data;
                    execute_command(*command, return_code, stdout_data, stderr_data);
                    
                    std::string base_key = *uuid + ":";
                    redis.set(base_key + "return_code", std::to_string(return_code));
                    redis.set(base_key + "stdout", stdout_data);
                    redis.set(base_key + "stderr", stderr_data);
                    
                    redis.del(key);
                    logger.info("Command executed and response sent. Return code: " + 
                               std::to_string(return_code));
                }
            }
        } catch (const std::exception& e) {
            logger.error("Error in command listener: " + std::string(e.what()));
        }
        
        // Check for shutdown request
        if (shutdown_requested.load()) {
            logger.info("Command listener shutting down");
            break;
        }
        
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }
}

// Function to run the "whoami" command and get the current user
std::string get_user_from_whoami() {
    std::array<char, 128> buffer;
    std::string user;
    
    // Use safer approach with execvp instead of popen
    int pipefd[2];
    if (pipe(pipefd) == -1) {
        throw std::runtime_error("pipe() failed!");
    }
    
    pid_t pid = fork();
    if (pid == -1) {
        close(pipefd[0]);
        close(pipefd[1]);
        throw std::runtime_error("fork() failed!");
    }
    
    if (pid == 0) {
        // Child process
        close(pipefd[0]);
        dup2(pipefd[1], STDOUT_FILENO);
        close(pipefd[1]);
        
        char* args[] = {(char*)"whoami", nullptr};
        execvp("whoami", args);
        _exit(1);  // execvp failed
    }
    
    // Parent process
    close(pipefd[1]);
    
    ssize_t n;
    while ((n = read(pipefd[0], buffer.data(), buffer.size() - 1)) > 0) {
        buffer[n] = '\0';
        user += buffer.data();
    }
    close(pipefd[0]);
    
    int status;
    waitpid(pid, &status, 0);
    
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        throw std::runtime_error("whoami command failed");
    }
    
    // Remove the newline character from the user string if present
    if (!user.empty() && user.back() == '\n') {
        user.pop_back();
    }
    return user;
}

// Register the agent with the master in Redis
void register_agent(Redis &redis, const std::string &hostname) {
    auto& logger = Logger::getInstance();
    logger.info("Registering agent with hostname: " + hostname);
    
    try {
        std::string user = get_user_from_whoami();
        logger.info("Agent running as user: " + user);
        
        redis.set("agents:" + hostname, hostname);
        
        std::string agent_id_key = hostname + "_agent_id";
        std::string user_key = hostname + "_user";
        std::string active_key = hostname + "_active";
        
        auto existing_agent_id = redis.get(agent_id_key);
        int uuid = 0;
        
        if (existing_agent_id) {
            uuid = std::stoi(*existing_agent_id);
            logger.info("Using existing agent UUID: " + std::to_string(uuid));
        } else {
            uuid = redis.incr("agent_uuid_counter");
            redis.set(agent_id_key, std::to_string(uuid));
            logger.info("Generated new agent UUID: " + std::to_string(uuid));
        }
        
        redis.set(user_key, user);
        redis.set(active_key, "yes");
        redis.expire(active_key, 10);
        
        logger.info("Agent registration complete. UUID: " + std::to_string(uuid));
        
        while (true) {
            redis.set(active_key, "yes");
            redis.set(user_key, user);
            redis.expire(active_key, 50);
            logger.debug("Agent status refreshed");
            
            // Check for shutdown request
            if (shutdown_requested.load()) {
                logger.info("Registration thread shutting down");
                break;
            }
            
            std::this_thread::sleep_for(std::chrono::seconds(20));
        }
    } catch (const std::exception &e) {
        logger.error("Registration error: " + std::string(e.what()));
        throw;
    }
}

// Global variables for cleanup (only used outside signal handler)
Redis* global_redis = nullptr;
std::string global_hostname;

// Signal handler - ONLY async-signal-safe operations
void signal_handler(int signum) {
    // Only set atomic flag - actual cleanup happens in main thread
    shutdown_requested.store(true);
}

void daemonize() {
    auto& logger = Logger::getInstance();

    // First fork
    pid_t pid = fork();
    if (pid < 0) {
        logger.error("Failed to fork first time");
        exit(EXIT_FAILURE);
    }
    if (pid > 0) {
        // Parent process exits
        std::cout << "Agent daemon started with PID: " << pid << std::endl;
        exit(EXIT_SUCCESS);
    }

    // Child process continues
    // Create new session
    if (setsid() < 0) {
        logger.error("Failed to create new session");
        exit(EXIT_FAILURE);
    }

    // Second fork
    pid = fork();
    if (pid < 0) {
        logger.error("Failed to fork second time");
        exit(EXIT_FAILURE);
    }
    if (pid > 0) {
        exit(EXIT_SUCCESS);
    }

    // Change working directory
    if (chdir("/") < 0) {
        logger.error("Failed to change working directory");
        exit(EXIT_FAILURE);
    }

    // Close standard file descriptors
    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);

    // Redirect standard files to /dev/null
    open("/dev/null", O_RDONLY);
    open("/dev/null", O_WRONLY);
    open("/dev/null", O_WRONLY);

    // Write PID file
    std::ofstream pid_file("/tmp/agent.pid");
    pid_file << getpid();
    pid_file.close();
}

void kill_existing_instance() {
    std::ifstream pid_file("/tmp/agent.pid");
    if (pid_file.is_open()) {
        pid_t old_pid;
        pid_file >> old_pid;
        pid_file.close();

        if (kill(old_pid, 0) == 0) {
            // Process exists, try graceful shutdown first
            kill(old_pid, SIGTERM);
            std::cout << "Sent SIGTERM to agent process with PID: " << old_pid << std::endl;

            // Wait up to 3 seconds for graceful shutdown
            for (int i = 0; i < 30; i++) {
                if (kill(old_pid, 0) != 0) {
                    std::cout << "Agent process terminated gracefully" << std::endl;
                    std::remove("/tmp/agent.pid");
                    // Clean up active flag in Redis
                    try {
                        auto redis = Redis("tcp://REDIS_HOST_PLACEHOLDER:6379?password=REDIS_PASS_PLACEHOLDER");
                        std::string hostname = get_hostname();
                        redis.del(hostname + "_active");
                        redis.del("agent:" + hostname);
                    } catch (...) {
                        // Ignore Redis errors during cleanup
                    }
                    return;
                }
                usleep(100000); // 100ms
            }

            // Force kill if still running
            kill(old_pid, SIGKILL);
            std::cout << "Force killed agent process with SIGKILL" << std::endl;
            std::remove("/tmp/agent.pid");
            // Clean up active flag in Redis
            try {
                auto redis = Redis("tcp://REDIS_HOST_PLACEHOLDER:6379?password=REDIS_PASS_PLACEHOLDER");
                std::string hostname = get_hostname();
                redis.del(hostname + "_active");
                redis.del("agent:" + hostname);
            } catch (...) {
                // Ignore Redis errors during cleanup
            }
        } else {
            // Process doesn't exist, clean up stale PID file
            std::remove("/tmp/agent.pid");
            // Also clean up active flag in Redis
            try {
                auto redis = Redis("tcp://REDIS_HOST_PLACEHOLDER:6379?password=REDIS_PASS_PLACEHOLDER");
                std::string hostname = get_hostname();
                redis.del(hostname + "_active");
                redis.del("agent:" + hostname);
            } catch (...) {
                // Ignore Redis errors during cleanup
            }
        }
    }
}

void print_usage() {
    std::cout << "Usage: ./agent [-k]\n"
              << "  -k    Kill existing agent process and exit\n";
}

// Function to handle file transfers
void handle_file_transfers(Redis &redis, const std::string &hostname) {
    auto& logger = Logger::getInstance();
    std::string transfer_prefix = "file_transfer:" + hostname + ":";
    
    while (true) {
        try {
            std::vector<std::string> keys;
            redis.keys(transfer_prefix + "*", std::back_inserter(keys));
            
            for (const auto &key : keys) {
                auto operation = redis.hget(key, "operation");
                auto path = redis.hget(key, "path");
                
                if (!operation || !path) continue;
                
                if (*operation == "check_type") {
                    try {
                        bool is_dir = fs::is_directory(*path);
                        redis.hset(key, "type", is_dir ? "directory" : "file");
                        redis.hset(key, "status", "completed");
                    } catch (const std::exception& e) {
                        redis.hset(key, "status", "error");
                        redis.hset(key, "error", e.what());
                    }
                } else if (*operation == "read") {
                    try {
                        logger.info("Checking path type: " + *path);
                        bool is_dir = fs::is_directory(*path);
                        std::string content;
                        
                        if (is_dir) {
                            logger.info("Detected directory transfer - Source: " + *path);
                            content = create_tar_archive(*path);
                            redis.hset(key, "is_directory", "1");
                            logger.info("Directory packaged successfully");
                        } else {
                            logger.info("Detected file transfer - Source: " + *path);
                            std::ifstream file(*path, std::ios::binary);
                            if (!file.is_open()) {
                                throw std::runtime_error("Failed to open file for reading");
                            }
                            std::stringstream buffer;
                            buffer << file.rdbuf();
                            file.close();
                            content = buffer.str();
                            redis.hset(key, "is_directory", "0");
                        }
                        
                        redis.hset(key, "content", content);
                        redis.hset(key, "status", "completed");
                        logger.info("Transfer completed: " + *path + (is_dir ? " (directory)" : " (file)"));
                    } catch (const std::exception& e) {
                        redis.hset(key, "status", "error");
                        redis.hset(key, "error", e.what());
                        logger.error("Read error for " + *path + ": " + std::string(e.what()));
                    }
                } else if (*operation == "write") {
                    auto content = redis.hget(key, "content");
                    auto is_directory = redis.hget(key, "is_directory");
                    if (!content) continue;
                    
                    try {
                        if (is_directory && *is_directory == "1") {
                            // Handle directory transfer
                            extract_tar_archive(*content, *path);
                        } else {
                            // Handle regular file transfer
                            std::ofstream file(*path, std::ios::binary);
                            if (!file.is_open()) {
                                throw std::runtime_error("Failed to open file for writing");
                            }
                            file << *content;
                            file.close();
                        }
                        redis.hset(key, "status", "completed");
                        logger.info("Write completed: " + *path);
                    } catch (const std::exception& e) {
                        redis.hset(key, "status", "error");
                        redis.hset(key, "error", e.what());
                        logger.error("Write error: " + std::string(e.what()));
                    }
                }
            }
            
            // Check for shutdown request
            if (shutdown_requested.load()) {
                logger.info("File transfer handler shutting down");
                break;
            }
            
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        } catch (const std::exception& e) {
            logger.error("Transfer handler error: " + std::string(e.what()));
        }
    }
}

void print_version() {
    std::cout << "Monitor Agent version: " << "VERSION_PLACEHOLDER" << std::endl;
}

int main(int argc, char* argv[]) {
    // Check for version flag
    if (argc > 1 && std::string(argv[1]) == "-v") {
        print_version();
        return 0;
    }

    // Check for command line arguments
    if (argc > 1) {
        std::string arg(argv[1]);
        if (arg == "-k") {
            kill_existing_instance();
            std::cout << "Agent process killed.\n";
            return 0;
        } else {
            print_usage();
            return 1;
        }
    }

    try {
        // Kill any existing instance
        kill_existing_instance();

        auto& logger = Logger::getInstance();
        logger.info("Agent starting up");

        // Daemonize the process
        daemonize();

        logger.info("Agent daemonized successfully");

        auto redis = Redis("tcp://REDIS_HOST_PLACEHOLDER:6379?password=REDIS_PASS_PLACEHOLDER");
        logger.info("Connected to Redis server");

        std::string hostname = get_hostname();

        // Set global variables for cleanup (NOT used in signal handler)
        global_redis = &redis;
        global_hostname = hostname;

        // Set up signal handlers for graceful shutdown
        signal(SIGTERM, signal_handler);
        signal(SIGINT, signal_handler);

        std::thread metrics_thread(collect_and_send_metrics, std::ref(redis), hostname);
        std::thread command_thread(listen_for_commands, std::ref(redis), hostname);
        std::thread register_thread(register_agent, std::ref(redis), hostname);
        std::thread file_transfer_thread(handle_file_transfers, std::ref(redis), hostname);

        // Wait for shutdown signal
        while (!shutdown_requested.load()) {
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }

        // Perform cleanup (this is safe - not in signal handler)
        logger.info("Agent shutting down gracefully");
        try {
            std::string active_key = hostname + "_active";
            redis.del(active_key);
            logger.info("Removed active flag from Redis");
        } catch (const std::exception& e) {
            logger.error("Error removing active flag: " + std::string(e.what()));
        }

        // Remove PID file
        std::remove("/tmp/agent.pid");

        // Wait for threads to finish
        metrics_thread.join();
        command_thread.join();
        register_thread.join();
        file_transfer_thread.join();
        
        logger.info("Agent shutdown complete");
    } catch (const Error &e) {
        auto& logger = Logger::getInstance();
        logger.error("Redis error: " + std::string(e.what()));
        return 1;
    }

    return 0;
}

