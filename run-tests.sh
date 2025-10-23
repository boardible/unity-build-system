#!/bin/bash

# ============================================================================
# Boardible Fast TDD Test Runner
# Runs unit tests outside Unity for rapid feedback
# ============================================================================

set -e  # Exit on error

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$PROJECT_ROOT/Tests"

# Default values
FILTER=""
WATCH=false
COVERAGE=false
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --filter)
            FILTER="$2"
            shift 2
            ;;
        --watch)
            WATCH=true
            shift
            ;;
        --coverage)
            COVERAGE=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            echo "Usage: ./run-tests.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --filter <pattern>    Run only tests matching pattern"
            echo "  --watch               Watch mode (auto-run on file changes)"
            echo "  --coverage            Generate code coverage report"
            echo "  --verbose             Detailed test output"
            echo "  --help                Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./run-tests.sh                              # Run all tests"
            echo "  ./run-tests.sh --filter DataLayerTests     # Run specific test class"
            echo "  ./run-tests.sh --watch                      # TDD watch mode"
            echo "  ./run-tests.sh --coverage                   # With coverage report"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Check if test project exists
if [ ! -f "$TEST_DIR/Boardible.Tests.csproj" ]; then
    echo -e "${RED}❌ Test project not found at: $TEST_DIR${NC}"
    echo -e "${YELLOW}Run setup first: ./Scripts/setup-tests.sh${NC}"
    exit 1
fi

# Check .NET SDK
if ! command -v dotnet &> /dev/null; then
    echo -e "${RED}❌ .NET SDK not found${NC}"
    echo -e "${YELLOW}Install from: https://dotnet.microsoft.com/download${NC}"
    exit 1
fi

# Verify .NET version
REQUIRED_VERSION="7.0"
CURRENT_VERSION=$(dotnet --version | cut -d. -f1,2)
if [ "$CURRENT_VERSION" != "$REQUIRED_VERSION" ]; then
    echo -e "${YELLOW}⚠️  Warning: Expected .NET $REQUIRED_VERSION, found $CURRENT_VERSION${NC}"
fi

# Change to test directory
cd "$TEST_DIR"

# Build test command
TEST_CMD="dotnet test"

if [ "$WATCH" = true ]; then
    TEST_CMD="dotnet watch test"
fi

if [ -n "$FILTER" ]; then
    TEST_CMD="$TEST_CMD --filter \"FullyQualifiedName~$FILTER\""
fi

if [ "$COVERAGE" = true ]; then
    TEST_CMD="$TEST_CMD --collect:\"XPlat Code Coverage\" --results-directory ./coverage"
fi

if [ "$VERBOSE" = true ]; then
    TEST_CMD="$TEST_CMD --logger \"console;verbosity=detailed\""
else
    TEST_CMD="$TEST_CMD --logger \"console;verbosity=normal\""
fi

# Run tests
echo -e "${BLUE}🧪 Running Boardible TDD Tests...${NC}"
echo -e "${BLUE}Command: $TEST_CMD${NC}"
echo ""

eval $TEST_CMD
EXIT_CODE=$?

# Handle coverage report
if [ "$COVERAGE" = true ] && [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo -e "${BLUE}📊 Generating coverage report...${NC}"
    
    # Check if reportgenerator is installed
    if ! command -v reportgenerator &> /dev/null; then
        echo -e "${YELLOW}Installing reportgenerator...${NC}"
        dotnet tool install -g dotnet-reportgenerator-globaltool
    fi
    
    # Generate HTML report
    reportgenerator \
        -reports:"coverage/**/coverage.cobertura.xml" \
        -targetdir:"coverage/html" \
        -reporttypes:"Html;TextSummary"
    
    # Show summary
    echo ""
    cat coverage/html/Summary.txt
    echo ""
    echo -e "${GREEN}✅ Coverage report: file://$TEST_DIR/coverage/html/index.html${NC}"
fi

# Exit with test exit code
if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ All tests passed!${NC}"
else
    echo ""
    echo -e "${RED}❌ Tests failed!${NC}"
fi

exit $EXIT_CODE
