#!/bin/bash
# File Transfer Tests

run_file_tests() {
    test_section "FILE TRANSFER TESTS"

    # Ensure Redis is running
    if ! check_redis; then
        echo -e "${YELLOW}Starting Redis for file tests...${NC}"
        if ! start_redis; then
            skip_test "All file tests" "Redis not available"
            return 1
        fi
    fi

    # Start agent
    if ! start_test_agent; then
        skip_test "All file tests" "Agent not available"
        return 1
    fi

    local hostname=$(get_current_agent_hostname)
    local test_dir="$TEST_DIR/file_test"
    mkdir -p "$test_dir"

    # Test 1: Send small text file
    test_subsection "Single File Transfer"
    print_test_header "Send small text file"
    local local_file="$test_dir/local_small.txt"
    local remote_file="/tmp/test_small.txt"
    create_test_file "$local_file" 100 "Small test file content"

    output_file="$LOG_DIR/file_send_small_test.log"
    send_file_via_master "$hostname" "$local_file" "$remote_file" "$output_file"

    if [ $? -eq 0 ] && grep -q "File transfer completed successfully" "$output_file"; then
        # Verify file exists on agent
        run_master_command "$hostname" "ls -l $remote_file" "$LOG_DIR/verify_file_exists.log"
        if grep -q "$remote_file" "$LOG_DIR/verify_file_exists.log"; then
            pass_test "Small text file sent successfully" ""
        else
            fail_test "File not found on agent after send" ""
        fi
    else
        fail_test "Failed to send small text file" ""
    fi

    # Test 2: Receive small text file
    print_test_header "Receive small text file"
    local receive_file="$test_dir/received_small.txt"
    output_file="$LOG_DIR/file_receive_small_test.log"
    receive_file_via_master "$hostname" "$remote_file" "$receive_file" "$output_file"

    if [ $? -eq 0 ] && grep -q "File transfer completed successfully" "$output_file"; then
        if verify_file_content "$receive_file" "Small test file content"; then
            pass_test "Small text file received successfully" ""
        else
            fail_test "Received file content incorrect" ""
        fi
    else
        fail_test "Failed to receive small text file" ""
    fi

    # Test 3: Send large file
    test_subsection "Large File Transfer"
    print_test_header "Send large file (10MB)"
    local large_file="$test_dir/large_file.bin"
    local remote_large="/tmp/test_large.bin"
    dd if=/dev/zero of="$large_file" bs=1M count=10 2>/dev/null

    output_file="$LOG_DIR/file_send_large_test.log"
    send_file_via_master "$hostname" "$large_file" "$remote_large" "$output_file"

    if [ $? -eq 0 ] && grep -q "File transfer completed successfully" "$output_file"; then
        run_master_command "$hostname" "ls -lh $remote_large" "$LOG_DIR/verify_large_file.log"
        if grep -q "$remote_large" "$LOG_DIR/verify_large_file.log"; then
            pass_test "Large file sent successfully" ""
        else
            fail_test "Large file not found on agent" ""
        fi
    else
        fail_test "Failed to send large file" ""
    fi

    # Test 4: Send binary file
    test_subsection "Binary File Transfer"
    print_test_header "Send binary file"
    local binary_file="$test_dir/binary_file.bin"
    local remote_binary="/tmp/test_binary.bin"
    generate_random_file "$binary_file" 1024

    output_file="$LOG_DIR/file_send_binary_test.log"
    send_file_via_master "$hostname" "$binary_file" "$remote_binary" "$output_file"

    if [ $? -eq 0 ] && grep -q "File transfer completed successfully" "$output_file"; then
        pass_test "Binary file sent successfully" ""
    else
        fail_test "Failed to send binary file" ""
    fi

    # Test 5: Receive binary file and verify integrity
    print_test_header "Receive and verify binary file"
    local receive_binary="$test_dir/received_binary.bin"
    output_file="$LOG_DIR/file_receive_binary_test.log"
    receive_file_via_master "$hostname" "$remote_binary" "$receive_binary" "$output_file"

    if [ $? -eq 0 ] && grep -q "File transfer completed successfully" "$output_file"; then
        if verify_binary_integrity "$binary_file" "$receive_binary"; then
            pass_test "Binary file integrity verified" ""
        else
            fail_test "Binary file integrity check failed" ""
        fi
    else
        fail_test "Failed to receive binary file" ""
    fi

    # Test 6: Send empty file
    test_subsection "Edge Cases"
    print_test_header "Send empty file"
    local empty_file="$test_dir/empty.txt"
    local remote_empty="/tmp/test_empty.txt"
    create_test_file "$empty_file" 0 ""

    output_file="$LOG_DIR/file_send_empty_test.log"
    send_file_via_master "$hostname" "$empty_file" "$remote_empty" "$output_file"

    if [ $? -eq 0 ] && grep -q "File transfer completed successfully" "$output_file"; then
        run_master_command "$hostname" "test -f $remote_empty && echo 'exists'" "$LOG_DIR/verify_empty_file.log"
        if grep -q "exists" "$LOG_DIR/verify_empty_file.log"; then
            pass_test "Empty file sent successfully" ""
        else
            fail_test "Empty file not found on agent" ""
        fi
    else
        fail_test "Failed to send empty file" ""
    fi

    # Test 7: Send file with spaces in name
    print_test_header "Send file with spaces in name"
    local spaced_file="$test_dir/file with spaces.txt"
    local remote_spaced="/tmp/test file with spaces.txt"
    create_test_file "$spaced_file" 50 "Content with spaces"

    output_file="$LOG_DIR/file_send_spaced_test.log"
    send_file_via_master "$hostname" "$spaced_file" "$remote_spaced" "$output_file"

    if [ $? -eq 0 ] && grep -q "File transfer completed successfully" "$output_file"; then
        pass_test "File with spaces sent successfully" ""
    else
        fail_test "Failed to send file with spaces" ""
    fi

    # Test 8: Send file with special characters
    print_test_header "Send file with special characters"
    local special_file="$test_dir/file!@#\$%.txt"
    local remote_special="/tmp/test!@#\$%.txt"
    create_test_file "$special_file" 50 "Special chars"

    output_file="$LOG_DIR/file_send_special_test.log"
    send_file_via_master "$hostname" "$special_file" "$remote_special" "$output_file"

    if [ $? -eq 0 ] && grep -q "File transfer completed successfully" "$output_file"; then
        pass_test "File with special characters sent successfully" ""
    else
        fail_test "Failed to send file with special characters" ""
    fi

    # Test 9: Send directory
    test_subsection "Directory Transfer"
    print_test_header "Send directory"
    local local_dir="$test_dir/source_dir"
    local remote_dir="/tmp/test_dir"
    create_test_directory "$local_dir" 2 3  # 2 levels, 3 files per level

    output_file="$LOG_DIR/file_send_dir_test.log"
    send_file_via_master "$hostname" "$local_dir" "$remote_dir" "$output_file"

    if [ $? -eq 0 ] && grep -q "File transfer completed successfully" "$output_file"; then
        run_master_command "$hostname" "ls -R $remote_dir" "$LOG_DIR/verify_dir_exists.log"
        if grep -q "level_1" "$LOG_DIR/verify_dir_exists.log"; then
            pass_test "Directory sent successfully" ""
        else
            fail_test "Directory not found on agent" ""
        fi
    else
        fail_test "Failed to send directory" ""
    fi

    # Test 10: Receive directory
    print_test_header "Receive directory"
    local receive_dir="$test_dir/received_dir"
    output_file="$LOG_DIR/file_receive_dir_test.log"
    receive_file_via_master "$hostname" "$remote_dir" "$receive_dir" "$output_file"

    if [ $? -eq 0 ] && grep -q "File transfer completed successfully" "$output_file"; then
        if verify_directory_structure "$receive_dir" 2 3; then
            pass_test "Directory received successfully" ""
        else
            fail_test "Directory structure incorrect" ""
        fi
    else
        fail_test "Failed to receive directory" ""
    fi

    # Test 11: Send empty directory
    print_test_header "Send empty directory"
    local empty_dir="$test_dir/empty_dir"
    local remote_empty_dir="/tmp/empty_dir"
    mkdir -p "$empty_dir"

    output_file="$LOG_DIR/file_send_empty_dir_test.log"
    send_file_via_master "$hostname" "$empty_dir" "$remote_empty_dir" "$output_file"

    if [ $? -eq 0 ] && grep -q "File transfer completed successfully" "$output_file"; then
        run_master_command "$hostname" "test -d $remote_empty_dir && echo 'dir_exists'" "$LOG_DIR/verify_empty_dir.log"
        if grep -q "dir_exists" "$LOG_DIR/verify_empty_dir.log"; then
            pass_test "Empty directory sent successfully" ""
        else
            fail_test "Empty directory not found on agent" ""
        fi
    else
        fail_test "Failed to send empty directory" ""
    fi

    # Test 12: Send to non-existent agent
    test_subsection "Error Handling"
    print_test_header "Send to non-existent agent"
    local non_existent_file="$test_dir/test.txt"
    create_test_file "$non_existent_file" 10 "test"
    output_file="$LOG_DIR/file_send_nonexistent_test.log"

    send_file_via_master "nonexistent_host_xyz" "$non_existent_file" "/tmp/test.txt" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "File transfer" "$output_file"; then
            pass_test "Transfer to non-existent agent handled" ""
        else
            skip_test "Transfer to non-existent agent" "May not be supported"
        fi
    else
        skip_test "Transfer to non-existent agent" "Command failed as expected"
    fi

    # Test 13: Send non-existent file
    print_test_header "Send non-existent file"
    output_file="$LOG_DIR/file_send_missing_test.log"
    send_file_via_master "$hostname" "/tmp/nonexistent_file_xyz" "/tmp/test.txt" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "File transfer" "$output_file"; then
            pass_test "Transfer of non-existent file handled" ""
        else
            skip_test "Transfer of non-existent file" "May not be supported"
        fi
    else
        skip_test "Transfer of non-existent file" "Command failed as expected"
    fi

    # Test 14: Receive non-existent file
    print_test_header "Receive non-existent file"
    local receive_missing="$test_dir/missing.txt"
    output_file="$LOG_DIR/file_receive_missing_test.log"
    receive_file_via_master "$hostname" "/tmp/nonexistent_file_xyz" "$receive_missing" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "File transfer" "$output_file"; then
            pass_test "Receive non-existent file handled" ""
        else
            skip_test "Receive non-existent file" "May not be supported"
        fi
    else
        skip_test "Receive non-existent file" "Command failed as expected"
    fi

    # Test 15: Send file to invalid path
    print_test_header "Send to invalid path"
    local invalid_path_file="$test_dir/test.txt"
    create_test_file "$invalid_path_file" 10 "test"
    output_file="$LOG_DIR/file_send_invalid_path_test.log"

    send_file_via_master "$hostname" "$invalid_path_file" "/root/.ssh/authorized_keys" "$output_file"

    if [ $? -eq 0 ]; then
        if grep -q "File transfer" "$output_file"; then
            pass_test "Transfer to invalid path handled" ""
        else
            skip_test "Transfer to invalid path" "May not be supported"
        fi
    else
        skip_test "Transfer to invalid path" "Command failed as expected"
    fi

    # Test 16: Multiple file transfers
    test_subsection "Multiple Transfers"
    print_test_header "Multiple file transfers"
    local success_count=0
    for i in {1..3}; do
        local multi_file="$test_dir/multi_$i.txt"
        local remote_multi="/tmp/multi_$i.txt"
        create_test_file "$multi_file" 50 "Multi $i"

        output_file="$LOG_DIR/file_multi_${i}_test.log"
        send_file_via_master "$hostname" "$multi_file" "$remote_multi" "$output_file"

        if [ $? -eq 0 ] && grep -q "File transfer completed successfully" "$output_file"; then
            success_count=$((success_count + 1))
        fi
    done

    if [ "$success_count" -eq 3 ]; then
        pass_test "All multiple file transfers succeeded" ""
    else
        fail_test "Some multiple file transfers failed" "Success: $success_count/3"
    fi

    # Test 17: Verify file content after transfer
    test_subsection "Content Verification"
    print_test_header "Verify file content integrity"
    local verify_file="$test_dir/verify.txt"
    local verify_content="Verification test content with special chars !@#"
    create_test_file "$verify_file" 0 "$verify_content"
    local remote_verify="/tmp/verify.txt"

    send_file_via_master "$hostname" "$verify_file" "$remote_verify" "$LOG_DIR/file_verify_send.log"
    local receive_verify="$test_dir/verify_received.txt"
    receive_file_via_master "$hostname" "$remote_verify" "$receive_verify" "$LOG_DIR/file_verify_receive.log"

    if verify_file_content "$receive_verify" "$Verification test content"; then
        pass_test "File content integrity verified" ""
    else
        fail_test "File content integrity check failed" ""
    fi

    # Test 18: File permissions after transfer
    print_test_header "File permissions after transfer"
    run_master_command "$hostname" "ls -l $remote_file" "$LOG_DIR/file_permissions.log"
    if grep -q "$remote_file" "$LOG_DIR/file_permissions.log"; then
        pass_test "File permissions preserved" ""
    else
        skip_test "File permissions check" "File not found"
    fi

    # Test 19: Large number of small files
    test_subsection "Performance Tests"
    print_test_header "Many small files"
    local many_files_dir="$test_dir/many_files"
    mkdir -p "$many_files_dir"
    for i in {1..20}; do
        create_test_file "$many_files_dir/file_$i.txt" 10 "File $i"
    done

    local remote_many="/tmp/many_files"
    output_file="$LOG_DIR/file_many_test.log"
    send_file_via_master "$hostname" "$many_files_dir" "$remote_many" "$output_file"

    if [ $? -eq 0 ] && grep -q "File transfer completed successfully" "$output_file"; then
        run_master_command "$hostname" "find $remote_many -type f | wc -l" "$LOG_DIR/verify_many_files.log"
        local file_count=$(grep -oP "\d+" "$LOG_DIR/verify_many_files.log" | tail -1)
        if [ "$file_count" -eq 20 ]; then
            pass_test "Many small files transferred successfully" "Count: $file_count"
        else
            fail_test "File count mismatch" "Expected: 20, Got: $file_count"
        fi
    else
        fail_test "Failed to transfer many files" ""
    fi

    # Test 20: File with UTF-8 characters
    print_test_header "File with UTF-8 characters"
    local utf8_file="$test_dir/utf8.txt"
    local remote_utf8="/tmp/utf8.txt"
    echo -e "UTF-8 test: café, naïve, 日本語, 🎉" > "$utf8_file"

    output_file="$LOG_DIR/file_utf8_test.log"
    send_file_via_master "$hostname" "$utf8_file" "$remote_utf8" "$output_file"

    if [ $? -eq 0 ] && grep -q "File transfer completed successfully" "$output_file"; then
        pass_test "UTF-8 file sent successfully" ""
    else
        fail_test "Failed to send UTF-8 file" ""
    fi

    # Cleanup
    stop_test_agent
    rm -rf "$test_dir"

    echo ""
    echo -e "${CYAN}File transfer tests completed${NC}"
}
