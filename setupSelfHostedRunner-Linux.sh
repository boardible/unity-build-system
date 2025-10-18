#!/bin/bash

# Self-Hosted GitHub Actions Runner Setup for Windows/WSL or Linux (Android Builds Only)
# This script sets up your PC as a GitHub Actions runner for Unity Android builds

set -e

# Configuration
REPO_OWNER="boardible"
REPO_NAME="ineuj"
UNITY_VERSION="6000.2.6f2"
RUNNER_VERSION="2.311.0"
RUNNER_NAME="${RUNNER_NAME:-ineuj-linux-android}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Helper functions
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_info() { echo -e "${CYAN}→ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }

# Show help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    cat << EOF
GitHub Actions Self-Hosted Runner Setup for Linux/WSL (Android Only)
=====================================================================

This script will:
1. Download and install GitHub Actions runner software
2. Configure it to listen for Android build jobs
3. Verify Unity installation for Android builds
4. Set up as a systemd service (optional)

Usage:
    ./setupSelfHostedRunner-Linux.sh [OPTIONS]

Options:
    --token TOKEN        GitHub runner registration token (required)
    --name NAME          Name for this runner (default: ineuj-linux-android)
    --skip-unity-check   Skip Unity installation verification
    --help, -h           Show this help message

Getting a GitHub Token:
    1. Go to: https://github.com/${REPO_OWNER}/${REPO_NAME}/settings/actions/runners/new
    2. Click "New self-hosted runner"
    3. Select "Linux" platform
    4. Copy the token from the configuration command
    5. Run: ./setupSelfHostedRunner-Linux.sh --token "YOUR_TOKEN_HERE"

Example:
    ./setupSelfHostedRunner-Linux.sh --token "ABCD1234EFGH5678" --name "my-android-runner"
EOF
    exit 0
fi

# Parse arguments
SKIP_UNITY_CHECK=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --token)
            GITHUB_TOKEN="$2"
            shift 2
            ;;
        --name)
            RUNNER_NAME="$2"
            shift 2
            ;;
        --skip-unity-check)
            SKIP_UNITY_CHECK=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Run with --help for usage information"
            exit 1
            ;;
    esac
done

print_info "=============================================="
print_info "GitHub Actions Runner Setup - Android Builds"
print_info "=============================================="
echo ""

# Validate GitHub token
if [ -z "$GITHUB_TOKEN" ]; then
    print_error "GitHub token is required!"
    echo ""
    print_info "To get a token:"
    print_info "1. Visit: https://github.com/${REPO_OWNER}/${REPO_NAME}/settings/actions/runners/new"
    print_info "2. Select 'Linux' platform"
    print_info "3. Copy the token from the config command"
    print_info "4. Run: ./setupSelfHostedRunner-Linux.sh --token \"YOUR_TOKEN\""
    echo ""
    exit 1
fi

# Step 1: Create runner directory
print_info "[Step 1/7] Creating runner directory..."
RUNNER_DIR="$HOME/actions-runner"
if [ -d "$RUNNER_DIR" ]; then
    print_warning "Runner directory already exists: $RUNNER_DIR"
    read -p "Do you want to remove it and start fresh? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$RUNNER_DIR"
        print_success "Removed existing runner directory"
    else
        print_error "Aborted. Please remove the directory manually or use a different location."
        exit 1
    fi
fi
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"
print_success "Created runner directory: $RUNNER_DIR"

# Step 2: Download GitHub Actions runner
print_info "[Step 2/7] Downloading GitHub Actions runner..."
RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
RUNNER_TAR="actions-runner.tar.gz"

if ! curl -o "$RUNNER_TAR" -L "$RUNNER_URL"; then
    print_error "Failed to download runner"
    exit 1
fi
print_success "Downloaded runner software"

# Step 3: Extract runner
print_info "[Step 3/7] Extracting runner..."
if ! tar xzf "$RUNNER_TAR"; then
    print_error "Failed to extract runner"
    exit 1
fi
rm "$RUNNER_TAR"
print_success "Extracted runner software"

