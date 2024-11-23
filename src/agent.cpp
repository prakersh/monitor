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
namespace fs = std::filesystem;
class Logger {
private:
    std::ofstream log_file;
    static Logger* instance;
    std::string log_path;
    const size_t MAX_SIZE = 10 * 1024 * 1024; // 10MB in bytes
    
    // Private constructor for singleton pattern
    Logger() {
        log_path = "/var/log/moniagent.log";
        log_file.open(log_path, std::ios::app);
    }

    void rotate_log() {
        if (log_file.is_open()) {
            log_file.close();
        }

        // Get current file size
        struct stat stat_buf;
        if (stat(log_path.c_str(), &stat_buf) == 0) {
            if (stat_buf.st_size >= MAX_SIZE) {
                // Rename current log to backup
                std::string backup_path = log_path + ".1";
                rename(log_path.c_str(), backup_path.c_str());
            }
        }

        // Open new log file
        log_file.open(log_path, std::ios::app);
    }

public:
    static Logger* getInstance() {
        if (instance == nullptr) {
            instance = new Logger();
        }
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
        if (log_file.is_open()) {
            // Check file size before writing
            struct stat stat_buf;
            if (stat(log_path.c_str(), &stat_buf) == 0) {
                if (stat_buf.st_size >= MAX_SIZE) {
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
};

// Initialize the static instance
Logger* Logger::instance = nullptr;

using namespace sw::redis;
// Generate a unique UUID
std::string generate_uuid() {
    uuid_t uuid;
    char uuid_str[37];
    uuid_generate(uuid);
    uuid_unparse(uuid, uuid_str);
    return std::string(uuid_str);
}

// Retrieve the hostname of the machine
std::string get_hostname() {
    struct utsname uts;
    if (uname(&uts) == 0) {
        return std::string(uts.nodename);
    }
    return "unknown";
}
// Helper function to create a tar archive of a folder
std::string create_tar_archive(const std::string& folder_path) {
    std::string temp_tar = "/tmp/" + generate_uuid() + ".tar";
    std::string cmd = "tar -cf " + temp_tar + " -C " + 
                     fs::path(folder_path).parent_path().string() + " " + 
                     fs::path(folder_path).filename().string();
    
    int result = system(cmd.c_str());
    if (result != 0) {
        throw std::runtime_error("Failed to create tar archive");
    }
    
    // Read the tar file into memory
    std::ifstream tar_file(temp_tar, std::ios::binary);
    std::stringstream buffer;
    buffer << tar_file.rdbuf();
    tar_file.close();
    
    // Clean up temporary tar file
    std::remove(temp_tar.c_str());
    
    return buffer.str();
}

void extract_tar_archive(const std::string& tar_content, const std::string& dest_path) {
    std::string temp_tar = "/tmp/" + generate_uuid() + ".tar";
    
    // Write the tar content to temporary file
    std::ofstream tar_file(temp_tar, std::ios::binary);
    tar_file << tar_content;
    tar_file.close();
    
    // Create the destination directory itself
    fs::create_directories(dest_path);
    
    // Extract the tar archive directly into the destination directory
    std::string cmd = "tar -xf " + temp_tar + " -C " + dest_path;
    int result = system(cmd.c_str());
    
    // Clean up temporary tar file
    std::remove(temp_tar.c_str());
    
    if (result != 0) {
        throw std::runtime_error("Failed to extract tar archive");
    }
}


// Execute a shell command and return return code, stdout, and stderr.
void execute_command(const std::string &cmd, int &return_code, std::string &stdout_data, std::string &stderr_data) {
    auto logger = Logger::getInstance();
    logger->debug("Executing command: " + cmd);
    
    // Special handling for cd command
    if (cmd.substr(0, 2) == "cd") {
        std::string dir = cmd.length() > 3 ? cmd.substr(3) : getenv("HOME");
        return_code = chdir(dir.c_str());
        if (return_code != 0) {
            stderr_data = "Failed to change directory to " + dir;
            logger->error(stderr_data);
        } else {
            char cwd[PATH_MAX];
            if (getcwd(cwd, sizeof(cwd)) != NULL) {
                stdout_data = "Changed directory to: " + std::string(cwd);
                logger->info(stdout_data);
            }
        }
        return;
    }
    
    // For other commands, use popen
    FILE *pipe = popen((cmd + " 2>&1").c_str(), "r");
    if (!pipe) {
        stderr_data = "Failed to execute command.";
        return_code = -1;
        logger->error("Failed to execute command: " + cmd);
        return;
    }
    
    char buffer[128];
    while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
        stdout_data += buffer;
    }
    return_code = pclose(pipe);
    
    logger->debug("Command executed. Return code: " + std::to_string(return_code));
}

// Collect comprehensive system metrics and send to Redis
void collect_and_send_metrics(Redis &redis, const std::string &hostname) {
    auto logger = Logger::getInstance();
    logger->info("Starting metrics collection for host: " + hostname);
    
    while (true) {
        try {
            struct sysinfo info;
            if (sysinfo(&info) == 0) {
                logger->debug("Collecting system metrics");
                
                long total_ram = info.totalram / (1024 * 1024);
                long free_ram = info.freeram / (1024 * 1024);
                long used_ram = total_ram - free_ram;
                double load_avg = info.loads[0] / 65536.0;
                
                std::string metrics_info = "RAM Total: " + std::to_string(total_ram) + 
                                         "MB, Used: " + std::to_string(used_ram) + 
                                         "MB, Load Avg: " + std::to_string(load_avg);
                logger->debug("Metrics collected: " + metrics_info);
                
                std::string key = "agent:" + hostname + ":metrics";
                redis.hset(key, "total_ram_mb", std::to_string(total_ram));
                redis.hset(key, "used_ram_mb", std::to_string(used_ram));
                redis.hset(key, "load_avg", std::to_string(load_avg));
                
                logger->info("Metrics updated in Redis for " + hostname);
            } else {
                logger->error("Failed to get system info for " + hostname);
            }
        } catch (const std::exception& e) {
            logger->error("Error in metrics collection: " + std::string(e.what()));
        }
        
        std::this_thread::sleep_for(std::chrono::seconds(60));
    }
}
// Listen for commands and execute those targeting this agent
void listen_for_commands(Redis &redis, const std::string &hostname) {
    auto logger = Logger::getInstance();
    std::string command_prefix = "run:" + hostname + ":";
    logger->info("Started command listener for host: " + hostname);
    
    while (true) {
        try {
            std::vector<std::string> keys;
            redis.keys(command_prefix + "*", std::back_inserter(keys));
            
            for (const auto &key : keys) {
                auto uuid = redis.get(key);
                if (uuid) {
                    auto command = redis.get(*uuid);
                    logger->info("Received command: " + *command + " (UUID: " + *uuid + ")");
                    
                    int return_code;
                    std::string stdout_data, stderr_data;
                    execute_command(*command, return_code, stdout_data, stderr_data);
                    
                    std::string base_key = *uuid + ":";
                    redis.set(base_key + "return_code", std::to_string(return_code));
                    redis.set(base_key + "stdout", stdout_data);
                    redis.set(base_key + "stderr", stderr_data);
                    
                    redis.del(key);
                    logger->info("Command executed and response sent. Return code: " + 
                               std::to_string(return_code));
                }
            }
        } catch (const std::exception& e) {
            logger->error("Error in command listener: " + std::string(e.what()));
        }
        
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }
}

// Function to run the "whoami" command and get the current user
std::string get_user_from_whoami() {
    std::array<char, 128> buffer;
    std::string user;
    FILE* pipe = popen("whoami", "r");  // Run the whoami command
    if (!pipe) {
        throw std::runtime_error("popen() failed!");
    }
    while (fgets(buffer.data(), buffer.size(), pipe) != nullptr) {
        user += buffer.data();  // Append the output to the user string
    }
    fclose(pipe);
    // Remove the newline character from the user string if present
    if (!user.empty() && user.back() == '\n') {
        user.pop_back();
    }
    return user;
}

// Register the agent with the master in Redis
void register_agent(Redis &redis, const std::string &hostname) {
    auto logger = Logger::getInstance();
    logger->info("Registering agent with hostname: " + hostname);
    
    try {
        std::string user = get_user_from_whoami();
        logger->info("Agent running as user: " + user);
        
        redis.set("agents:" + hostname, hostname);
        
        std::string agent_id_key = hostname + "_agent_id";
        std::string user_key = hostname + "_user";
        std::string active_key = hostname + "_active";
        
        auto existing_agent_id = redis.get(agent_id_key);
        int uuid = 0;
        
        if (existing_agent_id) {
            uuid = std::stoi(*existing_agent_id);
            logger->info("Using existing agent UUID: " + std::to_string(uuid));
        } else {
            uuid = redis.incr("agent_uuid_counter");
            redis.set(agent_id_key, std::to_string(uuid));
            logger->info("Generated new agent UUID: " + std::to_string(uuid));
        }
        
        redis.set(user_key, user);
        redis.set(active_key, "yes");
        redis.expire(active_key, 10);
        
        logger->info("Agent registration complete. UUID: " + std::to_string(uuid));
        
        while (true) {
            redis.set(active_key, "yes");
            redis.set(user_key, user);
            redis.expire(active_key, 50);
            logger->debug("Agent status refreshed");
            std::this_thread::sleep_for(std::chrono::seconds(20));
        }
    } catch (const std::exception &e) {
        logger->error("Registration error: " + std::string(e.what()));
        throw;
    }
}

void daemonize() {
    auto logger = Logger::getInstance();
    
    // First fork
    pid_t pid = fork();
    if (pid < 0) {
        logger->error("Failed to fork first time");
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
        logger->error("Failed to create new session");
        exit(EXIT_FAILURE);
    }

    // Second fork
    pid = fork();
    if (pid < 0) {
        logger->error("Failed to fork second time");
        exit(EXIT_FAILURE);
    }
    if (pid > 0) {
        exit(EXIT_SUCCESS);
    }

    // Change working directory
    if (chdir("/") < 0) {
        logger->error("Failed to change working directory");
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
            // Process exists, kill it
            kill(old_pid, SIGTERM);
            std::cout << "Killed existing agent process with PID: " << old_pid << std::endl;
            sleep(1); // Wait for process to terminate
        }
    }
}

void print_usage() {
    std::cout << "Usage: ./agent [-k]\n"
              << "  -k    Kill existing agent process and exit\n";
}

// Function to handle file transfers
void handle_file_transfers(Redis &redis, const std::string &hostname) {
    auto logger = Logger::getInstance();
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
                        logger->info("Checking path type: " + *path);
                        bool is_dir = fs::is_directory(*path);
                        std::string content;
                        
                        if (is_dir) {
                            logger->info("Detected directory transfer - Source: " + *path);
                            content = create_tar_archive(*path);
                            redis.hset(key, "is_directory", "1");
                            logger->info("Directory packaged successfully");
                        } else {
                            logger->info("Detected file transfer - Source: " + *path);
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
                        logger->info("Transfer completed: " + *path + (is_dir ? " (directory)" : " (file)"));
                    } catch (const std::exception& e) {
                        redis.hset(key, "status", "error");
                        redis.hset(key, "error", e.what());
                        logger->error("Read error for " + *path + ": " + std::string(e.what()));
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
                        logger->info("Write completed: " + *path);
                    } catch (const std::exception& e) {
                        redis.hset(key, "status", "error");
                        redis.hset(key, "error", e.what());
                        logger->error("Write error: " + std::string(e.what()));
                    }
                }
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        } catch (const std::exception& e) {
            logger->error("Transfer handler error: " + std::string(e.what()));
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

        auto logger = Logger::getInstance();
        logger->info("Agent starting up");

        // Daemonize the process
        daemonize();
        
        logger->info("Agent daemonized successfully");

        auto redis = Redis("tcp://REDIS_HOST_PLACEHOLDER:6379?password=REDIS_PASS_PLACEHOLDER");
        logger->info("Connected to Redis server");

        std::string hostname = get_hostname();

        std::thread metrics_thread(collect_and_send_metrics, std::ref(redis), hostname);
        std::thread command_thread(listen_for_commands, std::ref(redis), hostname);
        std::thread register_thread(register_agent, std::ref(redis), hostname);
        std::thread file_transfer_thread(handle_file_transfers, std::ref(redis), hostname);
        file_transfer_thread.detach();

        metrics_thread.join();
        command_thread.join();
        register_thread.join();
        file_transfer_thread.join();
    } catch (const Error &e) {
        auto logger = Logger::getInstance();
        logger->error("Redis error: " + std::string(e.what()));
        return 1;
    }

    return 0;
}

