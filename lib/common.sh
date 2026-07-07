#!/usr/bin/env bash

# Common Build Script Library
# Shared functions for Unity build, CSV sync, and deployment scripts
# Compatible with bash 3.2+ (macOS default)

# Add common paths to PATH to ensure tools like aws, jq, unity are found
# This is critical when running from Unity Editor or CI environments
export PATH="$PATH:/usr/local/bin:/opt/homebrew/bin:/opt/local/bin"

# Color definitions
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Parse environment argument (dev/prod)
# Usage: ENVIRONMENT=$(parse_environment "$1")
parse_environment() {
    local env="${1:-dev}"  # Default to dev if not specified
    
    if [ "$env" != "dev" ] && [ "$env" != "prod" ]; then
        log_error "Invalid environment '$env'. Must be 'dev' or 'prod'"
        echo "Usage: $0 [dev|prod]"
        exit 1
    fi
    
    echo "$env"
}

# Load AWS credentials from .env file
# Usage: load_aws_config [path_to_env_file]
load_aws_config() {
    local env_file="${1:-$SCRIPT_DIR/.env}"
    
    if [ -f "$env_file" ]; then
        # Export variables from .env.
        # NOTE: source the file DIRECTLY — do NOT use `source <(grep ... )`.
        # On macOS's system bash 3.2.57 (arm64) the `source <(process-substitution)`
        # pattern silently fails: variable assignments run in a subshell and never
        # reach this shell, so KEYLEN ends up 0 and `aws` falls back to stale/aborted
        # creds → InvalidClientTokenId. Direct `source` handles `#` comments and blank
        # lines natively, so the grep filter was never needed.
        set -a  # Mark variables for export
        source "$env_file"
        set +a  # Stop marking variables for export
        # The .env holds long-term (AKIA…) keys and is the authoritative source.
        # Force-clear anything inherited from the shell / earlier-sourced .local
        # files that would override them at auth time:
        #  - AWS_PROFILE: a stray/dead profile makes `aws` ignore the static keys
        #    and fail ("credentials not configured" / profile not found).
        #  - AWS_SESSION_TOKEN/SECURITY_TOKEN: a leftover (usually expired) session
        #    token poisons static keys → InvalidClientTokenId ("credentials expired").
        unset AWS_PROFILE AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
        log_success "Loaded AWS credentials from .env"
        return 0
    else
        log_warn ".env file not found at $env_file"
        return 1
    fi
}

# Auto-detect Unity version from ProjectSettings/ProjectVersion.txt
# Usage: UNITY_VERSION=$(detect_unity_version)
detect_unity_version() {
    local project_path="${1:-$PROJECT_PATH}"
    local version_file="$project_path/ProjectSettings/ProjectVersion.txt"
    
    if [ -f "$version_file" ]; then
        local detected_version=$(grep "m_EditorVersion:" "$version_file" | sed 's/m_EditorVersion: //' | tr -d '[:space:]')
        if [ -n "$detected_version" ]; then
            echo "$detected_version"
            return 0
        fi
    fi
    
    return 1
}

# Find Unity installation path for detected version
# Usage: UNITY_PATH=$(find_unity_path "$UNITY_VERSION")
find_unity_path() {
    local version="$1"
    local unity_hub_path="/Applications/Unity/Hub/Editor"
    local detected_path=""
    
    if [ -z "$version" ]; then
        log_error "Unity version not provided to find_unity_path"
        return 1
    fi
    
    # Check Unity Hub installation
    if [ -d "$unity_hub_path/$version" ]; then
        detected_path="$unity_hub_path/$version/Unity.app/Contents/MacOS/Unity"
    elif [ -d "$unity_hub_path/${version}f1" ]; then
        detected_path="$unity_hub_path/${version}f1/Unity.app/Contents/MacOS/Unity"
    fi
    
    if [ -n "$detected_path" ] && [ -f "$detected_path" ]; then
        echo "$detected_path"
        return 0
    fi
    
    return 1
}

UNITY_LAUNCH_ARGS_RESULT=()

