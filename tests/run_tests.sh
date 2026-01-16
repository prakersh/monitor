#!/bin/bash
# MONITOR Test Runner
# Runs comprehensive test suite for MONITOR system

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$(dirname "$SCRIPT_DIR")"

# Source the test framework
source "$SCRIPT_DIR/test_framework.sh"

# Test category selection
TEST_CATEGORIES=()

# Parse command line arguments
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --all              Run all tests"
    echo "  --build            Run build tests"
    echo "  --agent            Run agent tests"
    echo "  --master           Run master tests"
    echo "  --command          Run command execution tests"
    echo "  --file             Run file transfer tests"
    echo "  --metrics          Run metrics tests"
    echo "  --process          Run process management tests"
    echo "  --redis            Run Redis communication tests"
    echo "  --logging          Run logging tests"
    echo "  --concurrent       Run concurrent operation tests"
    echo "  --stress           Run stress tests"
    echo "  --security         Run security tests"
    echo "  --recovery         Run recovery tests"
    echo "  --installer        Run installer tests"
    echo "  --version          Run version tests"
    echo "  --quick            Run quick tests (smoke tests)"
    echo "  --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --all           # Run all tests"
    echo "  $0 --quick         # Run quick smoke tests"
    echo "  $0 --agent --master  # Run agent and master tests"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            TEST_CATEGORIES=(all)
            shift
            ;;
        --build)
            TEST_CATEGORIES+=(build)
            shift
            ;;
        --agent)
            TEST_CATEGORIES+=(agent)
            shift
            ;;
        --master)
            TEST_CATEGORIES+=(master)
            shift
            ;;
        --command)
            TEST_CATEGORIES+=(command)
            shift
            ;;
        --file)
            TEST_CATEGORIES+=(file)
            shift
            ;;
        --metrics)
            TEST_CATEGORIES+=(metrics)
            shift
            ;;
        --process)
            TEST_CATEGORIES+=(process)
            shift
            ;;
        --redis)
            TEST_CATEGORIES+=(redis)
            shift
            ;;
        --logging)
            TEST_CATEGORIES+=(logging)
            shift
            ;;
        --concurrent)
            TEST_CATEGORIES+=(concurrent)
            shift
            ;;
        --stress)
            TEST_CATEGORIES+=(stress)
            shift
            ;;
        --security)
            TEST_CATEGORIES+=(security)
            shift
            ;;
        --recovery)
            TEST_CATEGORIES+=(recovery)
            shift
            ;;
        --installer)
            TEST_CATEGORIES+=(installer)
            shift
            ;;
        --version)
            TEST_CATEGORIES+=(version)
            shift
            ;;
        --quick)
            TEST_CATEGORIES=(quick)
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# If no categories specified, default to all
if [ ${#TEST_CATEGORIES[@]} -eq 0 ]; then
    TEST_CATEGORIES=(all)
fi

# Main test execution
main() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         MONITOR Comprehensive Test Suite                  ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Initialize test framework
    init_test_framework

    # Check if we should run all tests
    if [[ " ${TEST_CATEGORIES[@]} " =~ " all " ]]; then
        echo -e "${YELLOW}Running ALL test categories...${NC}"
        TEST_CATEGORIES=(build agent master command file metrics process redis logging concurrent security recovery installer version)
    fi

    # Check if we should run quick tests
    if [[ " ${TEST_CATEGORIES[@]} " =~ " quick " ]]; then
        echo -e "${YELLOW}Running QUICK smoke tests...${NC}"
        TEST_CATEGORIES=(build agent master command)
    fi

    # Run selected test categories
    for category in "${TEST_CATEGORIES[@]}"; do
        case $category in
            build)
                source "$SCRIPT_DIR/test_build.sh"
                run_build_tests
                ;;
            agent)
                source "$SCRIPT_DIR/test_agent.sh"
                run_agent_tests
                ;;
            master)
                source "$SCRIPT_DIR/test_master.sh"
                run_master_tests
                ;;
            command)
                source "$SCRIPT_DIR/test_command.sh"
                run_command_tests
                ;;
            file)
                source "$SCRIPT_DIR/test_file.sh"
                run_file_tests
                ;;
            metrics)
                source "$SCRIPT_DIR/test_metrics.sh"
                run_metrics_tests
                ;;
            process)
                source "$SCRIPT_DIR/test_process.sh"
                run_process_tests
                ;;
            redis)
                source "$SCRIPT_DIR/test_redis.sh"
                run_redis_tests
                ;;
            logging)
                source "$SCRIPT_DIR/test_logging.sh"
                run_logging_tests
                ;;
            concurrent)
                source "$SCRIPT_DIR/test_concurrent.sh"
                run_concurrent_tests
                ;;
            stress)
                source "$SCRIPT_DIR/test_stress.sh"
                run_stress_tests
                ;;
            security)
                source "$SCRIPT_DIR/test_security.sh"
                run_security_tests
                ;;
            recovery)
                source "$SCRIPT_DIR/test_recovery.sh"
                run_recovery_tests
                ;;
            installer)
                source "$SCRIPT_DIR/test_installer.sh"
                run_installer_tests
                ;;
            version)
                source "$SCRIPT_DIR/test_version.sh"
                run_version_tests
                ;;
            *)
                echo -e "${RED}Unknown test category: $category${NC}"
                ;;
        esac
    done

    # Print summary
    print_summary

    # Cleanup
    cleanup_test_framework

    # Exit with appropriate code
    if [ $TESTS_FAILED -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"
