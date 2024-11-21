
#include <sw/redis++/redis++.h>
#include <iostream>
#include <thread>
#include <uuid/uuid.h>
#include <fstream>
#include <sstream>

using namespace sw::redis;

// Global log file for master logs
std::ofstream log_file("master.log", std::ios::app);

// Generate a unique UUID
std::string generate_uuid() {
    uuid_t uuid;
    char uuid_str[37];
    uuid_generate(uuid);
    uuid_unparse(uuid, uuid_str);
    return std::string(uuid_str);
}

// Function to log events to master.log
void log_event(const std::string &message) {
    if (log_file.is_open()) {
        log_file << message << std::endl;
    }
}

// Send a command to a specific agent
void send_command(Redis &redis, const std::string &hostname, const std::string &command) {
    // Check if the agent_id for the hostname is already assigned
    auto agent_id_str = redis.get(hostname + "_agent_id");
    int agent_id = 1;  // Default agent_id if it doesn't exist

    if (agent_id_str) {
        agent_id = std::stoi(*agent_id_str);  // Use the existing agent_id if present
        //std::cout << "Using existing Agent ID: " << agent_id << std::endl;
    } else {
        // If agent_id doesn't exist, assign a new one
        // auto next_agent_id_str = redis.get("next_agent_id");
        // if (next_agent_id_str) {
        //     agent_id = std::stoi(*next_agent_id_str);
        // }

        // // Store the new agent_id for the hostname
        // redis.set(hostname + "_agent_id", std::to_string(agent_id));

        // // Increment the agent ID counter
        // redis.incr("next_agent_id");

        std::cout << "Assigned new Agent ID: " << agent_id << std::endl;
    }

    // Check if the UUID already exists for the hostname, else generate one
    auto existing_uuid = redis.get("uuid:" + command + hostname);
    std::string uuid;
    if (existing_uuid) {
        uuid = *existing_uuid;  // Use existing UUID if present
        std::cout << "Using existing UUID: " << uuid << std::endl;
    } else {
        uuid = generate_uuid();  // Function to generate UUID if not found
        redis.set("uuid:" + hostname, uuid);  // Store the new UUID
        std::cout << "Generated new UUID: " << uuid << std::endl;
    }

    // Create a unique command key using the hostname and UUID
    std::string command_key = "run:" + hostname + ":" + command;

    // Set the command in Redis
    redis.set(command_key, uuid);
    redis.set(uuid, command);
    std::cout << "Command: " << command << " sent to Host: " << hostname << std::endl;

    // Log the command being sent
    log_event("---- Command sent ----");
    log_event("Host: " + hostname + ", Command: " + command);
    log_event("-------------------------");

    // Monitor the command execution result
    while (true) {
        std::string base_key = command_key + ":";

        // Fetch execution result (return code, stdout, stderr)
        auto return_code = redis.get(uuid + ":return_code");
        auto stdout_data = redis.get(uuid + ":stdout");
        auto stderr_data = redis.get(uuid + ":stderr");

        if (return_code && stdout_data && stderr_data) {
            // Command execution is complete
            std::cout << "Command Execution Result from " << hostname << ":\n";
            std::cout << "Return Code: " << *return_code << "\n";
            std::cout << "STDOUT: \n" << *stdout_data << "\n";
            std::cout << "STDERR: \n" << *stderr_data << "\n";

            // Log the results
            log_event("---- Command Execution Result ----");
            log_event("Host: " + hostname);
            log_event("Return Code: " + *return_code);
            log_event("STDOUT: " + *stdout_data);
            log_event("STDERR: " + *stderr_data);
            log_event("-----------------------------------");

            // Clean up the command keys
            redis.del(base_key + "return_code");
            redis.del(base_key + "stdout");
            redis.del(base_key + "stderr");
            redis.del(command_key);

            break;  // Break out of the loop after processing the command result
        }

        // Sleep for a while before checking the result again
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }
}

// List all connected agents
void list_agents(Redis &redis) {
    std::vector<std::string> keys;
    redis.keys("agents:*", std::back_inserter(keys));  // Fetch all agent-related keys

    std::cout << "\nConnected Agents:\n";
    for (const auto &key : keys) {
        std::string hostname = key.substr(7);  // Strip "agents:" prefix

        // Fetch agent info using the keys set during registration
        auto agent_id = redis.get(hostname + "_agent_id");
        auto user = redis.get(hostname + "_user");
        auto active = redis.get(hostname + "_active");

        // Print agent information
        std::cout << "- Hostname: " << hostname
                  << "\tAgent ID: " << (agent_id ? *agent_id : "N/A")
                  << "\tUser: " << (user ? *user : "N/A")
                  << "\tActive: " << (active ? *active : "N/A")
                  << "\n";
    }
}


void handle_cli_input(Redis &redis, int argc, char *argv[]) {
    // Check if the number of arguments is valid
    if (argc < 4) {
        std::cout << "Usage: ./master <option> <hostname> <command>\n";
        return;
    }

    int option = std::stoi(argv[1]);  // Option to choose action (1 or 2)
    std::string hostname = argv[2];   // Hostname or agent_id
    std::string command = argv[3];    // Command to send to the agent

    if (option == 2) {
        // Send the command to the agent specified by hostname
        send_command(redis, hostname, command);
    } 
    else if (option == 1) {
        // List all connected agents
        list_agents(redis);
    }
    else {
        std::cout << "Invalid option in CLI input.\n";
    }
}

// Main function
int main(int argc, char *argv[]) {
    std::string pass = "Jmnwgh87nOCVOWc6RYuQbNa/5DmDon3uQEjVAHbJ2Vj5xNeSvw4urxydZxeeEbkP4YCrGPb3OiYknuvk";

    auto redis = Redis("tcp://prakersh.in:6379?password=" + pass); 
    std::cout << "Connected to Redis\n";

    // Initialize next_agent_id in Redis if it doesn't exist
    if (!redis.exists("next_agent_id")) {// Initialize the next agent ID in Redis, starting from 1
        redis.set("next_agent_id", std::to_string(1));  // Start agent IDs from 1
    }

    // Check if there are CLI arguments provided
    if (argc > 1) {
        std::string input(argv[1]);
        try {
            handle_cli_input(redis, argc, argv);  // Process CLI input directly
        } catch (const Error &e) {
            std::cerr << "Redis error: " << e.what() << std::endl;
        }
        return 0;  // Exit after processing CLI input
    }

    // Interactive mode if no CLI arguments
    try {
        while (true) {
            std::cout << "\nOptions:\n";
            std::cout << "1. List connected agents\n";
            std::cout << "2. Send a command to an agent\n";
            std::cout << "3. get moni.sh to an agent\n";
            std::cout << "4. Exit\n\n";
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
                
                std::cout << "Entering moni.sh:\n";
                while (true) {
                    std::string command;
                    std::getline(std::cin, command);
                    if (command == "exit" || command == "quit") {
                        std::cout << "Exiting...\n";
                        break;
                    }
                    else if (command.empty() || command == " " || command == "\n" || command == "\t") {
                        continue; // Skip sending the command
                    }
                    send_command(redis, hostname, command);
                }
            }
             else if (choice == 4) {
                std::cout << "Exiting...\n";
                break;
            } else {
                std::cout << "Invalid choice.\n";
            }
        }
    } catch (const Error &e) {
        std::cerr << "Redis error: " << e.what() << std::endl;
    }

    // Close the log file
    if (log_file.is_open()) {
        log_file.close();
    }

    return 0;
}
