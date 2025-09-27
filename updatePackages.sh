#!/bin/bash

# Comprehensive Package Updater Script
# Updates Firebase and Facebook SDKs for Unity
# Usage: ./updatePackages.sh [options]

set -e

# Default values
FIREBASE_VERSION=""
FACEBOOK_VERSION=""
UNITY_PATH="/Applications/Unity/Hub/Editor/6000.0.58f1/Unity.app/Contents/MacOS/Unity"
PROJECT_PATH="/Users/pedromartinez/Dev/ineuj"
UPDATE_FIREBASE=false
UPDATE_FACEBOOK=false
UPDATE_ALL=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

print_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

print_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Function to show usage
show_usage() {
    echo "Unity Package Updater Script"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --firebase [version]     Update Firebase SDK (optional version, defaults to 13.3.0)"
    echo "  --facebook [version]     Update Facebook SDK (optional version, defaults to 19.0.0)"
    echo "  --all                    Update both Firebase and Facebook SDKs"
    echo "  --unity-path PATH        Path to Unity executable"
    echo "  --project-path PATH      Path to Unity project"
    echo "  --help                   Show this help message"
    echo
    echo "Examples:"
    echo "  $0 --firebase                    # Update Firebase to latest"
    echo "  $0 --firebase 13.2.0             # Update Firebase to specific version"
    echo "  $0 --facebook 19.0.0             # Update Facebook to specific version"
    echo "  $0 --all                         # Update both to latest versions"
    echo "  $0 --firebase --facebook         # Update both to latest versions"
    echo
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --firebase)
            UPDATE_FIREBASE=true
            if [[ -n $2 && $2 != --* ]]; then
                FIREBASE_VERSION="$2"
                shift
            else
                FIREBASE_VERSION="13.3.0"
            fi
            shift
            ;;
        --facebook)
            UPDATE_FACEBOOK=true
            if [[ -n $2 && $2 != --* ]]; then
                FACEBOOK_VERSION="$2"
                shift
            else
                FACEBOOK_VERSION="18.0.0"
            fi
            shift
            ;;
        --all)
            UPDATE_ALL=true
            UPDATE_FIREBASE=true
            UPDATE_FACEBOOK=true
            FIREBASE_VERSION="13.3.0"
            FACEBOOK_VERSION="18.0.0"
            shift
            ;;
        --unity-path)
            UNITY_PATH="$2"
            shift 2
            ;;
        --project-path)
            PROJECT_PATH="$2"
            shift 2
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate that at least one update option is specified
if [[ "$UPDATE_FIREBASE" != "true" && "$UPDATE_FACEBOOK" != "true" ]]; then
    print_error "No update option specified"
    show_usage
    exit 1
fi

# Validate Unity path
if [[ ! -f "$UNITY_PATH" ]]; then
    print_error "Unity executable not found at: $UNITY_PATH"
    exit 1
fi

# Validate project path
if [[ ! -d "$PROJECT_PATH" ]]; then
    print_error "Project path not found: $PROJECT_PATH"
    exit 1
fi

print_status "=== Unity Package Updater ==="
print_status "Unity Path: $UNITY_PATH"
print_status "Project Path: $PROJECT_PATH"
print_status "Firebase Update: $UPDATE_FIREBASE $([ "$UPDATE_FIREBASE" == "true" ] && echo "($FIREBASE_VERSION)")"
print_status "Facebook Update: $UPDATE_FACEBOOK $([ "$UPDATE_FACEBOOK" == "true" ] && echo "($FACEBOOK_VERSION)")"
echo

# Get script directory
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Update Firebase if requested
if [[ "$UPDATE_FIREBASE" == "true" ]]; then
    print_status "Starting Firebase SDK update..."
    
    if [[ -f "$SCRIPT_DIR/updateFirebase.sh" ]]; then
        "$SCRIPT_DIR/updateFirebase.sh" "$FIREBASE_VERSION" "$UNITY_PATH" "$PROJECT_PATH"
        
        if [[ $? -eq 0 ]]; then
            print_success "Firebase SDK updated successfully to v$FIREBASE_VERSION"
        else
            print_error "Firebase SDK update failed"
            exit 1
        fi
    else
        print_error "Firebase updater script not found: $SCRIPT_DIR/updateFirebase.sh"
        exit 1
    fi
    
    echo
fi

# Update Facebook if requested  
if [[ "$UPDATE_FACEBOOK" == "true" ]]; then
    print_status "Starting Facebook SDK update..."
    
    if [[ -f "$SCRIPT_DIR/updateFacebook.sh" ]]; then
        "$SCRIPT_DIR/updateFacebook.sh" "$FACEBOOK_VERSION" "$UNITY_PATH" "$PROJECT_PATH"
        
        if [[ $? -eq 0 ]]; then
            print_success "Facebook SDK updated successfully to v$FACEBOOK_VERSION"
        else
            print_error "Facebook SDK update failed"
            exit 1
        fi
    else
        print_error "Facebook updater script not found: $SCRIPT_DIR/updateFacebook.sh"
        exit 1
    fi
    
    echo
fi

# Final summary
print_success "=== Package Update Complete ==="
if [[ "$UPDATE_FIREBASE" == "true" ]]; then
    print_success "✓ Firebase SDK: v$FIREBASE_VERSION"
fi
if [[ "$UPDATE_FACEBOOK" == "true" ]]; then
    print_success "✓ Facebook SDK: v$FACEBOOK_VERSION"
fi

print_status "Post-update checklist:"
echo "1. Open Unity and check for any import errors"
echo "2. Verify SDK configurations (Firebase: google-services.json, Facebook: FacebookSettings.asset)"
echo "3. Test authentication and other SDK functionality"
echo "4. Update your build scripts if framework versions changed"
echo "5. Run a test build to ensure compatibility"

if [[ "$UPDATE_FIREBASE" == "true" && "$UPDATE_FACEBOOK" == "true" ]]; then
    print_warning "Both SDKs updated - pay special attention to potential conflicts"
fi

print_success "All updates completed successfully!"