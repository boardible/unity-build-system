#!/usr/bin/env bash

# CSV to S3 Migration Script
# Downloads CSVs from Google Sheets and uploads to S3 with CloudFront invalidation
# Can be run manually or automatically via BoardDoctor
# Compatible with bash 3.2+ (macOS default)

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"
TEMP_DIR="$PROJECT_PATH/.csv-temp"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# AWS Configuration
AWS_S3_BUCKET="boardible-app"
AWS_REGION="us-east-1"
AWS_PROFILE="${AWS_PROFILE:-}"  # Use profile if set, otherwise default
CLOUDFRONT_DOMAIN=""  # Will be loaded from AWSDevInfos

# Determine environment (dev or prod)
ENVIRONMENT="${BUILD_ENV:-dev}"  # Default to dev if not set
UPDATE_CONFIG=false  # Whether to update boardibleConfigs.json with CloudFront URLs

# Parse arguments
while [ $# -gt 0 ]; do
    case $1 in
        dev)
            ENVIRONMENT="dev"
            shift
            ;;
        prod)
            ENVIRONMENT="prod"
            shift
            ;;
        --update-config)
            UPDATE_CONFIG=true
            shift
            ;;
        *)
            log_error "Unknown argument: $1"
            echo "Usage: $0 [dev|prod] [--update-config]"
            exit 1
            ;;
    esac
done

# These will be loaded from boardibleConfigs.json
S3_PREFIX=""  # Will be set to: {s3Prefix}configs/$ENVIRONMENT
CLOUDFRONT_DISTRIBUTION_ID=""  # Will be loaded from AWSDevInfos

# Load CloudFront distribution ID from AWSDevInfos.asset
load_aws_config() {
    local config_file="$PROJECT_PATH/Assets/Resources/boardibleConfigs.json"
    local aws_config="$PROJECT_PATH/AWSDevInfos.asset"
    
    # Load s3Prefix from boardibleConfigs.json
    if [ -f "$config_file" ]; then
        if command -v jq &> /dev/null; then
            local s3_base=$(jq -r '.s3Prefix // "ineuj-app/"' "$config_file")
            S3_PREFIX="${s3_base}configs/$ENVIRONMENT"
            log_info "S3 Prefix: $S3_PREFIX"
        else
            # Fallback: hardcoded default
            S3_PREFIX="ineuj-app/configs/$ENVIRONMENT"
            log_warn "jq not installed - using default S3 prefix"
        fi
    else
        log_error "boardibleConfigs.json not found"
        exit 1
    fi
    
    # Load CloudFront config from AWSDevInfos.asset
    if [ -f "$aws_config" ]; then
        CLOUDFRONT_DISTRIBUTION_ID=$(grep -o '"distributionID":"[^"]*"' "$aws_config" | cut -d'"' -f4)
        CLOUDFRONT_DOMAIN=$(grep -o '"domainName":"[^"]*"' "$aws_config" | cut -d'"' -f4)
        
        if [ -n "$CLOUDFRONT_DISTRIBUTION_ID" ]; then
            log_info "CloudFront Distribution ID: $CLOUDFRONT_DISTRIBUTION_ID"
        else
            log_warn "CloudFront Distribution ID not found in AWSDevInfos.asset"
        fi
        
        if [ -n "$CLOUDFRONT_DOMAIN" ]; then
            log_info "CloudFront Domain: $CLOUDFRONT_DOMAIN"
        else
            log_warn "CloudFront Domain not found in AWSDevInfos.asset"
        fi
    else
        log_warn "AWSDevInfos.asset not found - CloudFront invalidation will be skipped"
    fi
}

# CSV Configuration - Load from boardibleConfigs.json
# Using parallel arrays instead of associative array for bash 3.2 compatibility
CSV_NAMES=()
CSV_URLS=()
CSV_CACHE_PATHS=()  # Optional cache paths for offline use

