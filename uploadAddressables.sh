#!/usr/bin/env bash

# Upload Addressables to CDN (S3 + CloudFront)
# Called by androidDeploy.sh and iosDeploy.sh after the Unity build
# Only runs when REMOTE_ADDRESSABLES_ENABLED=true in project-config.sh
#
# Usage: ./uploadAddressables.sh <platform>
#   platform: android | ios
#
# Required env vars (when REMOTE_ADDRESSABLES_ENABLED=true):
#   ADDRESSABLES_S3_PATH                 - e.g. s3://my-bucket/addressables_test
#   ADDRESSABLES_CLOUDFRONT_DISTRIBUTION_ID - CloudFront distribution ID (optional, for cache invalidation)
#
# Optional env vars:
#   ADDRESSABLES_BUILD_DIR               - override default ServerData path
#   AWS_PROFILE                          - AWS CLI profile to use

set -e

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"

# Load common helpers
source "$SCRIPT_DIR/lib/common.sh"

# Load project config
if [ -f "$PROJECT_PATH/project-config.sh" ]; then
    source "$PROJECT_PATH/project-config.sh"
fi

# Load AWS credentials from .env
load_aws_config "$SCRIPT_DIR/.env"

# ── Argument parsing ──────────────────────────────────────────────────────────
PLATFORM="${1:-android}"

case "$PLATFORM" in
    android|Android) BUILD_TARGET="Android" ;;
    ios|iOS)         BUILD_TARGET="iOS" ;;
    *)
        log_error "Unknown platform '$PLATFORM'. Use 'android' or 'ios'."
        exit 1
        ;;
esac

# ── Guard: skip if remote Addressables not enabled for this project ───────────
if [ "${REMOTE_ADDRESSABLES_ENABLED:-false}" != "true" ]; then
    log_info "REMOTE_ADDRESSABLES_ENABLED is not true — skipping Addressables upload"
    exit 0
fi

# ── Validate required config ──────────────────────────────────────────────────
if [ -z "${ADDRESSABLES_S3_PATH:-}" ]; then
    log_error "ADDRESSABLES_S3_PATH is not set. Add it to project-config.sh."
    log_error "Example: export ADDRESSABLES_S3_PATH=\"s3://my-cdn-bucket/addressables_test\""
    exit 1
fi

# ── Locate built Addressables ─────────────────────────────────────────────────
ADDRESSABLES_BUILD_DIR="${ADDRESSABLES_BUILD_DIR:-$PROJECT_PATH/ServerData/$BUILD_TARGET}"

if [ ! -d "$ADDRESSABLES_BUILD_DIR" ]; then
    log_error "Addressables build directory not found: $ADDRESSABLES_BUILD_DIR"
    log_error "Build Addressables in Unity before running this script."
    exit 1
fi

# Count files to upload
FILE_COUNT=$(find "$ADDRESSABLES_BUILD_DIR" -type f | wc -l | tr -d ' ')
if [ "$FILE_COUNT" -eq 0 ]; then
    log_warn "No files found in $ADDRESSABLES_BUILD_DIR — nothing to upload"
    exit 0
fi

# ── Upload to S3 ──────────────────────────────────────────────────────────────
S3_DEST="$ADDRESSABLES_S3_PATH/$BUILD_TARGET"

log "=== Uploading Addressables to CDN ==="
log "Platform  : $BUILD_TARGET"
log "Source    : $ADDRESSABLES_BUILD_DIR ($FILE_COUNT files)"
log "S3 dest   : $S3_DEST"

AWS_ARGS=()
if [ -n "${AWS_PROFILE:-}" ]; then
    AWS_ARGS+=(--profile "$AWS_PROFILE")
fi

aws s3 sync "$ADDRESSABLES_BUILD_DIR" "$S3_DEST" \
    --delete \
    --cache-control "max-age=31536000, immutable" \
    "${AWS_ARGS[@]}"

log_success "Addressables uploaded to S3 ($FILE_COUNT files)"

# ── Invalidate CloudFront cache ───────────────────────────────────────────────
if [ -n "${ADDRESSABLES_CLOUDFRONT_DISTRIBUTION_ID:-}" ]; then
    # Extract just the path prefix from the S3 path for the invalidation pattern
    # ADDRESSABLES_S3_PATH might be s3://bucket/addressables_test
    # We need: /addressables_test/Android/*
    CDN_PREFIX="${ADDRESSABLES_S3_PATH#s3://*/}"   # strip s3://bucket
    CDN_PREFIX="${ADDRESSABLES_S3_PATH#s3://[^/]*/}"  # portable: strip s3://bucket/
    # Fallback: just derive from last path component
    CDN_PREFIX="/${ADDRESSABLES_S3_PATH##*/}/$BUILD_TARGET/*"

    log "Invalidating CloudFront path: $CDN_PREFIX"
    INVALIDATION_ID=$(aws cloudfront create-invalidation \
        --distribution-id "$ADDRESSABLES_CLOUDFRONT_DISTRIBUTION_ID" \
        --paths "$CDN_PREFIX" \
        --query 'Invalidation.Id' \
        --output text \
        "${AWS_ARGS[@]}")
    log_success "CloudFront invalidation created: $INVALIDATION_ID"
else
    log_warn "ADDRESSABLES_CLOUDFRONT_DISTRIBUTION_ID not set — skipping CloudFront invalidation"
fi

log "=== Addressables upload complete ==="
