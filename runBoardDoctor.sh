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

# Get script directory and project paths
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"

# Load common functions
source "$SCRIPT_DIR/lib/common.sh"

# Print banner
print_banner "BoardDoctor Preprocessing"

# Parse environment argument (dev or prod)
ENVIRONMENT=$(parse_environment "${1:-dev}")

# Load project configuration if it exists
load_project_config "$PROJECT_PATH/project-config.sh"

# Set Unity version - auto-detect or use default
if [ -z "$UNITY_VERSION" ]; then
    DETECTED_VERSION=$(detect_unity_version "$PROJECT_PATH")
    if [ -n "$DETECTED_VERSION" ]; then
        export UNITY_VERSION="$DETECTED_VERSION"
        log "Auto-detected Unity version: $UNITY_VERSION"
    else
        export UNITY_VERSION="6000.5.3f1"
        log "Using default Unity version: $UNITY_VERSION"
    fi
fi

# Detect Unity path using common library
UNITY_PATH=$(find_unity_path "$UNITY_VERSION")
if [ -z "$UNITY_PATH" ]; then
    log_error "Unity $UNITY_VERSION not found."
    echo "Please install Unity $UNITY_VERSION or update UNITY_VERSION in project-config.sh"
    exit 1
fi

log "=== BoardDoctor Standalone Execution ==="
log "Environment: $ENVIRONMENT"
log "Project Path: $PROJECT_PATH"
log "Unity Path: $UNITY_PATH"

run_unity_with_followed_log() {
    local log_file="$1"
    shift

    : > "$log_file"

    # Let Unity write its own log file and stream that file, instead of piping
    # Unity stdout through tee. This avoids the console stream path that has
    # intermittently failed during Android project modification.
    tail -n +1 -F "$log_file" &
    local tail_pid=$!

    set +e
    "$@" -logFile "$log_file"
    local exit_code=$?
    set -e

    kill "$tail_pid" >/dev/null 2>&1 || true
    wait "$tail_pid" 2>/dev/null || true

    return $exit_code
}

ensure_project_not_open_in_unity() {
    local unity_processes
    unity_processes=$(pgrep -af "Unity.app/Contents/MacOS/Unity" | grep -- "-projectPath $PROJECT_PATH" || true)

    if [ -n "$unity_processes" ]; then
        log "❌ Another Unity instance already has this project open:"
        echo "$unity_processes"
        log "Close the Unity editor for $PROJECT_PATH, then rerun BoardDoctor."
        exit 1
    fi
}

report_unity_package_registration_failure() {
    local log_file="$1"

    if [ ! -f "$log_file" ]; then
        return 1
    fi

    if ! grep -Fq "[Package Manager] Registered 0 packages:" "$log_file"; then
        return 1
    fi

    if ! grep -Fq "[Package Manager] The following packages were not registered because your license doesn't allow it." "$log_file"; then
        return 1
    fi

    log ""
    log "Unity batchmode failed before BoardDoctor started."

    if grep -Fq "[Licensing::Module] Error: 'com.unity.editor.headless' was not found." "$log_file"; then
        log "Root cause: Unity lost the headless licensing entitlement, so Package Manager registered 0 packages."
    else
        log "Root cause: Unity Package Manager registered 0 packages during startup."
    fi

    log "This makes package types like UniTask, TextMeshPro, UGUI, Purchasing, and Newtonsoft disappear."
    log "Recovery steps:"
    log "  1. Quit all Unity editors and Unity Hub."
    log "  2. Kill any stuck Unity.Licensing.Client and UnityPackageManager processes."
    log "  3. Reopen Unity Hub, sign in again if needed, and open this project once in the editor."
    log "  4. Retry BoardDoctor."
    log "If it still fails, try the rerun from an active desktop session without -nographics as a local workaround."

    return 0
}

# Create logs directory
LOGS_PATH="$PROJECT_PATH/Logs"
mkdir -p "$LOGS_PATH"
prune_unity_artifacts "$PROJECT_PATH"

# Step 1: Sync CSVs from Google Sheets to S3
log "=== Step 1: Syncing CSVs to S3 ($ENVIRONMENT) ==="
CSV_SYNC_SCRIPT="$SCRIPT_DIR/sync-csv-to-s3.sh"
if [ -f "$CSV_SYNC_SCRIPT" ]; then
    log "Running CSV sync script for $ENVIRONMENT environment..."
    # For prod, also update boardibleConfigs.json URLs to point to prod CloudFront paths
    SYNC_ARGS="$ENVIRONMENT"
    if [ "$ENVIRONMENT" = "prod" ]; then
        SYNC_ARGS="$ENVIRONMENT --update-config"
        log "Production build: will update boardibleConfigs.json URLs to prod CloudFront paths"
    fi
    if bash "$CSV_SYNC_SCRIPT" $SYNC_ARGS; then
        log_success "CSV sync completed successfully"
    else
        log_warn "CSV sync failed - continuing with existing CSVs"
        # Don't exit, just warn - BoardDoctor can continue with cached CSVs
    fi
else
    log "⚠️  CSV sync script not found at $CSV_SYNC_SCRIPT"
    log "Skipping CSV sync - using existing CSVs"
fi
log ""

# Step 2: Execute Unity BoardDoctor
log "=== Step 2: Executing Unity BoardDoctor ==="
log "This will refresh:"
log "  - Localization files"
log "  - Textures"
log "  - Sound processing"
log "  - Exchange rates"
log "  - Visual effects data"
log "  - Game data from CSV sources"
log ""
ensure_project_not_open_in_unity
append_unity_launch_args

# Execute BoardDoctor with real-time output
log_file="$LOGS_PATH/unity-boarddoctor-$(date +%Y%m%d-%H%M%S).log"
run_unity_with_followed_log "$log_file" \
    "$UNITY_PATH" -batchmode -nographics "${UNITY_LAUNCH_ARGS_RESULT[@]}" \
    -projectPath "$PROJECT_PATH" \
    -executeMethod "BuildScript.RunBoardDoctor" \
    -stackTraceLogType None
exit_code=$?

if [ $exit_code -eq 0 ]; then
    log "✅ BoardDoctor completed successfully"
    log "Log file: $log_file"
else
    log "❌ BoardDoctor failed with exit code $exit_code"
    log "Check log file: $log_file"
    report_unity_package_registration_failure "$log_file" || true
    log "Last 20 lines of log:"
    tail -20 "$log_file" 2>/dev/null || echo "Could not read log file"
    exit $exit_code
fi

log "=== BoardDoctor Execution Complete ==="