load_csv_sources() {
    local config_file="$PROJECT_PATH/Assets/Resources/boardibleConfigs.json"
    
    if [ ! -f "$config_file" ]; then
        log_error "boardibleConfigs.json not found at: $config_file"
        exit 1
    fi
    
    log_info "Loading CSV sources from boardibleConfigs.json..."
    
    # Check if jq is available for better JSON parsing
    if command -v jq &> /dev/null; then
        # Use jq for robust JSON parsing - works with bash 3.2
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                # Split on first '=' character
                local key="${line%%=*}"
                local value="${line#*=}"
                if [ -n "$key" ] && [ -n "$value" ]; then
                    CSV_NAMES+=("$key")
                    CSV_URLS+=("$value")
                    
                    # Check if this CSV has a cache path configured
                    local cache_path=$(jq -r ".csvCache.\"$key\" // \"\"" "$config_file")
                    CSV_CACHE_PATHS+=("$cache_path")
                fi
            fi
        done < <(jq -r '.csvSources | to_entries | .[] | "\(.key)=\(.value)"' "$config_file")
    else
        # Fallback to grep/sed (less robust but works)
        log_warn "jq not installed - using basic parsing (install with: brew install jq)"
        log_warn "CSV caching will be disabled without jq"
        
        # Extract csvSources section and parse key-value pairs
        local in_csv_section=0
        while IFS= read -r line; do
            # Detect start of csvSources section
            if [[ "$line" =~ \"csvSources\"[[:space:]]*:[[:space:]]*\{ ]]; then
                in_csv_section=1
                continue
            fi
            
            # Detect end of csvSources section
            if [ $in_csv_section -eq 1 ] && [[ "$line" =~ ^\s*\},?\s*$ ]]; then
                break
            fi
            
            # Parse key-value pairs inside csvSources
            if [ $in_csv_section -eq 1 ]; then
                if [[ "$line" =~ \"([^\"]+)\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                    local key="${BASH_REMATCH[1]}"
                    local value="${BASH_REMATCH[2]}"
                    CSV_NAMES+=("$key")
                    CSV_URLS+=("$value")
                    CSV_CACHE_PATHS+=("")  # No cache path in fallback mode
                fi
            fi
        done < "$config_file"
    fi
    
    local count=${#CSV_NAMES[@]}
    if [ $count -eq 0 ]; then
        log_error "No CSV sources found in boardibleConfigs.json"
        log_error "Make sure 'csvSources' section exists with CSV URLs"
        exit 1
    fi
    
    log_success "Loaded $count CSV sources from config"
}

# Download CSV from URL
download_csv() {
    local name=$1
    local url=$2
    local output_file="$TEMP_DIR/${name}.csv"
    
    log_info "Downloading $name..."
    
    # Use curl with retry logic
    if curl -sSL --retry 3 --retry-delay 2 -o "$output_file" "$url"; then
        # Validate CSV has content
        if [ -s "$output_file" ]; then
            local line_count=$(wc -l < "$output_file")
            log_success "Downloaded $name ($line_count lines)"
            return 0
        else
            log_error "Downloaded file is empty: $name"
            return 1
        fi
    else
        log_error "Failed to download $name from $url"
        return 1
    fi
}

# Upload CSV to S3
upload_to_s3() {
    local name=$1
    local file="$TEMP_DIR/${name}.csv"
    local s3_path="$S3_PREFIX/${name}.csv"
    
    if [ ! -f "$file" ]; then
        log_error "File not found: $file"
        return 1
    fi
    
    log_info "Uploading $name to s3://$AWS_S3_BUCKET/$s3_path..."
    
    # Build AWS command with optional profile
    local aws_cmd="aws"
    if [ -n "$AWS_PROFILE" ]; then
        aws_cmd="aws --profile $AWS_PROFILE"
    fi
    
    # Upload with proper content type and cache control
    if $aws_cmd s3 cp "$file" "s3://$AWS_S3_BUCKET/$s3_path" \
        --content-type "text/csv; charset=utf-8" \
        --cache-control "max-age=3600" \
        --region "$AWS_REGION" \
        --only-show-errors; then
        log_success "Uploaded $name to S3"
        return 0
    else
        log_error "Failed to upload $name to S3"
        return 1
    fi
}

# Cache CSV to Unity Resources folder for offline use
cache_csv_to_resources() {
    local name=$1
    local cache_path=$2
    
    # Skip if no cache path configured
    if [ -z "$cache_path" ]; then
        return 0
    fi
    
    local source_file="$TEMP_DIR/${name}.csv"
    local target_file="$PROJECT_PATH/$cache_path"
    local target_dir=$(dirname "$target_file")
    
    if [ ! -f "$source_file" ]; then
        log_error "Source file not found for caching: $source_file"
        return 1
    fi
    
    log_info "Caching $name to $cache_path..."
    
    # Create directory if it doesn't exist
    mkdir -p "$target_dir"
    
    # Copy CSV to Resources folder
    if cp "$source_file" "$target_file"; then
        log_success "Cached $name for offline use"
        return 0
    else
        log_error "Failed to cache $name"
        return 1
    fi
}

# Update boardibleConfigs.json with CloudFront URLs
update_config_urls() {
    if [ -z "$CLOUDFRONT_DOMAIN" ]; then
        log_warn "Cannot update config - CloudFront domain not found"
        return 1
    fi
    
    local config_file="$PROJECT_PATH/Assets/Resources/boardibleConfigs.json"
    local config_backup="${config_file}.backup"
    
    log_info "Updating boardibleConfigs.json with CloudFront URLs..."
    
    # Create backup
    cp "$config_file" "$config_backup"
    log_info "Created backup: ${config_backup}"
    
    # Build CloudFront base URL
    local cloudfront_base="https://${CLOUDFRONT_DOMAIN}/${S3_PREFIX}"
    
    # Check if jq is available for better JSON manipulation
    if command -v jq &> /dev/null; then
        local temp_file="${config_file}.tmp"
        local updated=0
        
        # Update localizationURL (maps to "localization" CSV key)
        local localization_url="${cloudfront_base}/localization.csv"
        jq --arg url "$localization_url" \
           'if .localizationURL then .localizationURL = $url else . end' \
           "$config_file" > "$temp_file"
        mv "$temp_file" "$config_file"
        log_info "Updated localizationURL → $localization_url"
        ((updated++))
        
        # Update partnerURL (maps to "partners" CSV key)
        local partner_url="${cloudfront_base}/partners.csv"
        jq --arg url "$partner_url" \
           'if .partnerURL then .partnerURL = $url else . end' \
           "$config_file" > "$temp_file"
        mv "$temp_file" "$config_file"
        log_info "Updated partnerURL → $partner_url"
        ((updated++))
        
        # Update notificationsURL (maps to "notifications" CSV key)
        local notifications_url="${cloudfront_base}/notifications.csv"
        jq --arg url "$notifications_url" \
           'if .tools.notificationsURL then .tools.notificationsURL = $url else . end' \
           "$config_file" > "$temp_file"
        mv "$temp_file" "$config_file"
        log_info "Updated notificationsURL → $notifications_url"
        ((updated++))
        
        log_success "Updated $updated config URLs to CloudFront"
        log_info "Backup saved at: ${config_backup}"
        return 0
    else
        # Fallback without jq - not recommended
        log_error "jq is required for --update-config"
        log_error "Install with: brew install jq"
        return 1
    fi
}

# Invalidate CloudFront cache
invalidate_cloudfront() {
    if [ -z "$CLOUDFRONT_DISTRIBUTION_ID" ]; then
        log_warn "Skipping CloudFront invalidation (no distribution ID)"
        return 0
    fi
    
    log_info "Invalidating CloudFront cache for /$S3_PREFIX/*..."
    
    # Build AWS command with optional profile
    local aws_cmd="aws"
    if [ -n "$AWS_PROFILE" ]; then
        aws_cmd="aws --profile $AWS_PROFILE"
    fi
    
    if $aws_cmd cloudfront create-invalidation \
        --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
        --paths "/$S3_PREFIX/*" \
        --query 'Invalidation.Id' \
        --output text > /dev/null 2>&1; then
        log_success "CloudFront cache invalidated"
        return 0
    else
        log_warn "CloudFront invalidation failed (non-critical)"
        return 0  # Don't fail the whole script
    fi
}

# Main execution
main() {
    echo "========================================"
    echo " CSV to S3 Migration"
    echo "========================================"
    echo ""
    log_info "Environment: $ENVIRONMENT"
    log_info "S3 Path: s3://$AWS_S3_BUCKET/$S3_PREFIX/"
    echo ""
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first:"
        log_error "  brew install awscli"
        exit 1
    fi
    
    # Check AWS credentials (with SSO support)
    local aws_cmd="aws"
    if [ -n "$AWS_PROFILE" ]; then
        aws_cmd="aws --profile $AWS_PROFILE"
        log_info "Using AWS profile: $AWS_PROFILE"
    fi
    
    if ! $aws_cmd sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or expired."
        if [ -n "$AWS_PROFILE" ]; then
            log_error "  aws sso login --profile $AWS_PROFILE"
        else
            log_error "Option 1 - Use AWS SSO (recommended):"
            log_error "  aws configure sso"
            log_error "  export AWS_PROFILE=PowerUserAccess-325252612153"
            log_error ""
            log_error "Option 2 - Use access keys:"
            log_error "  aws configure"
        fi
        exit 1
    fi
    
    # Load AWS configuration
    load_aws_config
    
    # Load CSV sources from boardibleConfigs.json
    load_csv_sources
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    
    # Track statistics
    local total_count=${#CSV_NAMES[@]}
    local success_count=0
    local failed_count=0
    local cached_count=0
    local failed_items=()
    
    # Process each CSV using indexed arrays
    for i in "${!CSV_NAMES[@]}"; do
        local name="${CSV_NAMES[$i]}"
        local url="${CSV_URLS[$i]}"
        local cache_path="${CSV_CACHE_PATHS[$i]}"
        
        if download_csv "$name" "$url"; then
            local upload_success=true
            local cache_success=true
            
            # Upload to S3
            if ! upload_to_s3 "$name"; then
                upload_success=false
                ((failed_count++))
                failed_items+=("$name (upload failed)")
            fi
            
            # Cache to Resources folder if configured
            if [ -n "$cache_path" ]; then
                if cache_csv_to_resources "$name" "$cache_path"; then
                    ((cached_count++))
                else
                    cache_success=false
                    if [ "$upload_success" = true ]; then
                        # Only count as failed if upload succeeded but cache failed
                        log_warn "CSV uploaded but cache failed for $name"
                    fi
                fi
            fi
            
            # Only increment success if upload succeeded
            if [ "$upload_success" = true ]; then
                ((success_count++))
            fi
        else
            ((failed_count++))
            failed_items+=("$name (download failed)")
        fi
        echo ""
    done
    
    # Invalidate CloudFront cache once at the end
    if [ $success_count -gt 0 ]; then
        invalidate_cloudfront
    fi
    
    # Update config URLs if requested
    if [ "$UPDATE_CONFIG" = true ] && [ $success_count -gt 0 ]; then
        echo ""
        update_config_urls
    fi
    
    # Cleanup temp directory
    rm -rf "$TEMP_DIR"
    
    # Print summary
    echo "========================================"
    echo " Migration Complete"
    echo "========================================"
    log_info "Total CSVs: $total_count"
    log_success "Successful uploads: $success_count"
    if [ $cached_count -gt 0 ]; then
        log_success "Cached for offline: $cached_count"
    fi
    if [ $failed_count -gt 0 ]; then
        log_error "Failed: $failed_count"
        for item in "${failed_items[@]}"; do
            log_error "  - $item"
        done
    fi
    echo ""
    
    if [ $success_count -eq $total_count ]; then
        log_success "✅ All CSVs migrated successfully!"
        if [ "$UPDATE_CONFIG" = true ]; then
            log_info "✅ Config URLs updated to CloudFront"
        else
            log_info "To update config URLs automatically, run with: --update-config"
        fi
        log_info "Next steps:"
        log_info "  1. Test the app to ensure CSVs load correctly"
        log_info "  2. Deploy the updated config"
        return 0
    elif [ $success_count -gt 0 ]; then
        log_warn "⚠️  Partial migration completed"
        return 1
    else
        log_error "❌ Migration failed"
        return 1
    fi
}

# Run main function
main "$@"