cleanup_stale_unity_license_socket() {
    local username sock target lc_pids

    # Kill orphaned UnityLicensingClient processes left from crashed or killed Unity runs.
    # Any LicensingClient running while no Unity Editor is open is an orphan that will
    # block the IPC channel name and cause the next run to time out during license init.
    if ! pgrep -f "Unity.app/Contents/MacOS/Unity" >/dev/null 2>&1; then
        lc_pids=$(pgrep -f "Unity.Licensing.Client" 2>/dev/null || true)
        if [ -n "$lc_pids" ]; then
            log_warn "Killing orphaned UnityLicensingClient processes: $lc_pids"
            echo "$lc_pids" | xargs kill 2>/dev/null || true
            sleep 2
            echo "$lc_pids" | xargs kill -9 2>/dev/null || true
        fi
    fi

    username="$(whoami)"

    # Remove stale Unity licensing socket files.
    # Matches plain and version-qualified variants, e.g.:
    #   Unity-LicenseClient-user.sock
    #   Unity-LicenseClient-user-notifications.sock
    #   Unity-LicenseClient-user-6000.3.17.sock
    #   Unity-LicenseClient-user-6000.3.17-notifications.sock
    for sock in /tmp/Unity-LicenseClient-"${username}"*.sock; do
        [ -e "$sock" ] || continue

        if [ -L "$sock" ]; then
            target=$(readlink "$sock" 2>/dev/null || true)
            if [ -n "$target" ] && [ -S "$target" ]; then
                continue  # symlink points to a live socket — leave it
            fi
            rm -f "$sock"
            log_warn "Removed stale licensing socket symlink: $(basename "$sock")"
        elif [ -S "$sock" ]; then
            if ! pgrep -f "Unity.Licensing.Client" >/dev/null 2>&1; then
                rm -f "$sock"
                log_warn "Removed stale licensing socket file: $(basename "$sock")"
            fi
        fi
    done
}

append_unity_launch_args() {
    UNITY_LAUNCH_ARGS_RESULT=()

    if [ "${BOARDIBLE_USE_HUB_IPC:-false}" != "true" ]; then
        cleanup_stale_unity_license_socket
        return 0
    fi

    UNITY_LAUNCH_ARGS_RESULT+=( -useHub -hubIPC )

    if [ -n "${UNITY_LICENSING_IPC:-}" ]; then
        UNITY_LAUNCH_ARGS_RESULT+=( -licensingIpc "$UNITY_LICENSING_IPC" )
    fi

    if [ -n "${UNITY_HUB_SESSION_ID:-}" ]; then
        UNITY_LAUNCH_ARGS_RESULT+=( -hubSessionId "$UNITY_HUB_SESSION_ID" )
    fi

    if [ -n "${UNITY_ACCESS_TOKEN:-}" ]; then
        UNITY_LAUNCH_ARGS_RESULT+=( -accessToken "$UNITY_ACCESS_TOKEN" )
    fi

    log_warn "BOARDIBLE_USE_HUB_IPC=true. Restoring the legacy Hub IPC launch path."
}

# Load project configuration file
# Usage: load_project_config [path_to_config]
load_project_config() {
    local config_file="${1:-$PROJECT_PATH/project-config.sh}"
    
    if [ -f "$config_file" ]; then
        source "$config_file"
        log_success "Loaded project configuration"
        return 0
    else
        log_warn "project-config.sh not found at $config_file"
        return 1
    fi
}

# Parse JSON value from file using jq or Python fallback
# Usage: value=$(json_get "path/to/file.json" ".key.subkey")
json_get() {
    local file="$1"
    local query="$2"
    
    if [ ! -f "$file" ]; then
        log_error "JSON file not found: $file"
        return 1
    fi
    
    if command -v jq &> /dev/null; then
        jq -r "$query // empty" "$file"
    else
        # Fallback to Python if jq not available
        python3 -c "import json, sys; data=json.load(open('$file')); print(data$query if data$query else '')" 2>/dev/null || echo ""
    fi
}

# Check if command exists
# Usage: if command_exists "jq"; then ...
command_exists() {
    command -v "$1" &> /dev/null
}

# Validate required commands are installed
# Usage: validate_commands "jq" "aws" "unity"
validate_commands() {
    local missing_commands=()
    
    for cmd in "$@"; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        return 1
    fi
    
    return 0
}

# Print banner with title
# Usage: print_banner "Script Name"
print_banner() {
    local title="$1"
    local length=$((${#title} + 4))
    local separator=$(printf '=%.0s' $(seq 1 $length))
    
    echo ""
    echo "$separator"
    echo "  $title"
    echo "$separator"
    echo ""
}

# Cleanup function to run on exit
# Usage: trap cleanup_temp_files EXIT
cleanup_temp_files() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        log_info "Cleaned up temporary files"
    fi
}

# Export all functions so they're available to scripts that source this file
export -f log_info
export -f log_success
export -f log_warn
export -f log_error
export -f log
export -f parse_environment
export -f load_aws_config
export -f detect_unity_version
export -f find_unity_path
export -f cleanup_stale_unity_license_socket
export -f append_unity_launch_args
export -f load_project_config
export -f json_get
export -f command_exists
export -f validate_commands
export -f print_banner
export -f cleanup_temp_files
