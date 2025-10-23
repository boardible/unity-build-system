#!/bin/bash

# ============================================================================
# Boardible TDD Test Setup
# Sets up standalone test project for fast TDD workflow
# ============================================================================

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Project paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$PROJECT_ROOT/Tests"

echo -e "${BLUE}🔧 Setting up Boardible TDD Test Suite...${NC}"
echo ""

# Step 1: Check .NET SDK
echo -e "${BLUE}1/5 Checking .NET SDK...${NC}"
if ! command -v dotnet &> /dev/null; then
    echo -e "${YELLOW}⚠️  .NET SDK not found${NC}"
    echo "Install from: https://dotnet.microsoft.com/download"
    exit 1
fi
DOTNET_VERSION=$(dotnet --version)
echo -e "${GREEN}✅ .NET SDK $DOTNET_VERSION found${NC}"
echo ""

# Step 2: Restore test project dependencies
echo -e "${BLUE}2/5 Restoring NuGet packages...${NC}"
cd "$TEST_DIR"
dotnet restore
echo -e "${GREEN}✅ Packages restored${NC}"
echo ""

# Step 3: Build test project
echo -e "${BLUE}3/5 Building test project...${NC}"
dotnet build --no-restore
echo -e "${GREEN}✅ Test project built${NC}"
echo ""

# Step 4: Install dotnet tools
echo -e "${BLUE}4/5 Installing dotnet tools...${NC}"

# Coverage report generator
if ! command -v reportgenerator &> /dev/null; then
    echo "Installing reportgenerator..."
    dotnet tool install -g dotnet-reportgenerator-globaltool
    echo -e "${GREEN}✅ reportgenerator installed${NC}"
else
    echo -e "${GREEN}✅ reportgenerator already installed${NC}"
fi
echo ""

# Step 5: VS Code integration
echo -e "${BLUE}5/5 Setting up VS Code integration...${NC}"

VSCODE_DIR="$PROJECT_ROOT/.vscode"
SETTINGS_FILE="$VSCODE_DIR/settings.json"

if [ ! -f "$SETTINGS_FILE" ]; then
    mkdir -p "$VSCODE_DIR"
    cat > "$SETTINGS_FILE" <<EOF
{
  "dotnet-test-explorer.testProjectPath": "Tests",
  "dotnet-test-explorer.autoWatch": true,
  "dotnet-test-explorer.showCodeLens": true,
  "dotnet.test.defaultCoverage": true
}
EOF
    echo -e "${GREEN}✅ VS Code settings created${NC}"
else
    echo -e "${YELLOW}⚠️  VS Code settings already exist (not overwriting)${NC}"
fi

# Create VS Code tasks
TASKS_FILE="$VSCODE_DIR/tasks.json"
if [ ! -f "$TASKS_FILE" ]; then
    cat > "$TASKS_FILE" <<EOF
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Run All Tests",
      "type": "shell",
      "command": "./Scripts/run-tests.sh",
      "group": {
        "kind": "test",
        "isDefault": true
      },
      "presentation": {
        "reveal": "always",
        "panel": "new"
      }
    },
    {
      "label": "Run Tests (Watch Mode)",
      "type": "shell",
      "command": "./Scripts/run-tests.sh --watch",
      "group": "test",
      "presentation": {
        "reveal": "always",
        "panel": "new"
      },
      "isBackground": true
    },
    {
      "label": "Run Tests with Coverage",
      "type": "shell",
      "command": "./Scripts/run-tests.sh --coverage",
      "group": "test",
      "presentation": {
        "reveal": "always",
        "panel": "new"
      }
    }
  ]
}
EOF
    echo -e "${GREEN}✅ VS Code tasks created${NC}"
else
    echo -e "${YELLOW}⚠️  VS Code tasks already exist (not overwriting)${NC}"
fi

echo ""
echo -e "${GREEN}✅ Test suite setup complete!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Run tests: ./Scripts/run-tests.sh"
echo "2. Watch mode: ./Scripts/run-tests.sh --watch"
echo "3. VS Code: Cmd+Shift+P → 'Tasks: Run Test Task'"
echo ""
echo -e "${YELLOW}Recommended VS Code Extension:${NC}"
echo "code --install-extension formulahendry.dotnet-test-explorer"
