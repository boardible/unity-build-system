#!/bin/bash

# Link.xml Validation Script
# Validates that link.xml hasn't been accidentally broken or reverted
# Run this as part of your build process

set -e

LINK_XML_PATH="Assets/link.xml"
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"

log() {
    echo "[link.xml Validator] $1"
}

error() {
    echo "[link.xml Validator] ERROR: $1" >&2
}

# Change to project directory
cd "$PROJECT_PATH"

# Check if link.xml exists
if [ ! -f "$LINK_XML_PATH" ]; then
    error "link.xml not found at $LINK_XML_PATH"
    exit 1
fi

log "Validating link.xml..."

# Read link.xml content
LINK_CONTENT=$(cat "$LINK_XML_PATH")

# ============================================================
# CRITICAL CHECKS - These MUST NOT appear in link.xml
# ============================================================

# Check 1: Ensure game assemblies don't have preserve="all"
if echo "$LINK_CONTENT" | grep -q '<assembly fullname="App" preserve="all"'; then
    error "Found 'preserve=\"all\"' on App assembly!"
    error "This prevents code stripping and inflates build size by ~25 MB."
    error "Remove it and use selective type preservation instead."
    exit 1
fi

if echo "$LINK_CONTENT" | grep -q '<assembly fullname="Boardible.Menu" preserve="all"'; then
    error "Found 'preserve=\"all\"' on Boardible.Menu assembly!"
    error "This prevents code stripping. Use selective preservation instead."
    exit 1
fi

if echo "$LINK_CONTENT" | grep -q '<assembly fullname="Boardible.Games" preserve="all"'; then
    error "Found 'preserve=\"all\"' on Boardible.Games assembly!"
    error "This prevents code stripping. Use selective preservation instead."
    exit 1
fi

if echo "$LINK_CONTENT" | grep -q '<assembly fullname="Boardible.Gameplay" preserve="all"'; then
    error "Found 'preserve=\"all\"' on Boardible.Gameplay assembly!"
    error "This prevents code stripping. Use selective preservation instead."
    exit 1
fi

if echo "$LINK_CONTENT" | grep -q '<assembly fullname="Boardible.Utils" preserve="all"'; then
    error "Found 'preserve=\"all\"' on Boardible.Utils assembly!"
    error "This prevents code stripping. Use selective preservation instead."
    exit 1
fi

# ============================================================
# REQUIRED CHECKS - These MUST be present
# ============================================================

# Check 2: AWS SDK must be preserved (required for DynamoDB)
if ! echo "$LINK_CONTENT" | grep -q '<assembly fullname="AWSSDK.Core" preserve="all"'; then
    error "AWSSDK.Core preservation is missing!"
    error "AWS DynamoDB operations will fail without this."
    exit 1
fi

if ! echo "$LINK_CONTENT" | grep -q '<assembly fullname="AWSSDK.DynamoDBv2" preserve="all"'; then
    error "AWSSDK.DynamoDBv2 preservation is missing!"
    error "DynamoDB operations will fail without this."
    exit 1
fi

# Check 3: Newtonsoft.Json must be preserved (used for all serialization)
if ! echo "$LINK_CONTENT" | grep -q '<assembly fullname="Newtonsoft.Json" preserve="all"'; then
    error "Newtonsoft.Json preservation is missing!"
    error "JSON serialization will fail without this."
    exit 1
fi

# ============================================================
# WARNING CHECKS - Suspicious but not blocking
# ============================================================

# Count how many assemblies have preserve="all"
PRESERVE_ALL_COUNT=$(echo "$LINK_CONTENT" | grep -c 'preserve="all"' || true)

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
log "   - No game assemblies with preserve=\"all\""
log "   - Required assemblies (AWS, Newtonsoft.Json) are preserved"
log "   - Total assemblies with preserve=\"all\": $PRESERVE_ALL_COUNT"

exit 0
