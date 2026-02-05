#include <sw/redis++/redis++.h>
#include <iostream>
#include <thread>
#include <uuid/uuid.h>
#include <fstream>
#include <sstream>
#include <chrono>
#include <iomanip>
#include <filesystem>
#include <mutex>
#include <algorithm>
#include <cctype>

namespace fs = std::filesystem;

using namespace sw::redis;

// Thread-safe Logger using Meyers' singleton pattern
class Logger {
private:
    std::ofstream log_file;
    std::string log_path;
    static constexpr size_t MAX_LOG_SIZE = 10 * 1024 * 1024; // 10MB
    std::mutex log_mutex;
    
    Logger() {
        log_path = "/var/log/master.log";
        checkAndRotateLog();
        log_file.open(log_path, std::ios::app);
    }

    void checkAndRotateLog() {
        std::ifstream file(log_path, std::ios::binary | std::ios::ate);
        if (file.is_open()) {
            size_t size = file.tellg();
            file.close();
            
            if (size > MAX_LOG_SIZE) {
                std::string backup = log_path + ".old";
                std::remove(backup.c_str());
                std::rename(log_path.c_str(), backup.c_str());
            }
        }
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

    void log(const std::string& level, const std::string& category, const std::string& message) {
        std::lock_guard<std::mutex> lock(log_mutex);
        if (log_file.is_open()) {
            log_file << getCurrentTimestamp() << "\t" << level << "\t" 
                    << "[" << category << "]\t" << message << std::endl;
            log_file.flush();
            
            checkAndRotateLog();
        }
    }

    void info(const std::string& category, const std::string& message) {
        log("INFO", category, message);
    }

    void error(const std::string& category, const std::string& message) {
        log("ERROR", category, message);
    }

    void debug(const std::string& category, const std::string& message) {
        log("DEBUG", category, message);
    }

    void command(const std::string& hostname, const std::string& cmd, const std::string& status) {
        info("COMMAND", hostname + " | " + status + " | " + cmd);
    }

    void fileTransfer(const std::string& hostname, const std::string& operation, 
                     const std::string& status, const std::string& details) {
        info("FILE", hostname + " | " + operation + " | " + status + " | " + details);
    }

    void connection(const std::string& hostname, const std::string& status) {
        info("CONNECTION", hostname + " | " + status);
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

// Generate a unique UUID
std::string generate_uuid() {
    uuid_t uuid;
    char uuid_str[37];
    uuid_generate(uuid);
    uuid_unparse(uuid, uuid_str);
    return std::string(uuid_str);
}

// Send a command to a specific agent
void send_command(Redis &redis, const std::string &hostname, const std::string &command) {
    auto& logger = Logger::getInstance();
    
    // Log command initiation
    logger.command(hostname, command, "INITIATED");
    
    // Check if the agent_id for the hostname is already assigned
    auto agent_id_str = redis.get(hostname + "_agent_id");
    if (!agent_id_str) {
        logger.error("AGENT", "No agent ID found for host: " + hostname);
        return;
    }

    int agent_id = std::stoi(*agent_id_str);

    // Check if the UUID already exists for the hostname, else generate one
    std::string uuid_key = "uuid:" + command + hostname;
    auto existing_uuid = redis.get(uuid_key);
    std::string uuid;
    if (existing_uuid) {
        uuid = *existing_uuid;
        std::cout << "Using existing UUID: " << uuid << std::endl;
    } else {
        uuid = generate_uuid();
        redis.set(uuid_key, uuid);  // BUG FIX: Use consistent key format
        std::cout << "Generated new UUID: " << uuid << std::endl;
    }

    // Create a unique command key using the hostname and UUID
    std::string command_key = "run:" + hostname + ":" + command;

    // Set the command in Redis
    redis.set(command_key, uuid);
    redis.set(uuid, command);
    std::cout << "Command: " << command << " sent to Host: " << hostname << std::endl;

    // Log the command being sent
    logger.info("COMMAND", "---- Command sent ----");
    logger.info("COMMAND", "Host: " + hostname + ", Command: " + command);
    logger.info("COMMAND", "-------------------------");

    // Log command execution
    logger.command(hostname, command, "EXECUTING");
    
    // Monitor the command execution result with timeout (BUG FIX)
    const int TIMEOUT_SECONDS = 60;
    int elapsed = 0;
    
    while (elapsed < TIMEOUT_SECONDS) {
        std::string base_key = uuid + ":";

        // Fetch execution result (return code, stdout, stderr)
        auto return_code = redis.get(base_key + "return_code");
        auto stdout_data = redis.get(base_key + "stdout");
        auto stderr_data = redis.get(base_key + "stderr");

        if (return_code && stdout_data && stderr_data) {
            // Log completion with return code
            logger.command(hostname, command, "COMPLETED | RC=" + *return_code);
            
            if (*return_code != "0") {
                logger.error("COMMAND", 
                    "Command failed on " + hostname + "\n" +
                    "STDERR: " + *stderr_data);
            }

            // Command execution is complete
            std::cout << "Command Execution Result from " << hostname << ":\n";
            std::cout << "Return Code: " << *return_code << "\n";
            std::cout << "STDOUT: \n" << *stdout_data << "\n";
            std::cout << "STDERR: \n" << *stderr_data << "\n";

            // Log the results
            logger.info("COMMAND", "---- Command Execution Result ----");
            logger.info("COMMAND", "Host: " + hostname);
            logger.info("COMMAND", "Return Code: " + *return_code);
            logger.info("COMMAND", "STDOUT: " + *stdout_data);
            logger.info("COMMAND", "STDERR: " + *stderr_data);
            logger.info("COMMAND", "-----------------------------------");

            // Clean up the command keys
            redis.del(base_key + "return_code");
            redis.del(base_key + "stdout");
            redis.del(base_key + "stderr");
            redis.del(command_key);
            redis.del(uuid_key);

            return;  // Success
        }

        // Sleep for a while before checking the result again
        std::this_thread::sleep_for(std::chrono::seconds(1));
        elapsed++;
    }
    
    // Timeout occurred (BUG FIX)
    logger.error("COMMAND", "Timeout waiting for command result from " + hostname);
    std::cerr << "Error: Command execution timeout after " << TIMEOUT_SECONDS << " seconds" << std::endl;
    
    // Cleanup on timeout
    redis.del(command_key);
    redis.del(uuid_key);
}
// Helper function to create a tar archive of a folder
std::string create_tar_archive(const std::string& folder_path) {
    if (!fs::exists(folder_path)) {
        throw std::runtime_error("Source path does not exist: " + folder_path);
    }

    if (!fs::is_directory(folder_path)) {
        throw std::runtime_error("Source path is not a directory: " + folder_path);
    }

    std::string temp_tar = "/tmp/" + generate_uuid() + ".tar";

    // Create tar with directory name as root in archive
    // This preserves the directory structure when extracting
    std::string parent_dir = fs::path(folder_path).parent_path().string();
    std::string dir_name = fs::path(folder_path).filename().string();

    if (parent_dir.empty()) {
        parent_dir = ".";
    }

    std::string cmd = "tar -cf " + temp_tar + " -C " + parent_dir + " " + dir_name;

    int result = system(cmd.c_str());
    if (result != 0) {
        throw std::runtime_error("Failed to create tar archive. Command: " + cmd);
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
}

// Helper function to extract a tar archive
void extract_tar_archive(const std::string& tar_content, const std::string& dest_path) {
    std::string temp_tar = "/tmp/" + generate_uuid() + ".tar";
    auto& logger = Logger::getInstance();

    // Write the tar content to temporary file
    std::ofstream tar_file(temp_tar, std::ios::binary);
    tar_file << tar_content;
    tar_file.close();

    // Create destination directory
    fs::create_directories(dest_path);

    logger.info("FILE", "Extracting tar archive to: " + dest_path);

    // Extract the tar archive into a temporary location first
    std::string temp_extract = "/tmp/" + generate_uuid();
    fs::create_directories(temp_extract);

    std::string cmd = "tar -xf " + temp_tar + " -C " + temp_extract;
    int result = system(cmd.c_str());

    if (result != 0) {
        std::remove(temp_tar.c_str());
        fs::remove_all(temp_extract);
        throw std::runtime_error("Failed to extract tar archive");
    }

    // Find the extracted directory (should be only one)
    for (const auto& entry : fs::directory_iterator(temp_extract)) {
        if (fs::is_directory(entry.path())) {
            // Move contents from the extracted directory to destination
            for (const auto& subentry : fs::directory_iterator(entry.path())) {
                fs::copy(subentry.path(), dest_path / subentry.path().filename(),
                        fs::copy_options::recursive | fs::copy_options::overwrite_existing);
            }
            break;
        }
    }

    // Clean up temporary files
    std::remove(temp_tar.c_str());
    fs::remove_all(temp_extract);
}


// List all connected agents
void list_agents(Redis &redis) {
    auto& logger = Logger::getInstance();
    std::vector<std::string> keys;
    redis.keys("agents:*", std::back_inserter(keys));  // Fetch all agent-related keys

    std::cout << "\nConnected Agents:\n";
    for (const auto &key : keys) {
        std::string hostname = key.substr(7);  // Strip "agents:" prefix

        // Fetch agent info using the keys set during registration
        auto agent_id = redis.get(hostname + "_agent_id");
        auto user = redis.get(hostname + "_user");
        auto active = redis.get(hostname + "_active");

        // Log connection event
        logger.connection(hostname, "LISTED");

        // Print agent information
        std::cout << "- Hostname: " << hostname
                  << "\tAgent ID: " << (agent_id ? *agent_id : "N/A")
                  << "\tUser: " << (user ? *user : "N/A")
                  << "\tActive: " << (active ? *active : "N/A")
                  << "\n";
    }
}


// Function to read a file and send its contents to an agent
void send_file_to_agent(Redis &redis, const std::string &hostname, 
                       const std::string &local_path, const std::string &remote_path) {
    auto& logger = Logger::getInstance();
    
    logger.fileTransfer(hostname, "WRITE", "STARTED", 
                        "Local: " + local_path + " -> Remote: " + remote_path);
    
    std::string content;
    bool is_directory = fs::is_directory(local_path);
    
    try {
        if (is_directory) {
            logger.info("FILE", "Detected directory transfer");
            content = create_tar_archive(local_path);
        } else {
            std::ifstream file(local_path, std::ios::binary);
            if (!file.is_open()) {
                logger.error("FILE", "Failed to open local file: " + local_path);
                return;
            }
            std::stringstream buffer;
            buffer << file.rdbuf();
            content = buffer.str();
            file.close();
        }
        
        auto uuid = generate_uuid();
        std::string transfer_key = "file_transfer:" + hostname + ":" + uuid;
        
        logger.info("FILE", "---- File Transfer Started ----");
        logger.info("FILE", "Host: " + hostname + ", Operation: WRITE");
        logger.info("FILE", "Local path: " + local_path);
        logger.info("FILE", "Remote path: " + remote_path);
        
        // Store file transfer information in Redis
        redis.hset(transfer_key, "operation", "write");
        redis.hset(transfer_key, "path", remote_path);
        redis.hset(transfer_key, "content", content);
        redis.hset(transfer_key, "is_directory", is_directory ? "1" : "0");
        
        // Monitor transfer status with timeout
        const int MAX_WAIT_SECONDS = 30;
        const int MAX_RETRIES = MAX_WAIT_SECONDS * 10;  // Check every 100ms
        int retry_count = 0;

        while (retry_count < MAX_RETRIES) {
            auto status = redis.hget(transfer_key, "status");
            if (status) {
                if (*status == "completed") {
                    std::cout << "File transfer completed successfully" << std::endl;
                    logger.info("FILE", "Transfer completed successfully");
                    redis.del(transfer_key);
                    break;
                } else if (*status == "error") {
                    auto error = redis.hget(transfer_key, "error");
                    logger.error("FILE", "Transfer failed: " + (error ? *error : "Unknown error"));
                    redis.del(transfer_key);
                    break;
                }
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            retry_count++;
        }

        if (retry_count >= MAX_RETRIES) {
            logger.error("FILE", "Transfer timeout: Agent did not respond within " + std::to_string(MAX_WAIT_SECONDS) + " seconds");
            std::cerr << "Error: File transfer timeout - agent did not respond" << std::endl;
            redis.del(transfer_key);
        }
        
    } catch (const std::exception& e) {
        logger.error("FILE", "Transfer error: " + std::string(e.what()));
    }
    
    logger.info("FILE", "---------------------------");
}

// Function to receive a file from an agent
void receive_file_from_agent(Redis &redis, const std::string &hostname, 
                           const std::string &remote_path, const std::string &local_path) {
    auto& logger = Logger::getInstance();
    
    // First check if remote path is a directory
    auto check_uuid = generate_uuid();
    std::string check_key = "file_transfer:" + hostname + ":" + check_uuid;
    redis.hset(check_key, "operation", "check_type");
    redis.hset(check_key, "path", remote_path);
    
    bool is_directory = false;
    logger.info("FILE", "Checking remote path type: " + remote_path);
    
    // Wait for type check response with timeout
    const int MAX_WAIT_SECONDS = 30;
    const int MAX_RETRIES = MAX_WAIT_SECONDS * 10;
    int retry_count = 0;

    while (retry_count < MAX_RETRIES) {
        auto status = redis.hget(check_key, "status");
        if (status && *status == "completed") {
            auto type = redis.hget(check_key, "type");
            is_directory = (type && *type == "directory");
            logger.info("FILE", std::string("Remote path is ") + (is_directory ? "directory" : "file"));
            redis.del(check_key);
            break;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        retry_count++;
    }

    if (retry_count >= MAX_RETRIES) {
        logger.error("FILE", "Type check timeout: Agent did not respond within " + std::to_string(MAX_WAIT_SECONDS) + " seconds");
        std::cerr << "Error: Type check timeout - agent did not respond" << std::endl;
        redis.del(check_key);
        return;
    }
    
    // Create parent directory if needed
    try {
        fs::path local_fs_path(local_path);
        if (is_directory) {
            // For directories, create the target directory itself
            fs::create_directories(local_fs_path);
        } else {
            // For files, create parent directory if needed
            if (local_fs_path.has_parent_path()) {
                fs::create_directories(local_fs_path.parent_path());
            }
        }
    } catch (const fs::filesystem_error& e) {
        logger.error("FILE", "Failed to create directory structure: " + std::string(e.what()));
        throw;
    }
    
    // Now proceed with actual transfer
    auto uuid = generate_uuid();
    std::string transfer_key = "file_transfer:" + hostname + ":" + uuid;
    
    logger.info("FILE", "---- File Transfer Request ----");
    logger.info("FILE", "Host: " + hostname + ", Operation: READ");
    logger.info("FILE", std::string("Remote ") + (is_directory ? "directory" : "file") + ": " + remote_path);
    logger.info("FILE", "Local path: " + local_path);
    
    redis.hset(transfer_key, "operation", "read");
    redis.hset(transfer_key, "path", remote_path);
    redis.hset(transfer_key, "is_directory", is_directory ? "1" : "0");
    
    // Wait for response with timeout
    retry_count = 0;
    while (retry_count < MAX_RETRIES) {
        auto status = redis.hget(transfer_key, "status");
        if (status) {
            if (*status == "completed") {
                auto content = redis.hget(transfer_key, "content");
                if (content) {
                    try {
                        if (is_directory) {
                            logger.info("FILE", "Extracting directory contents to: " + local_path);
                            extract_tar_archive(*content, local_path);
                            logger.info("FILE", "Directory extraction completed");
                        } else {
                            std::ofstream file(local_path, std::ios::binary);
                            if (!file.is_open()) {
                                throw std::runtime_error("Failed to open local file for writing");
                            }
                            file << *content;
                            file.close();
                        }
                        std::cout << "File transfer completed successfully" << std::endl;
                        logger.info("FILE", "Transfer completed successfully");
                    } catch (const std::exception& e) {
                        std::cerr << "Transfer failed: " << e.what() << std::endl;
                        logger.error("FILE", "Transfer failed: " + std::string(e.what()));
                    }
                }
                redis.del(transfer_key);
                break;
            } else if (*status == "error") {
                auto error = redis.hget(transfer_key, "error");
                std::cerr << "File transfer failed: " << (error ? *error : "Unknown error") << std::endl;
                logger.error("FILE", "Transfer failed: " + (error ? *error : "Unknown error"));
                redis.del(transfer_key);
                break;
            }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        retry_count++;
    }

    if (retry_count >= MAX_RETRIES) {
        logger.error("FILE", "Transfer timeout: Agent did not respond within " + std::to_string(MAX_WAIT_SECONDS) + " seconds");
        std::cerr << "Error: File transfer timeout - agent did not respond" << std::endl;
        redis.del(transfer_key);
    }
    logger.info("FILE", "---------------------------");
}

// Validate that a string represents a valid integer
bool is_valid_integer(const std::string& str) {
    if (str.empty()) return false;
    
    size_t pos = 0;
    if (str[0] == '-' || str[0] == '+') {
        if (str.length() == 1) return false;
        pos = 1;
    }
    
    for (; pos < str.length(); ++pos) {
        if (!std::isdigit(str[pos])) return false;
    }
    
    return true;
}

void handle_cli_input(Redis &redis, int argc, char *argv[]) {
    // Validate first argument is a valid option number
    if (!is_valid_integer(argv[1])) {
        std::cerr << "Error: Invalid option. Must be a number between 1 and 5." << std::endl;
        return;
    }
    
    int option;
    try {
        option = std::stoi(argv[1]);
    } catch (const std::exception& e) {
        std::cerr << "Error: Invalid option number." << std::endl;
        return;
    }
    
    // Validate option is in valid range
    if (option < 1 || option > 5) {
        std::cerr << "Error: Option must be between 1 and 5." << std::endl;
        std::cout << "Valid options:\n"
                  << "1 - List agents\n"
                  << "2 - Send command: ./master 2 <hostname> <command>\n"
                  << "3 - Interactive moni.sh: ./master 3 <hostname>\n"
                  << "4 - Send file: ./master 4 <hostname> <local_path> <remote_path>\n"
                  << "5 - Receive file: ./master 5 <hostname> <remote_path> <local_path>\n";
        return;
    }

    switch (option) {
        case 1:  // List agents
            if (argc != 2) {
                std::cout << "Usage: ./master 1\n";
                return;
            }
            list_agents(redis);
            break;

        case 2:  // Send command
            if (argc != 4) {
                std::cout << "Usage: ./master 2 <hostname> <command>\n";
                return;
            }
            send_command(redis, argv[2], argv[3]);
            break;

        case 3:  // Interactive moni.sh mode
            if (argc != 3) {
                std::cout << "Usage: ./master 3 <hostname>\n";
                return;
            }
            {  // Added block scope for new variables
                auto user = redis.get(std::string(argv[2]) + "_user");
                auto pwd = redis.get(std::string(argv[2]) + "_pwd");
                std::cout << "Entering moni.sh for " << argv[2] << ":\n";
                while (true) {
                    // Display prompt with user, hostname, and pwd
                    std::cout << (user ? *user : "unknown") << "@" << argv[2] << ":" 
                              << (pwd ? *pwd : "~") << "$ ";
                    
                    std::string command;
                    std::getline(std::cin, command);
                    if (command == "exit" || command == "quit") {
                        std::cout << "Exiting...\n";
                        break;
                    }
                    else if (command.empty() || command == " " || command == "\n" || command == "\t") {
                        continue;
                    }
                    send_command(redis, argv[2], command);
                }
            }
            break;

        case 4:  // Send file
            if (argc != 5) {
                std::cout << "Usage: ./master 4 <hostname> <local_path> <remote_path>\n";
                return;
            }
            send_file_to_agent(redis, argv[2], argv[3], argv[4]);
            break;

        case 5:  // Receive file
            if (argc != 5) {
                std::cout << "Usage: ./master 5 <hostname> <remote_path> <local_path>\n";
                return;
            }
            receive_file_from_agent(redis, argv[2], argv[3], argv[4]);
            break;

        default:
            std::cout << "Invalid option. Available options:\n"
                      << "1 - List agents\n"
                      << "2 - Send command: ./master 2 <hostname> <command>\n"
                      << "3 - Interactive moni.sh: ./master 3 <hostname>\n"
                      << "4 - Send file: ./master 4 <hostname> <local_path> <remote_path>\n"
                      << "5 - Receive file: ./master 5 <hostname> <remote_path> <local_path>\n"
                      << "-v - Print version information\n";
    }
}

void print_version() {
    std::cout << "Monitor Master version: " << "VERSION_PLACEHOLDER" << std::endl;
}

// Main function
int main(int argc, char *argv[]) {
    // Check for version flag first
    if (argc > 1 && std::string(argv[1]) == "-v") {
        print_version();
        return 0;
    }

    auto redis = Redis("tcp://REDIS_HOST_PLACEHOLDER:6379?password=REDIS_PASS_PLACEHOLDER"); 
    std::cout << "Connected to Redis\n";

    // Initialize next_agent_id in Redis if it doesn't exist
    if (!redis.exists("next_agent_id")) {
        redis.set("next_agent_id", std::to_string(1));
    }

    // Check if there are CLI arguments provided
    if (argc > 1) {
        std::string input(argv[1]);
        try {
            handle_cli_input(redis, argc, argv);
        } catch (const Error &e) {
            std::cerr << "Redis error: " << e.what() << std::endl;
        }
        return 0;
    }

    // Interactive mode if no CLI arguments
    try {
        while (true) {
            std::cout << "\nOptions:\n";
            std::cout << "1. List connected agents\n";
            std::cout << "2. Send a command to an agent\n";
            std::cout << "3. get moni.sh to an agent\n";
            std::cout << "4. Send file to agent\n";
            std::cout << "5. Receive file from agent\n";
            std::cout << "6. Exit\n\n";
            std::cout << "Enter choice: ";
            int choice;
            std::cin >> choice;
            std::cin.ignore();  // Clear input buffer

            if (choice == 1) {
                list_agents(redis);
            } else if (choice == 2) {
                std::cout << "Enter agent hostname: ";
                std::string hostname;
                std::cin >> hostname;
                std::cin.ignore();

                std::cout << "Enter command: ";
                std::string command;
                std::getline(std::cin, command);

                send_command(redis, hostname, command);
            }
            else if (choice == 3) {
                std::cout << "Enter agent hostname or agent_id: ";
                std::string hostname;
                std::cin >> hostname;
                std::cin.ignore();
                
                auto user = redis.get(hostname + "_user");
                auto pwd = redis.get(hostname + "_pwd");
                std::cout << "Entering moni.sh:\n";
                
                while (true) {
                    // Display prompt with user, hostname, and pwd
                    std::cout << (user ? *user : "unknown") << "@" << hostname << ":" 
                              << (pwd ? *pwd : "~") << "$ ";
                    
                    std::string command;
                    std::getline(std::cin, command);
                    if (command == "exit" || command == "quit") {
                        std::cout << "Exiting...\n";
                        break;
                    }
                    else if (command.empty() || command == " " || command == "\n" || command == "\t") {
                        continue;
                    }
                    send_command(redis, hostname, command);
                }
            }
            else if (choice == 4) {
                std::cout << "Enter agent hostname: ";
                std::string hostname;
                std::cin >> hostname;
                std::cin.ignore();

                std::cout << "Enter local file path: ";
                std::string local_path;
                std::getline(std::cin, local_path);

                std::cout << "Enter remote file path: ";
                std::string remote_path;
                std::getline(std::cin, remote_path);

                send_file_to_agent(redis, hostname, local_path, remote_path);
            }
            else if (choice == 5) {
                std::cout << "Enter agent hostname: ";
                std::string hostname;
                std::cin >> hostname;
                std::cin.ignore();

                std::cout << "Enter remote file path: ";
                std::string remote_path;
                std::getline(std::cin, remote_path);

                std::cout << "Enter local file path: ";
                std::string local_path;
                std::getline(std::cin, local_path);

                receive_file_from_agent(redis, hostname, remote_path, local_path);
            }
            else if (choice == 6) {
                std::cout << "Exiting...\n";
                break;
            } else {
                std::cout << "Invalid choice.\n";
            }
        }
    } catch (const Error &e) {
        std::cerr << "Redis error: " << e.what() << std::endl;
    }

    return 0;
}

