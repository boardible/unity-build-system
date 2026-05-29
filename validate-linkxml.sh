#!/bin/bash

# Link.xml Validation Script
# Validates that link.xml hasn't been accidentally broken or reverted
# Run this as part of your build process

set -e

VERSIONED_LINK_XML_PATH="Assets/link.xml"
GENERATED_LINK_XML_PATH="Assets/AddressableAssetsData/link.xml"
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"

log() {
    echo "[link.xml Validator] $1"
}

error() {
    echo "[link.xml Validator] ERROR: $1" >&2
}

count_preserve_all_entries() {
    local link_content="$1"
    echo "$link_content" | grep -c 'preserve="all"' || true
}

validate_game_assemblies() {
    local link_path="$1"
    local link_content="$2"

    if echo "$link_content" | grep -q '<assembly fullname="App" preserve="all"'; then
        error "Found 'preserve=\"all\"' on App assembly in $link_path!"
        error "This prevents code stripping and inflates build size by ~25 MB."
        error "Remove it and use selective type preservation instead."
        exit 1
    fi

    if echo "$link_content" | grep -q '<assembly fullname="Boardible.Menu" preserve="all"'; then
        error "Found 'preserve=\"all\"' on Boardible.Menu assembly in $link_path!"
        error "This prevents code stripping. Use selective preservation instead."
        exit 1
    fi

    if echo "$link_content" | grep -q '<assembly fullname="Boardible.Games" preserve="all"'; then
        error "Found 'preserve=\"all\"' on Boardible.Games assembly in $link_path!"
        error "This prevents code stripping. Use selective preservation instead."
        exit 1
    fi

    if echo "$link_content" | grep -q '<assembly fullname="Boardible.Gameplay" preserve="all"'; then
        error "Found 'preserve=\"all\"' on Boardible.Gameplay assembly in $link_path!"
        error "This prevents code stripping. Use selective preservation instead."
        exit 1
    fi

    if echo "$link_content" | grep -q '<assembly fullname="Boardible.Utils" preserve="all"'; then
        error "Found 'preserve=\"all\"' on Boardible.Utils assembly in $link_path!"
        error "This prevents code stripping. Use selective preservation instead."
        exit 1
    fi
}

validate_required_base_assemblies() {
    local link_path="$1"
    local link_content="$2"

    if ! echo "$link_content" | grep -q '<assembly fullname="AWSSDK.Core" preserve="all"'; then
        error "AWSSDK.Core preservation is missing from $link_path!"
        error "AWS DynamoDB operations will fail without this."
        exit 1
    fi

    if ! echo "$link_content" | grep -q '<assembly fullname="AWSSDK.DynamoDBv2" preserve="all"'; then
        error "AWSSDK.DynamoDBv2 preservation is missing from $link_path!"
        error "DynamoDB operations will fail without this."
        exit 1
    fi

    if ! echo "$link_content" | grep -q '<assembly fullname="Newtonsoft.Json" preserve="all"'; then
        error "Newtonsoft.Json preservation is missing from $link_path!"
        error "JSON serialization will fail without this."
        exit 1
    fi
}

# Change to project directory
cd "$PROJECT_PATH"

# Check if the versioned link.xml exists
if [ ! -f "$VERSIONED_LINK_XML_PATH" ]; then
    error "link.xml not found at $VERSIONED_LINK_XML_PATH"
    exit 1
fi

log "Validating versioned link.xml..."

VERSIONED_LINK_CONTENT=$(cat "$VERSIONED_LINK_XML_PATH")
VERSIONED_PRESERVE_ALL_COUNT=$(count_preserve_all_entries "$VERSIONED_LINK_CONTENT")

validate_game_assemblies "$VERSIONED_LINK_XML_PATH" "$VERSIONED_LINK_CONTENT"
validate_required_base_assemblies "$VERSIONED_LINK_XML_PATH" "$VERSIONED_LINK_CONTENT"

GENERATED_PRESERVE_ALL_COUNT=0
if [ -f "$GENERATED_LINK_XML_PATH" ]; then
    log "Validating generated Addressables link.xml..."
    GENERATED_LINK_CONTENT=$(cat "$GENERATED_LINK_XML_PATH")
    validate_game_assemblies "$GENERATED_LINK_XML_PATH" "$GENERATED_LINK_CONTENT"
    GENERATED_PRESERVE_ALL_COUNT=$(count_preserve_all_entries "$GENERATED_LINK_CONTENT")
else
    log "Generated Addressables link.xml not present; skipping transient file checks."
fi

# ============================================================
# WARNING CHECKS - Suspicious but not blocking
# ============================================================

PRESERVE_ALL_COUNT=$((VERSIONED_PRESERVE_ALL_COUNT + GENERATED_PRESERVE_ALL_COUNT))

if [ "$PRESERVE_ALL_COUNT" -gt 10 ]; then
    log "WARNING: Found $PRESERVE_ALL_COUNT assemblies with preserve=\"all\""
    log "This might prevent effective code stripping."
    log "Consider using selective type preservation instead."
    # Don't exit, just warn
fi

# ============================================================
# SUCCESS
# ============================================================

log "✅ link.xml validation passed!"
log "   - No game assemblies with preserve=\"all\" in versioned/generated sources"
log "   - Required assemblies (AWS, Newtonsoft.Json) are preserved in $VERSIONED_LINK_XML_PATH"
log "   - Total assemblies with preserve=\"all\": $PRESERVE_ALL_COUNT"

exit 0
