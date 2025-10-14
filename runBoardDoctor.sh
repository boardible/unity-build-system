#!/bin/bash

# BoardDoctor Standalone Script
# Runs BoardDoctor preprocessing independently of the build process
# Use this when you need to refresh game data, localization, textures, etc.
# 
# Usage:
#   ./runBoardDoctor.sh          # Defaults to dev environment
#   ./runBoardDoctor.sh dev      # Explicitly use dev environment
#   ./runBoardDoctor.sh prod     # Use production environment

set -e  # Exit on any error

echo "========================================"
echo " BoardDoctor Preprocessing"
echo "========================================"
echo ""

# Parse environment argument (dev or prod)
ENVIRONMENT="${1:-dev}"  # Default to dev if not specified
if [ "$ENVIRONMENT" != "dev" ] && [ "$ENVIRONMENT" != "prod" ]; then
    echo "❌ Error: Invalid environment '$ENVIRONMENT'. Must be 'dev' or 'prod'"
    echo "Usage: $0 [dev|prod]"
    exit 1
fi

# Get script directory and project paths
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"

# Load project configuration if it exists
if [ -f "$PROJECT_PATH/project-config.sh" ]; then
    source "$PROJECT_PATH/project-config.sh"
fi

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Auto-detect Unity version from ProjectSettings/ProjectVersion.txt
detect_unity_version() {
    local version_file="$PROJECT_PATH/ProjectSettings/ProjectVersion.txt"
    if [ -f "$version_file" ]; then
        local detected_version=$(grep "m_EditorVersion:" "$version_file" | sed 's/m_EditorVersion: //' | tr -d '[:space:]')
        if [ -n "$detected_version" ]; then
            echo "$detected_version"
            return 0
        fi
    fi
    return 1
}

# Set Unity version
if [ -z "$UNITY_VERSION" ]; then
    DETECTED_VERSION=$(detect_unity_version)
    if [ -n "$DETECTED_VERSION" ]; then
        export UNITY_VERSION="$DETECTED_VERSION"
        log "Auto-detected Unity version: $UNITY_VERSION"
    else
        export UNITY_VERSION="6000.0.58f2"
        log "Using default Unity version: $UNITY_VERSION"
    fi
fi

# Detect Unity path
detect_unity_path() {
    local version="$1"
    local paths=(
        "/Applications/Unity/Hub/Editor/$version/Unity.app/Contents/MacOS/Unity"
        "/Applications/Unity/Unity.app/Contents/MacOS/Unity"
        "$HOME/Applications/Unity/Hub/Editor/$version/Unity.app/Contents/MacOS/Unity"
    )
    
    for path in "${paths[@]}"; do
        if [ -f "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

UNITY_PATH=$(detect_unity_path "$UNITY_VERSION")
if [ -z "$UNITY_PATH" ]; then
    echo "❌ Error: Unity $UNITY_VERSION not found."
    echo "Please install Unity $UNITY_VERSION or update UNITY_VERSION in project-config.sh"
    exit 1
fi

log "=== BoardDoctor Standalone Execution ==="
log "Environment: $ENVIRONMENT"
log "Project Path: $PROJECT_PATH"
log "Unity Path: $UNITY_PATH"

# Create logs directory
LOGS_PATH="$PROJECT_PATH/Logs"
mkdir -p "$LOGS_PATH"

# Step 1: Sync CSVs from Google Sheets to S3
log "=== Step 1: Syncing CSVs to S3 ($ENVIRONMENT) ==="
CSV_SYNC_SCRIPT="$SCRIPT_DIR/sync-csv-to-s3.sh"
if [ -f "$CSV_SYNC_SCRIPT" ]; then
    log "Running CSV sync script for $ENVIRONMENT environment..."
    if bash "$CSV_SYNC_SCRIPT" "$ENVIRONMENT"; then
        log "✅ CSV sync completed successfully"
    else
        log "⚠️  CSV sync failed - continuing with existing CSVs"
        # Don't exit, just warn - BoardDoctor can continue with cached CSVs
    fi
else
    log "⚠️  CSV sync script not found at $CSV_SYNC_SCRIPT"
    log "Skipping CSV sync - using existing CSVs"
fi
log ""

# Step 2: Execute Unity BoardDoctor
# Unity command WITHOUT -quit (BuildScript.cs handles exit via EditorApplication.Exit)
unity_cmd="$UNITY_PATH"
# NOTE: -quit removed because BuildScript.RunBoardDoctor() calls EditorApplication.Exit() manually
unity_cmd+=" -batchmode"
unity_cmd+=" -nographics"
unity_cmd+=" -projectPath $PROJECT_PATH"
unity_cmd+=" -executeMethod BuildScript.RunBoardDoctor"
unity_cmd+=" -stackTraceLogType None"

log "=== Step 2: Executing Unity BoardDoctor ==="
log "This will refresh:"
log "  - Localization files"
log "  - Textures"
log "  - Sound processing"
log "  - Exchange rates"
log "  - Visual effects data"
log "  - Game data from CSV sources"
log ""

# Execute BoardDoctor with real-time output
log_file="$LOGS_PATH/unity-boarddoctor-$(date +%Y%m%d-%H%M%S).log"
eval "$unity_cmd" 2>&1 | tee "$log_file"
exit_code=${PIPESTATUS[0]}

if [ $exit_code -eq 0 ]; then
    log "✅ BoardDoctor completed successfully"
    log "Log file: $log_file"
else
    log "❌ BoardDoctor failed with exit code $exit_code"
    log "Check log file: $log_file"
    log "Last 20 lines of log:"
    tail -20 "$log_file" 2>/dev/null || echo "Could not read log file"
    exit $exit_code
fi

log "=== BoardDoctor Execution Complete ==="
