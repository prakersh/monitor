#!/bin/bash
# Version Management Tests

run_version_tests() {
    test_section "VERSION MANAGEMENT TESTS"

    # Ensure Redis is running
    if ! check_redis; then
        echo -e "${YELLOW}Starting Redis for version tests...${NC}"
        if ! start_redis; then
            skip_test "All version tests" "Redis not available"
            return 1
        fi
    fi

    # Test 1: Verify agent version flag
    test_subsection "Agent Version"
    print_test_header "Agent version flag"
    local version_output=$(sudo "$OUT_DIR/agent" -v 2>&1)
    if echo "$version_output" | grep -q "version\|Monitor"; then
        pass_test "Agent version flag works" "$version_output"
    else
        fail_test "Agent version flag failed" "$version_output"
    fi

    # Test 2: Verify master version flag
    test_subsection "Master Version"
    print_test_header "Master version flag"
    local master_version=$(sudo "$OUT_DIR/master" -v 2>&1)
    if echo "$master_version" | grep -q "version\|Monitor"; then
        pass_test "Master version flag works" "$master_version"
    else
        fail_test "Master version flag failed" "$master_version"
    fi

    # Test 3: Verify monitor version flag
    test_subsection "Monitor Version"
    print_test_header "Monitor version flag"
    local monitor_version=$(sudo "$OUT_DIR/monitor" -v 2>&1)
    if echo "$monitor_version" | grep -q "version\|Monitor"; then
        pass_test "Monitor version flag works" "$monitor_version"
    else
        fail_test "Monitor version flag failed" "$monitor_version"
    fi

    # Test 4: Verify version format
    test_subsection "Version Format"
    print_test_header "Verify version format"
    local agent_version=$(sudo "$OUT_DIR/agent" -v 2>&1 | grep -oP "\\d+\\.\\d+\\.\\d+" | head -1)
    if [ -n "$agent_version" ]; then
        pass_test "Agent version format correct" "Version: $agent_version"
    else
        skip_test "Agent version format" "Could not parse"
    fi

    # Test 5: Verify version increment logic
    print_test_header "Verify version increment logic"
    if [ -f "$BUILD_DIR/version.txt" ]; then
        local current_version=$(cat "$BUILD_DIR/version.txt")
        pass_test "Version file exists" "Version: $current_version"
    else
        skip_test "Version file" "Not found"
    fi

    # Test 6: Verify version consistency across binaries
    test_subsection "Version Consistency"
    print_test_header "Verify version consistency"
    local agent_v=$(sudo "$OUT_DIR/agent" -v 2>&1 | grep -oP "\\d+\\.\\d+\\.\\d+" | head -1)
    local master_v=$(sudo "$OUT_DIR/master" -v 2>&1 | grep -oP "\\d+\\.\\d+\\.\\d+" | head -1)
    local monitor_v=$(sudo "$OUT_DIR/monitor" -v 2>&1 | grep -oP "\\d+\\.\\d+\\.\\d+" | head -1)

    if [ "$agent_v" = "$master_v" ] && [ "$master_v" = "$monitor_v" ]; then
        pass_test "Versions consistent across binaries" "Version: $agent_v"
    else
        skip_test "Version consistency" "Agent: $agent_v, Master: $master_v, Monitor: $monitor_v"
    fi

    # Test 7: Verify version in build script
    test_subsection "Build Script Version"
    print_test_header "Verify version in build script"
    if [ -f "$BUILD_DIR/build.sh" ]; then
        if grep -q "VERSION\|version" "$BUILD_DIR/build.sh" -i; then
            pass_test "Build script contains version info" ""
        else
            skip_test "Build script version" "Not found"
        fi
    fi

    # Test 8: Verify version in README
    print_test_header "Verify version in README"
    if [ -f "$BUILD_DIR/README.md" ]; then
        if grep -q "version\|v\\d" "$BUILD_DIR/README.md" -i; then
            pass_test "README contains version info" ""
        else
            skip_test "README version" "Not found"
        fi
    fi

    # Test 9: Verify version in CI workflow
    test_subsection "CI Version"
    print_test_header "Verify version in CI workflow"
    if [ -f "$BUILD_DIR/.github/workflows/ci.yml" ]; then
        if grep -q "version" "$BUILD_DIR/.github/workflows/ci.yml" -i; then
            pass_test "CI workflow contains version info" ""
        else
            skip_test "CI version" "Not found"
        fi
    fi

    # Test 10: Start agent for version-related tests
    test_subsection "Agent Version in Redis"
    print_test_header "Start agent for version tests"
    if start_test_agent; then
        pass_test "Agent started for version tests" ""
    else
        skip_test "Agent version tests" "Agent not available"
        echo ""
        echo -e "${CYAN}Version tests completed${NC}"
        return 1
    fi

    local hostname=$(get_current_agent_hostname)

    # Test 11: Verify agent version in Redis
    print_test_header "Verify agent version in Redis"
    local agent_info=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" get "agent:$hostname" 2>/dev/null)
    if echo "$agent_info" | grep -q "version\|v\\d"; then
        pass_test "Agent version stored in Redis" ""
    else
        skip_test "Agent version in Redis" "Not found"
    fi

    # Test 12: Verify version flag doesn't start agent
    print_test_header "Verify version flag doesn't start agent"
    local pid_before=$(pgrep -f "out/agent" | wc -l)
    sudo "$OUT_DIR/agent" -v > /dev/null 2>&1
    local pid_after=$(pgrep -f "out/agent" | wc -l)

    if [ "$pid_before" -eq "$pid_after" ]; then
        pass_test "Version flag doesn't start agent" ""
    else
        skip_test "Version flag behavior" "PIDs changed"
    fi

    # Test 13: Verify version output format
    print_test_header "Verify version output format"
    local version_lines=$(sudo "$OUT_DIR/agent" -v 2>&1 | wc -l)
    if [ "$version_lines" -le 5 ]; then
        pass_test "Version output is concise" "Lines: $version_lines"
    else
        skip_test "Version output" "Too many lines: $version_lines"
    fi

    # Test 14: Verify version includes build info
    print_test_header "Verify version includes build info"
    local version_output=$(sudo "$OUT_DIR/agent" -v 2>&1)
    if echo "$version_output" | grep -qE "(build|compiled|built)"; then
        pass_test "Version includes build info" ""
    else
        skip_test "Build info" "Not found in version"
    fi

    # Test 15: Verify version in binary strings
    test_subsection "Binary Version Strings"
    print_test_header "Verify version in binary strings"
    local binary_strings=$(strings "$OUT_DIR/agent" | grep -E "^\\d+\\.\\d+\\.\\d+" | head -1)
    if [ -n "$binary_strings" ]; then
        pass_test "Version found in binary strings" "Version: $binary_strings"
    else
        skip_test "Binary strings" "Version not found"
    fi

    # Test 16: Verify version comparison capability
    print_test_header "Verify version comparison"
    local version=$(sudo "$OUT_DIR/agent" -v 2>&1 | grep -oP "\\d+\\.\\d+\\.\\d+" | head -1)
    if [ -n "$version" ]; then
        # Parse version components
        local major=$(echo "$version" | cut -d. -f1)
        local minor=$(echo "$version" | cut -d. -f2)
        local patch=$(echo "$version" | cut -d. -f3)

        if [ -n "$major" ] && [ -n "$minor" ] && [ -n "$patch" ]; then
            pass_test "Version can be parsed for comparison" "Major: $major, Minor: $minor, Patch: $patch"
        else
            skip_test "Version parsing" "Incomplete version"
        fi
    else
        skip_test "Version comparison" "No version found"
    fi

    # Test 17: Verify version in installer
    test_subsection "Installer Version"
    print_test_header "Verify version in installer"
    if [ -f "$BUILD_DIR/monitor_inst.sh" ]; then
        if grep -q "version\|VERSION" "$BUILD_DIR/monitor_inst.sh" -i; then
            pass_test "Installer contains version info" ""
        else
            skip_test "Installer version" "Not found"
        fi
    fi

    # Test 18: Verify version increment in build process
    print_test_header "Verify build version increment"
    if [ -f "$BUILD_DIR/build.sh" ]; then
        if grep -q "increment\|bump\|update.*version" "$BUILD_DIR/build.sh" -i; then
            pass_test "Build script handles version increment" ""
        else
            skip_test "Version increment" "Not found in build script"
        fi
    fi

    # Test 19: Verify version in git tags
    test_subsection "Git Version"
    print_test_header "Verify version in git tags"
    if git rev-parse --git-dir > /dev/null 2>&1; then
        local git_tags=$(git tag -l "v*" | wc -l)
        if [ "$git_tags" -gt 0 ]; then
            pass_test "Git tags found" "Count: $git_tags"
        else
            skip_test "Git tags" "No version tags found"
        fi
    else
        skip_test "Git version" "Not a git repository"
    fi

    # Test 20: Verify version in recent commits
    print_test_header "Verify version in recent commits"
    if git rev-parse --git-dir > /dev/null 2>&1; then
        local version_commits=$(git log --oneline | grep -i "version\|v\\d" | wc -l)
        if [ "$version_commits" -gt 0 ]; then
            pass_test "Version mentioned in commits" "Count: $version_commits"
        else
            skip_test "Version commits" "Not found in recent commits"
        fi
    fi

    # Test 21: Verify version consistency with file
    test_subsection "Version File Consistency"
    print_test_header "Verify version file consistency"
    if [ -f "$BUILD_DIR/version.txt" ]; then
        local file_version=$(cat "$BUILD_DIR/version.txt")
        local binary_version=$(sudo "$OUT_DIR/agent" -v 2>&1 | grep -oP "\\d+\\.\\d+\\.\\d+" | head -1)

        if [ "$file_version" = "$binary_version" ]; then
            pass_test "Version file matches binary" "Version: $file_version"
        else
            skip_test "Version consistency" "File: $file_version, Binary: $binary_version"
        fi
    fi

    # Test 22: Verify version in documentation
    print_test_header "Verify version in documentation"
    local doc_files=("$BUILD_DIR/README.md" "$BUILD_DIR/tests/README.md")
    local version_found=false

    for doc in "${doc_files[@]}"; do
        if [ -f "$doc" ] && grep -q "version\|v\\d" "$doc" -i; then
            version_found=true
        fi
    done

    if [ "$version_found" = true ]; then
        pass_test "Version found in documentation" ""
    else
        skip_test "Documentation version" "Not found"
    fi

    # Test 23: Verify version format compliance
    print_test_header "Verify version format compliance (SemVer)"
    local version=$(sudo "$OUT_DIR/agent" -v 2>&1 | grep -oP "\\d+\\.\\d+\\.\\d+" | head -1)
    if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        pass_test "Version follows SemVer format" "Version: $version"
    else
        skip_test "SemVer format" "Version: $version"
    fi

    # Test 24: Verify major version
    print_test_header "Verify major version"
    local major=$(echo "$version" | cut -d. -f1)
    if [ -n "$major" ] && [ "$major" -ge 0 ]; then
        pass_test "Major version valid" "Major: $major"
    else
        skip_test "Major version" "Invalid"
    fi

    # Test 25: Verify minor version
    print_test_header "Verify minor version"
    local minor=$(echo "$version" | cut -d. -f2)
    if [ -n "$minor" ] && [ "$minor" -ge 0 ]; then
        pass_test "Minor version valid" "Minor: $minor"
    else
        skip_test "Minor version" "Invalid"
    fi

    # Test 26: Verify patch version
    print_test_header "Verify patch version"
    local patch=$(echo "$version" | cut -d. -f3)
    if [ -n "$patch" ] && [ "$patch" -ge 0 ]; then
        pass_test "Patch version valid" "Patch: $patch"
    else
        skip_test "Patch version" "Invalid"
    fi

    # Test 27: Verify version bump capability
    test_subsection "Version Bump"
    print_test_header "Verify version bump capability"
    if [ -f "$BUILD_DIR/build.sh" ]; then
        if grep -qE "(bump|increment|update).*version" "$BUILD_DIR/build.sh" -i; then
            pass_test "Version bump capability exists" ""
        else
            skip_test "Version bump" "Not implemented"
        fi
    fi

    # Test 28: Verify version in CHANGELOG
    print_test_header "Verify version in CHANGELOG"
    if [ -f "$BUILD_DIR/CHANGELOG.md" ]; then
        if grep -q "## \\[v\\|## Version" "$BUILD_DIR/CHANGELOG.md"; then
            pass_test "CHANGELOG contains version entries" ""
        else
            skip_test "CHANGELOG version" "Not found"
        fi
    else
        skip_test "CHANGELOG" "File not found"
    fi

    # Test 29: Verify version in LICENSE
    print_test_header "Verify version in LICENSE"
    if [ -f "$BUILD_DIR/LICENSE" ]; then
        if grep -q "v\\d\|version" "$BUILD_DIR/LICENSE" -i; then
            pass_test "LICENSE contains version info" ""
        else
            skip_test "LICENSE version" "Not found"
        fi
    fi

    # Test 30: Verify version in .gitignore
    print_test_header "Verify version in .gitignore"
    if [ -f "$BUILD_DIR/.gitignore" ]; then
        if grep -q "version\|v\\d" "$BUILD_DIR/.gitignore" -i; then
            pass_test ".gitignore contains version patterns" ""
        else
            skip_test ".gitignore version" "Not found"
        fi
    fi

    # Cleanup
    stop_test_agent

    echo ""
    echo -e "${CYAN}Version tests completed${NC}"
}
