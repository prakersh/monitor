#!/bin/bash
# Build and Installation Tests

run_build_tests() {
    test_section "BUILD & INSTALLATION TESTS"

    # Test 1: Check if binaries exist
    test_subsection "Binary Existence"
    print_test_header "Check Binaries Exist"

    if check_binaries; then
        pass_test "Binaries exist" "agent, master, monitor, monitor.service found"
    else
        fail_test "Binaries missing" "Run ./build.sh first"
        return 1
    fi

    # Test 2: Verify binary permissions
    test_subsection "Binary Permissions"
    print_test_header "Binary Permissions"

    local all_executable=true
    for binary in agent master monitor; do
        if [ -x "$OUT_DIR/$binary" ]; then
            pass_test "$binary is executable" ""
        else
            fail_test "$binary is not executable" ""
            all_executable=false
        fi
    done

    if [ "$all_executable" = true ]; then
        pass_test "All binaries are executable" ""
    fi

    # Test 3: Verify monitor.service exists
    print_test_header "Service File Exists"
    if [ -f "$OUT_DIR/monitor.service" ]; then
        pass_test "monitor.service exists" ""
    else
        fail_test "monitor.service missing" ""
    fi

    # Test 4: Verify static linking
    print_test_header "Static Linking Check"
    local static_check=true
    for binary in agent master; do
        if ldd "$OUT_DIR/$binary" 2>&1 | grep -q "not a dynamic executable"; then
            pass_test "$binary is statically linked" ""
        else
            # Check for dynamic libraries (this is expected for some system libs)
            local dynamic_libs=$(ldd "$OUT_DIR/$binary" 2>/dev/null | grep -c "=> /" || true)
            if [ "$dynamic_libs" -eq 0 ]; then
                pass_test "$binary is statically linked" ""
            else
                skip_test "$binary dynamic linking check" "Binary uses dynamic libraries"
            fi
        fi
    done

    # Test 5: Verify version embedding
    print_test_header "Version Embedding"
    local version_output=$(sudo "$OUT_DIR/agent" -v 2>&1)
    if echo "$version_output" | grep -q "Monitor Agent version:"; then
        pass_test "Agent version output correct" "$version_output"
    else
        fail_test "Agent version output incorrect" "$version_output"
    fi

    version_output=$(sudo "$OUT_DIR/master" -v 2>&1)
    if echo "$version_output" | grep -q "Monitor Master version:"; then
        pass_test "Master version output correct" "$version_output"
    else
        fail_test "Master version output incorrect" "$version_output"
    fi

    # Test 6: Verify installer version
    print_test_header "Installer Version"
    version_output=$(sudo "$OUT_DIR/monitor" -v 2>&1)
    if echo "$version_output" | grep -q "Monitor Installer version:"; then
        pass_test "Installer version output correct" "$version_output"
    else
        fail_test "Installer version output incorrect" "$version_output"
    fi

    # Test 7: Check for Redis++ dependency
    print_test_header "Redis++ Dependency Check"
    if [ -d "/usr/local/include/sw/redis++" ]; then
        pass_test "Redis++ headers found" ""
    else
        skip_test "Redis++ headers" "Redis++ may not be installed"
    fi

    # Test 8: Check hiredis dependency
    print_test_header "Hiredis Dependency Check"
    if [ -f "/usr/include/hiredis/hiredis.h" ] || [ -f "/usr/local/include/hiredis/hiredis.h" ]; then
        pass_test "Hiredis headers found" ""
    else
        skip_test "Hiredis headers" "Hiredis may not be installed"
    fi

    # Test 9: Verify .last_version file
    print_test_header "Version File Check"
    if [ -f "$BUILD_DIR/.last_version" ]; then
        local version=$(cat "$BUILD_DIR/.last_version")
        pass_test ".last_version exists" "Version: $version"
    else
        skip_test ".last_version file" "File not found"
    fi

    # Test 10: Check file sizes
    print_test_header "Binary File Sizes"
    for binary in agent master monitor; do
        if [ -f "$OUT_DIR/$binary" ]; then
            local size=$(stat -c%s "$OUT_DIR/$binary")
            if [ "$size" -gt 1000000 ]; then  # At least 1MB
                pass_test "$binary size: $size bytes" ""
            else
                fail_test "$binary size too small: $size bytes" ""
            fi
        fi
    done

    # Test 11: Verify service file content
    print_test_header "Service File Content"
    if grep -q "Description=Remote System Management Agent" "$OUT_DIR/monitor.service"; then
        pass_test "Service file has correct description" ""
    else
        fail_test "Service file description incorrect" ""
    fi

    if grep -q "ExecStart=/etc/monitor/agent" "$OUT_DIR/monitor.service"; then
        pass_test "Service file has correct ExecStart" ""
    else
        fail_test "Service file ExecStart incorrect" ""
    fi

    # Test 12: Check for placeholder replacement
    print_test_header "Placeholder Replacement"
    local has_placeholder=false
    for binary in agent master; do
        if strings "$OUT_DIR/$binary" | grep -q "REDIS_HOST_PLACEHOLDER"; then
            has_placeholder=true
            fail_test "$binary still has REDIS_HOST_PLACEHOLDER" ""
        fi
        if strings "$OUT_DIR/$binary" | grep -q "REDIS_PASS_PLACEHOLDER"; then
            has_placeholder=true
            fail_test "$binary still has REDIS_PASS_PLACEHOLDER" ""
        fi
    done

    if [ "$has_placeholder" = false ]; then
        pass_test "All placeholders replaced correctly" ""
    fi

    # Test 13: Verify installer payload
    print_test_header "Installer Payload"
    if strings "$OUT_DIR/monitor" | grep -q "__PAYLOAD_FOLLOWS__"; then
        pass_test "Installer has payload marker" ""
    else
        fail_test "Installer missing payload marker" ""
    fi

    # Test 14: Check for required system commands
    print_test_header "Required System Commands"
    local required_commands="tar dd stat strings ldd"
    local all_found=true
    for cmd in $required_commands; do
        if command -v "$cmd" &> /dev/null; then
            pass_test "$cmd command found" ""
        else
            fail_test "$cmd command not found" ""
            all_found=false
        fi
    done

    # Test 15: Verify log directory permissions
    print_test_header "Log Directory Permissions"
    if [ -d "/var/log" ]; then
        if [ -w "/var/log" ]; then
            pass_test "/var/log is writable" ""
        else
            skip_test "/var/log write check" "Requires root/sudo"
        fi
    fi

    echo ""
    echo -e "${CYAN}Build tests completed${NC}"
}
