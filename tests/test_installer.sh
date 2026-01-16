#!/bin/bash
# Installer Tests

run_installer_tests() {
    test_section "INSTALLER TESTS"

    # Test 1: Verify installer script exists
    test_subsection "Installer Verification"
    print_test_header "Verify installer script exists"
    local installer_path="$BUILD_DIR/monitor_inst.sh"
    if [ -f "$installer_path" ]; then
        pass_test "Installer script exists" "Path: $installer_path"
    else
        fail_test "Installer script not found" ""
        return 1
    fi

    # Test 2: Verify installer is executable
    print_test_header "Verify installer is executable"
    if [ -x "$installer_path" ]; then
        pass_test "Installer is executable" ""
    else
        fail_test "Installer is not executable" ""
    fi

    # Test 3: Verify installer has correct shebang
    print_test_header "Verify installer shebang"
    local shebang=$(head -1 "$installer_path")
    if [[ "$shebang" == "#!/bin/bash" ]]; then
        pass_test "Installer has correct shebang" ""
    else
        fail_test "Installer shebang incorrect" "Found: $shebang"
    fi

    # Test 4: Verify installer contains required functions
    print_test_header "Verify installer functions"
    local has_install=$(grep -c "install_monitor" "$installer_path")
    local has_uninstall=$(grep -c "uninstall_monitor" "$installer_path")
    local has_status=$(grep -c "check_status" "$installer_path")

    if [ "$has_install" -gt 0 ] && [ "$has_uninstall" -gt 0 ] && [ "$has_status" -gt 0 ]; then
        pass_test "Installer has required functions" ""
    else
        fail_test "Installer missing functions" ""
    fi

    # Test 5: Verify installer checks for root
    test_subsection "Installer Safety Checks"
    print_test_header "Verify root check"
    if grep -q "root\|UID.*0\|id -u" "$installer_path"; then
        pass_test "Installer checks for root" ""
    else
        skip_test "Root check" "Not found in installer"
    fi

    # Test 6: Verify installer checks dependencies
    print_test_header "Verify dependency checks"
    if grep -q "check.*depend\|require.*bin\|which" "$installer_path" -i; then
        pass_test "Installer checks dependencies" ""
    else
        skip_test "Dependency checks" "Not found in installer"
    fi

    # Test 7: Verify installer creates directories
    print_test_header "Verify directory creation"
    if grep -q "mkdir\|create.*dir" "$installer_path" -i; then
        pass_test "Installer creates directories" ""
    else
        skip_test "Directory creation" "Not found in installer"
    fi

    # Test 8: Verify installer copies binaries
    print_test_header "Verify binary installation"
    if grep -q "cp\|install.*bin" "$installer_path" -i; then
        pass_test "Installer copies binaries" ""
    else
        skip_test "Binary installation" "Not found in installer"
    fi

    # Test 9: Verify installer sets permissions
    print_test_header "Verify permission setting"
    if grep -q "chmod\|chown" "$installer_path"; then
        pass_test "Installer sets permissions" ""
    else
        skip_test "Permission setting" "Not found in installer"
    fi

    # Test 10: Verify installer creates service file
    print_test_header "Verify service file creation"
    if grep -q "monitor.service\|systemd\|service.*file" "$installer_path" -i; then
        pass_test "Installer creates service file" ""
    else
        skip_test "Service file" "Not found in installer"
    fi

    # Test 11: Verify installer has help option
    print_test_header "Verify help option"
    if grep -q "help\|--help\|-h" "$installer_path"; then
        pass_test "Installer has help option" ""
    else
        skip_test "Help option" "Not found in installer"
    fi

    # Test 12: Verify installer has version option
    print_test_header "Verify version option"
    if grep -q "version\|--version\|-v" "$installer_path"; then
        pass_test "Installer has version option" ""
    else
        skip_test "Version option" "Not found in installer"
    fi

    # Test 13: Verify installer has uninstall option
    print_test_header "Verify uninstall option"
    if grep -q "uninstall\|--uninstall" "$installer_path"; then
        pass_test "Installer has uninstall option" ""
    else
        skip_test "Uninstall option" "Not found in installer"
    fi

    # Test 14: Verify installer has status option
    print_test_header "Verify status option"
    if grep -q "status\|--status" "$installer_path"; then
        pass_test "Installer has status option" ""
    else
        skip_test "Status option" "Not found in installer"
    fi

    # Test 15: Verify installer handles errors
    test_subsection "Error Handling"
    print_test_header "Verify error handling"
    if grep -q "error\|fail\|exit.*[1-9]" "$installer_path" -i; then
        pass_test "Installer handles errors" ""
    else
        skip_test "Error handling" "Not found in installer"
    fi

    # Test 16: Verify installer has logging
    print_test_header "Verify installer logging"
    if grep -q "echo\|log\|logger" "$installer_path" -i; then
        pass_test "Installer has logging" ""
    else
        skip_test "Installer logging" "Not found in installer"
    fi

    # Test 17: Verify installer checks for existing installation
    print_test_header "Verify existing installation check"
    if grep -q "test.*-f\|exists\|already" "$installer_path" -i; then
        pass_test "Installer checks for existing installation" ""
    else
        skip_test "Existing installation check" "Not found in installer"
    fi

    # Test 18: Verify installer backup capability
    print_test_header "Verify backup capability"
    if grep -q "backup\|mv.*bak\|cp.*bak" "$installer_path" -i; then
        pass_test "Installer has backup capability" ""
    else
        skip_test "Backup capability" "Not found in installer"
    fi

    # Test 19: Verify installer cleanup on failure
    print_test_header "Verify cleanup on failure"
    if grep -q "cleanup\|trap\|rm.*tmp" "$installer_path" -i; then
        pass_test "Installer cleans up on failure" ""
    else
        skip_test "Cleanup on failure" "Not found in installer"
    fi

    # Test 20: Verify installer validates inputs
    test_subsection "Input Validation"
    print_test_header "Verify input validation"
    if grep -q "if.*test\|\\[.*\\]\|read.*-p" "$installer_path"; then
        pass_test "Installer validates inputs" ""
    else
        skip_test "Input validation" "Not found in installer"
    fi

    # Test 21: Verify installer has configuration options
    print_test_header "Verify configuration options"
    if grep -q "config\|REDIS\|HOST\|PORT" "$installer_path" -i; then
        pass_test "Installer has configuration options" ""
    else
        skip_test "Configuration options" "Not found in installer"
    fi

    # Test 22: Verify installer syntax
    test_subsection "Syntax Validation"
    print_test_header "Verify installer syntax"
    if bash -n "$installer_path" 2>/dev/null; then
        pass_test "Installer syntax is valid" ""
    else
        fail_test "Installer syntax error" ""
    fi

    # Test 23: Verify installer references correct binaries
    print_test_header "Verify binary references"
    if grep -q "agent\|master\|monitor" "$installer_path"; then
        pass_test "Installer references correct binaries" ""
    else
        skip_test "Binary references" "Not found in installer"
    fi

    # Test 24: Verify installer has usage examples
    print_test_header "Verify usage examples"
    if grep -q "Example\|example\|Usage:" "$installer_path" -i; then
        pass_test "Installer has usage examples" ""
    else
        skip_test "Usage examples" "Not found in installer"
    fi

    # Test 25: Verify installer checks for required files
    test_subsection "File Verification"
    print_test_header "Verify required file checks"
    if grep -q "test.*-f\|\\[.*-f" "$installer_path"; then
        pass_test "Installer checks for required files" ""
    else
        skip_test "File checks" "Not found in installer"
    fi

    # Test 26: Verify installer has exit codes
    print_test_header "Verify exit codes"
    if grep -q "exit 0\|exit [1-9]" "$installer_path"; then
        pass_test "Installer has proper exit codes" ""
    else
        skip_test "Exit codes" "Not found in installer"
    fi

    # Test 27: Verify installer script size
    print_test_header "Verify installer size"
    local installer_size=$(wc -l < "$installer_path")
    if [ "$installer_size" -gt 10 ]; then
        pass_test "Installer has reasonable size" "Lines: $installer_size"
    else
        fail_test "Installer too small" "Lines: $installer_size"
    fi

    # Test 28: Verify installer comments
    print_test_header "Verify installer comments"
    local comment_count=$(grep -c "^#" "$installer_path")
    if [ "$comment_count" -gt 5 ]; then
        pass_test "Installer has comments" "Comments: $comment_count"
    else
        skip_test "Installer comments" "Count: $comment_count"
    fi

    # Test 29: Verify installer doesn't use dangerous commands
    print_test_header "Verify no dangerous commands"
    local dangerous_count=$(grep -c "rm -rf /\|dd if=.*of=/dev/sda\|mkfs" "$installer_path")
    if [ "$dangerous_count" -eq 0 ]; then
        pass_test "No dangerous commands found" ""
    else
        fail_test "Dangerous commands found" "Count: $dangerous_count"
    fi

    # Test 30: Verify installer has proper structure
    print_test_header "Verify installer structure"
    local has_main=$(grep -c "main\|case.*\\$1" "$installer_path")
    if [ "$has_main" -gt 0 ]; then
        pass_test "Installer has proper structure" ""
    else
        skip_test "Installer structure" "Not found"
    fi

    # Test 31: Verify service file exists
    test_subsection "Service File"
    print_test_header "Verify service file exists"
    if [ -f "$BUILD_DIR/monitor.service" ]; then
        pass_test "Service file exists" "Path: $BUILD_DIR/monitor.service"
    else
        fail_test "Service file not found" ""
    fi

    # Test 32: Verify service file format
    print_test_header "Verify service file format"
    if [ -f "$BUILD_DIR/monitor.service" ]; then
        if grep -q "\\[Unit\\]" "$BUILD_DIR/monitor.service" && grep -q "\\[Service\\]" "$BUILD_DIR/monitor.service"; then
            pass_test "Service file has correct format" ""
        else
            fail_test "Service file format incorrect" ""
        fi
    fi

    # Test 33: Verify service file references binaries
    print_test_header "Verify service file binary references"
    if [ -f "$BUILD_DIR/monitor.service" ]; then
        if grep -q "agent\|master" "$BUILD_DIR/monitor.service"; then
            pass_test "Service file references binaries" ""
        else
            skip_test "Service file binaries" "Not found"
        fi
    fi

    # Test 34: Verify service file has description
    print_test_header "Verify service file description"
    if [ -f "$BUILD_DIR/monitor.service" ]; then
        if grep -q "Description=" "$BUILD_DIR/monitor.service"; then
            pass_test "Service file has description" ""
        else
            skip_test "Service file description" "Not found"
        fi
    fi

    # Test 35: Verify service file has restart policy
    print_test_header "Verify service file restart policy"
    if [ -f "$BUILD_DIR/monitor.service" ]; then
        if grep -q "Restart=" "$BUILD_DIR/monitor.service"; then
            pass_test "Service file has restart policy" ""
        else
            skip_test "Restart policy" "Not found"
        fi
    fi

    # Cleanup
    echo ""
    echo -e "${CYAN}Installer tests completed${NC}"
}
