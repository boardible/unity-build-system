#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/lib/common.sh"

RETENTION="${UNITY_ARTIFACT_RETENTION:-5}"
if [[ "${1:-}" == "--keep" ]]; then
    RETENTION="${2:-}"
fi

print_usage() {
    echo "Usage: ./Scripts/pruneUnityArtifacts.sh [--keep <count>]"
    echo "Prunes ignored Unity logs, test XMLs, doctor/build logs, and bridge artifacts."
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    print_usage
    exit 0
fi

if ! [[ "$RETENTION" =~ ^[0-9]+$ ]] || [[ "$RETENTION" -le 0 ]]; then
    log_error "Retention must be a positive integer."
    exit 1
fi

before="$(du -sk "$PROJECT_PATH/Logs" "$PROJECT_PATH/.utmp/unity-control-bridge" 2>/dev/null | awk '{ total += $1 } END { print total + 0 }')"
UNITY_ARTIFACT_RETENTION="$RETENTION" prune_unity_artifacts "$PROJECT_PATH"
after="$(du -sk "$PROJECT_PATH/Logs" "$PROJECT_PATH/.utmp/unity-control-bridge" 2>/dev/null | awk '{ total += $1 } END { print total + 0 }')"

log_success "Unity artifacts pruned (keep=$RETENTION per family, reclaimed=$((before - after)) KB)"