# Step 4: Install dependencies
print_info "[Step 4/7] Installing dependencies..."
if command -v apt-get &> /dev/null; then
    print_info "Detected Debian/Ubuntu - installing dependencies..."
    sudo apt-get update
    sudo apt-get install -y libicu-dev
elif command -v yum &> /dev/null; then
    print_info "Detected RHEL/CentOS - installing dependencies..."
    sudo yum install -y libicu
else
    print_warning "Unknown package manager - you may need to install libicu manually"
fi
print_success "Dependencies installed"

# Step 5: Configure runner
print_info "[Step 5/7] Configuring runner for Android builds..."
if ! ./config.sh \
    --url "https://github.com/${REPO_OWNER}/${REPO_NAME}" \
    --token "$GITHUB_TOKEN" \
    --name "$RUNNER_NAME" \
    --labels "self-hosted,linux,android,unity" \
    --work "_work" \
    --unattended; then
    print_error "Failed to configure runner"
    exit 1
fi
print_success "Runner configured successfully"

# Step 6: Verify Unity installation (optional)
if [ "$SKIP_UNITY_CHECK" = false ]; then
    print_info "[Step 6/7] Verifying Unity installation..."
    
    UNITY_PATHS=(
        "$HOME/Unity/Hub/Editor/${UNITY_VERSION}/Editor/Unity"
        "/opt/unity/Editor/Unity"
        "/Applications/Unity/Hub/Editor/${UNITY_VERSION}/Unity.app/Contents/MacOS/Unity"
    )
    
    UNITY_FOUND=false
    for path in "${UNITY_PATHS[@]}"; do
        if [ -f "$path" ]; then
            print_success "Found Unity ${UNITY_VERSION} at: $path"
            UNITY_FOUND=true
            break
        fi
    done
    
    if [ "$UNITY_FOUND" = false ]; then
        print_warning "Unity ${UNITY_VERSION} not found in common locations"
        print_info "Please ensure Unity ${UNITY_VERSION} is installed with Android Build Support"
        print_info "Download from: https://unity.com/releases/editor/archive"
    fi
else
    print_info "[Step 6/7] Skipping Unity verification (as requested)"
fi

# Step 7: Install as systemd service (optional)
print_info "[Step 7/7] Setting up systemd service..."
if command -v systemctl &> /dev/null && [ -d "/etc/systemd/system" ]; then
    if ! sudo ./svc.sh install; then
        print_warning "Failed to install systemd service (non-critical)"
        print_info "You can run the runner manually with: ./run.sh"
    else
        print_success "Installed runner as systemd service"
        if ! sudo ./svc.sh start; then
            print_warning "Failed to start service, starting manually..."
            ./run.sh &
        else
            print_success "Runner service started"
        fi
    fi
else
    print_warning "systemd not available - runner will need to be started manually"
    print_info "Starting runner in background..."
    nohup ./run.sh > runner.log 2>&1 &
    print_success "Runner started in background (PID: $!)"
fi

# Final instructions
echo ""
print_success "=============================================="
print_success "Runner Setup Complete!"
print_success "=============================================="
echo ""
print_info "Your Linux PC is now configured as a GitHub Actions runner for Android builds."
echo ""
print_info "Next Steps:"
print_info "1. Verify runner is online: https://github.com/${REPO_OWNER}/${REPO_NAME}/settings/actions/runners"
print_info "2. Update your workflow file (.github/workflows/main.yml):"
print_info "   Change 'runs-on: macos-latest' to 'runs-on: self-hosted' for Android builds"
print_info "3. Push to androidBuild branch to trigger a test build"
echo ""
print_info "Runner Location: $RUNNER_DIR"
print_info "Runner Name: $RUNNER_NAME"
print_info "Labels: self-hosted, linux, android, unity"
echo ""
print_info "To stop the runner:"
if command -v systemctl &> /dev/null; then
    print_info "  sudo ./svc.sh stop"
else
    print_info "  pkill -f 'Runner.Listener'"
fi
echo ""
print_info "To uninstall the runner:"
print_info "  cd $RUNNER_DIR"
print_info "  ./config.sh remove --token YOUR_REMOVAL_TOKEN"
echo ""
