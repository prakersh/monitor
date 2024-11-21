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


using namespace sw::redis;

// Retrieve the hostname of the machine
std::string get_hostname() {
    struct utsname uts;
    if (uname(&uts) == 0) {
        return std::string(uts.nodename);
    }
    return "unknown";
}

// Execute a shell command and return return code, stdout, and stderr.
void execute_command(const std::string &cmd, int &return_code, std::string &stdout_data, std::string &stderr_data) {
    FILE *pipe = popen((cmd + " 2>&1").c_str(), "r");
    if (!pipe) {
        stderr_data = "Failed to execute command.";
        return_code = -1;
        return;
    }
    char buffer[128];
    while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
        stdout_data += buffer;
    }
    return_code = pclose(pipe);
}

// Collect comprehensive system metrics and send to Redis
void collect_and_send_metrics(Redis &redis, const std::string &hostname) {
    while (true) {
        struct sysinfo info;
        if (sysinfo(&info) == 0) {
            long total_ram = info.totalram / (1024 * 1024); // Convert to MB
            long free_ram = info.freeram / (1024 * 1024);
            long used_ram = total_ram - free_ram;
            double load_avg = info.loads[0] / 65536.0;

            // CPU usage from /proc/stat
            std::ifstream cpu_file("/proc/stat");
            std::string cpu_line;
            double cpu_usage = 0.0;
            if (std::getline(cpu_file, cpu_line)) {
                std::istringstream ss(cpu_line);
                std::string cpu;
                long user, nice, system, idle;
                ss >> cpu >> user >> nice >> system >> idle;
                cpu_usage = 100.0 * (user + nice + system) / (user + nice + system + idle);
            }

            // Update metrics in Redis
            std::string key = "agent:" + hostname + ":metrics";
            redis.hset(key, "total_ram_mb", std::to_string(total_ram));
            redis.hset(key, "used_ram_mb", std::to_string(used_ram));
            redis.hset(key, "load_avg", std::to_string(load_avg));
            redis.hset(key, "cpu_usage_percent", std::to_string(cpu_usage));
            //redis.expire(key, 120); // Expire metrics after 10 seconds

            redis.publish("metrics_channel", "Metrics updated for " + hostname);
            // std::cout << "Metrics sent to Redis for " << hostname << ".\n";
        } else {
            std::cerr << "Failed to get system info.\n";
        }
        std::this_thread::sleep_for(std::chrono::seconds(60));
    }
}

// Listen for commands and execute those targeting this agent
void listen_for_commands(Redis &redis, const std::string &hostname) {
    std::string command_prefix = "run:" + hostname + ":";
    std::cout << "Listening for commands" << std::endl;
    while (true) {
        std::vector<std::string> keys;
        redis.keys(command_prefix + "*", std::back_inserter(keys));
        for (const auto &key : keys) {
            auto uuid = redis.get(key);
            if (uuid) {
                auto command = redis.get(*uuid);
                std::cout << "Received command: " << *command << std::endl;

                int return_code;
                std::string stdout_data, stderr_data;
                execute_command(*command, return_code, stdout_data, stderr_data);

                std::string base_key = *uuid + ":";
                redis.set(base_key + "return_code", std::to_string(return_code));
                redis.set(base_key + "stdout", stdout_data);
                redis.set(base_key + "stderr", stderr_data);

                redis.del(key); // Clean up command key after execution
                std::cout << "Command response sent.\n Deleted key"<<key;
            }
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
    std::cout << "Registering agent to Redis" << std::endl;

    // Get the user using the whoami command
    std::string user;
    try {
        user = get_user_from_whoami();
    } catch (const std::exception &e) {
        std::cerr << "Error getting user: " << e.what() << std::endl;
        user = "unknown";
    }
    redis.set("agents:"+hostname, hostname);  // Set the user info
    // Generate keys for agent information
    std::string agent_id_key = hostname + "_agent_id";
    std::string user_key = hostname + "_user";
    std::string active_key = hostname + "_active";

    try {
        // Check if the agent_id already exists for the given hostname
        auto existing_agent_id = redis.get(agent_id_key);

        int uuid = 0;

        // If the agent_id already exists, use the existing UUID, otherwise increment the counter
        if (existing_agent_id) {
            uuid = std::stoi(*existing_agent_id);  // Use the existing UUID
            std::cout << "Using existing agent UUID: " << uuid << std::endl;
        } else {
            // If the UUID doesn't exist, create a new UUID
            uuid = redis.incr("agent_uuid_counter");
            redis.set(agent_id_key, std::to_string(uuid));  // Set the new agent UUID in Redis
            std::cout << "Generated new agent UUID: " << uuid << std::endl;
        }

        // Set the agent's user info and status in Redis
        redis.set(user_key, user);  // Set the user info
        redis.set(active_key, "yes");  // Set the agent as active

        // Set the expiration for the "active" key only
        redis.expire(active_key, 10);

        std::cout << "Agent registered with UUID " << uuid << " and user " << user << std::endl;

        // Sleep before updating again
        while (true) {
            std::this_thread::sleep_for(std::chrono::seconds(5));

            // Optionally refresh the agent status and user info every 5 seconds
            redis.set(active_key, "yes");  // Ensure the agent is still active
            redis.set(user_key, user);  // Refresh user info

            // Keep the "active" key with a 10-second expiration
            redis.expire(active_key, 10);
        }

    } catch (const sw::redis::Error &e) {
        // Print the error and the key that caused it
        std::cerr << "Redis Error: " << e.what() << " (Key causing error: " << active_key << ")" << std::endl;
    }
}


int main() {
    try {
        std::cout << "Starting Agent" << std::endl;

        auto redis = Redis("tcp://prakersh.in:6379?password=Jmnwgh87nOCVOWc6RYuQbNa/5DmDon3uQEjVAHbJ2Vj5xNeSvw4urxydZxeeEbkP4YCrGPb3OiYknuvk");
        std::cout << "Connected to redis" << std::endl;

        std::string hostname = get_hostname();

        std::thread metrics_thread(collect_and_send_metrics, std::ref(redis), hostname);
        std::thread command_thread(listen_for_commands, std::ref(redis), hostname);
        std::thread register_thread(register_agent, std::ref(redis), hostname);

        metrics_thread.join();
        command_thread.join();
        register_thread.join();
    } catch (const Error &e) {
        std::cerr << "Redis error: " << e.what() << std::endl;
    }

    return 0;
}
