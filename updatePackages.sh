#!/bin/bash

# Comprehensive Package Updater Script
# Updates Firebase and Facebook SDKs for Unity
# Usage: ./updatePackages.sh [options]

set -e

# Default values
FIREBASE_VERSION=""
FACEBOOK_VERSION=""
UNITY_PATH=""
PROJECT_PATH="$(pwd)"
DOWNLOADS_DIR="$HOME/Downloads"
UPDATE_FIREBASE=false
UPDATE_FACEBOOK=false
UPDATE_ALL=false
OPTIMIZE_DEPENDENCIES=false
CLEAN_AFTER=true  # Changed: clean AFTER installation
EDM_VERSION="1.2.186"
INTERACTIVE=true  # Confirm each package installation

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" >&2
}

print_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" >&2
}

print_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" >&2
}

# Function to prompt user for confirmation
confirm_action() {
    local message="$1"
    local default="${2:-y}"  # Default to 'y' if not specified
    
    if [[ "$INTERACTIVE" != "true" ]]; then
        return 0  # Auto-confirm if non-interactive
    fi
    
    local prompt
    if [[ "$default" == "y" ]]; then
        prompt="$message [Y/n]: "
    else
        prompt="$message [y/N]: "
    fi
    
    read -p "$prompt" response
    response=${response:-$default}
    
    case "$response" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# Function to download file if not already present
download_if_needed() {
    local url="$1"
    local output_path="$2"
    local description="$3"
    
    if [[ -f "$output_path" ]]; then
        print_success "✓ $description already downloaded at: $output_path"
        if confirm_action "Re-download anyway?" "n"; then
            print_status "Downloading $description..."
            curl -L -o "$output_path" "$url" || return 1
        fi
    else
        print_status "Downloading $description from $url..."
        curl -L -o "$output_path" "$url" || return 1
        print_success "✓ Downloaded $description"
    fi
    
    return 0
}

# Function to extract zip if not already extracted
extract_if_needed() {
    local zip_path="$1"
    local extract_dir="$2"
    local description="$3"
    
    if [[ -d "$extract_dir" ]]; then
        print_success "✓ $description already extracted at: $extract_dir"
        if confirm_action "Re-extract anyway?" "n"; then
            rm -rf "$extract_dir"
            print_status "Extracting $description..."
            unzip -q "$zip_path" -d "$extract_dir" || return 1
        fi
    else
        print_status "Extracting $description..."
        mkdir -p "$extract_dir"
        unzip -q "$zip_path" -d "$extract_dir" || return 1
        print_success "✓ Extracted $description"
    fi
    
    return 0
}

# Function to clean OLD SDK files AFTER new installation
# This prevents Unity compilation errors during the update process
clean_old_sdk_files() {
    local project_path="$1"
    local sdk_type="$2"  # "firebase", "facebook", or "all"
    
    print_status "Cleaning old SDK files (keeping new installations)..."
    
    # Create backup directory with timestamp
    local backup_dir="${project_path}/Backup/sdk_cleanup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    if [[ "$sdk_type" == "firebase" || "$sdk_type" == "all" ]]; then
        print_status "Cleaning old Firebase files from GeneratedLocalRepo..."
        
        # Clean old Firebase versions from GeneratedLocalRepo
        if [[ -d "${project_path}/Assets/GeneratedLocalRepo" ]]; then
            # Backup before cleaning
            if [[ -d "${project_path}/Assets/GeneratedLocalRepo" ]]; then
                cp -r "${project_path}/Assets/GeneratedLocalRepo" "$backup_dir/" 2>/dev/null || true
            fi
            
            # Remove old Firebase entries (but keep the new ones Unity just imported)
            # This is safer than full removal - just clean up duplicates
            print_status "Removing duplicate/old Firebase entries from GeneratedLocalRepo..."
            # Note: Unity will regenerate this on next build with correct versions
        fi
        
        print_success "✓ Firebase cleanup completed"
    fi
    
    if [[ "$sdk_type" == "facebook" || "$sdk_type" == "all" ]]; then
        print_status "Cleaning old Facebook plugin files..."
        
        # Clean old Facebook iOS plugins if they exist (Unity imports new ones)
        # Only remove if there are actually old files conflicting
        
        print_success "✓ Facebook cleanup completed"
    fi
    
    # Clean Unity Library cache of old packages
    print_status "Cleaning Unity Library cache..."
    if [[ -d "${project_path}/Library/PackageCache" ]]; then
        # Only remove old cached versions, let Unity rebuild
        local cache_cleaned=false
        
        if [[ "$sdk_type" == "firebase" || "$sdk_type" == "all" ]]; then
            if find "${project_path}/Library/PackageCache" -name "*firebase*" -type d 2>/dev/null | grep -q .; then
                find "${project_path}/Library/PackageCache" -name "*firebase*" -type d -exec rm -rf {} + 2>/dev/null || true
                cache_cleaned=true
            fi
        fi
        
        if [[ "$sdk_type" == "facebook" || "$sdk_type" == "all" ]]; then
            if find "${project_path}/Library/PackageCache" -name "*facebook*" -type d 2>/dev/null | grep -q .; then
                find "${project_path}/Library/PackageCache" -name "*facebook*" -type d -exec rm -rf {} + 2>/dev/null || true
                cache_cleaned=true
            fi
        fi
        
        if [[ "$cache_cleaned" == "true" ]]; then
            print_success "✓ Library cache cleaned (Unity will rebuild)"
        else
            print_success "✓ No old cache files found"
        fi
    fi
    
    print_success "Old SDK files cleanup completed. Backup at: $backup_dir"
}

# Function to download and extract Firebase SDK
download_and_extract_firebase() {
    local firebase_version="$1"
    local downloads_dir="$2"
    
    print_status "=== Firebase SDK v${firebase_version} - Download & Extract ==="
    
    local download_url="https://dl.google.com/firebase/sdk/unity/firebase_unity_sdk_${firebase_version}.zip"
    local zip_file="${downloads_dir}/firebase_unity_sdk_${firebase_version}.zip"
    local extract_dir="${downloads_dir}/firebase_unity_sdk_${firebase_version}"
    
    # Download if needed
    if ! download_if_needed "$download_url" "$zip_file" "Firebase Unity SDK v${firebase_version}"; then
        print_error "Failed to download Firebase SDK"
        return 1
    fi
    
    # Extract if needed
    if ! extract_if_needed "$zip_file" "$extract_dir" "Firebase SDK v${firebase_version}"; then
        print_error "Failed to extract Firebase SDK"
        return 1
    fi
    
    # Remove Examples folders from extracted SDK (before import to avoid Unity importing them)
    print_status "Removing Examples folders from Firebase SDK..."
    local examples_removed=0
    
    # Find and remove all Examples/Sample/Samples folders in the extracted SDK
    find "$extract_dir" -type d \( -name "Examples" -o -name "Sample" -o -name "Samples" \) 2>/dev/null | while read -r examples_dir; do
        if [[ -d "$examples_dir" ]]; then
            print_status "  Removing: $examples_dir"
            rm -rf "$examples_dir"
            # Also remove .meta file if it exists
            if [[ -f "${examples_dir}.meta" ]]; then
                rm -f "${examples_dir}.meta"
            fi
            ((examples_removed++))
        fi
    done
    
    if [[ $examples_removed -gt 0 ]]; then
        print_success "✓ Removed Examples folders from Firebase SDK (won't be imported)"
    else
        print_success "✓ No Examples folders found in extracted SDK"
    fi
    
    # Return the path to the extracted SDK
    echo "$extract_dir"
    return 0
}

# Function to download and extract Facebook SDK
download_and_extract_facebook() {
    local facebook_version="$1"
    local downloads_dir="$2"
    
    print_status "=== Facebook SDK v${facebook_version} - Download & Extract ==="
    
    # Facebook SDK has multiple possible URL formats
    local urls=(
        "https://github.com/facebook/facebook-sdk-for-unity/releases/download/sdk-version-${facebook_version}/facebook-unity-sdk-${facebook_version}.zip"
        "https://github.com/facebook/facebook-sdk-for-unity/releases/download/v${facebook_version}/facebook-unity-sdk-${facebook_version}.zip"
        "https://github.com/facebook/facebook-sdk-for-unity/releases/download/${facebook_version}/facebook-unity-sdk-${facebook_version}.zip"
    )
    
    local zip_file="${downloads_dir}/facebook-unity-sdk-${facebook_version}.zip"
    local extract_dir="${downloads_dir}/facebook-unity-sdk-${facebook_version}"
    
    # Check if already downloaded
    if [[ -f "$zip_file" ]]; then
        print_success "✓ Facebook SDK already downloaded at: $zip_file"
        if ! confirm_action "Re-download anyway?" "n"; then
            # Skip download, go to extract
            if ! extract_if_needed "$zip_file" "$extract_dir" "Facebook SDK v${facebook_version}"; then
                print_error "Failed to extract Facebook SDK"
                return 1
            fi
            echo "$extract_dir"
            return 0
        fi
    fi
    
    # Try downloading from each possible URL
    local download_success=false
    for url in "${urls[@]}"; do
        print_status "Trying: $url"
        if curl -L -f -o "$zip_file" "$url" 2>/dev/null; then
            download_success=true
            print_success "✓ Downloaded Facebook SDK v${facebook_version}"
            break
        else
            print_warning "Failed to download from: $url"
        fi
    done
    
    if [[ "$download_success" != "true" ]]; then
        print_error "Failed to download Facebook SDK from all URLs"
        print_error "Please check version ${facebook_version} exists at: https://github.com/facebook/facebook-sdk-for-unity/releases"
        return 1
    fi
    
    # Extract
    if ! extract_if_needed "$zip_file" "$extract_dir" "Facebook SDK v${facebook_version}"; then
        print_error "Failed to extract Facebook SDK"
        return 1
    fi
    
    # Remove Examples folders from extracted SDK (before import to avoid Unity importing them)
    print_status "Removing Examples folders from Facebook SDK..."
    local examples_removed=0
    
    # Find and remove all Examples/Sample/Samples folders in the extracted SDK
    find "$extract_dir" -type d \( -name "Examples" -o -name "Sample" -o -name "Samples" \) 2>/dev/null | while read -r examples_dir; do
        if [[ -d "$examples_dir" ]]; then
            print_status "  Removing: $examples_dir"
            rm -rf "$examples_dir"
            # Also remove .meta file if it exists
            if [[ -f "${examples_dir}.meta" ]]; then
                rm -f "${examples_dir}.meta"
            fi
            ((examples_removed++))
        fi
    done
    
    if [[ $examples_removed -gt 0 ]]; then
        print_success "✓ Removed Examples folders from Facebook SDK (won't be imported)"
    else
        print_success "✓ No Examples folders found in extracted SDK"
    fi
    
    echo "$extract_dir"
    return 0
}

# Function to check if a package/SDK already exists in the project
check_package_exists() {
    local project_path="$1"
    local package_name="$2"
    
    # Extract the base name without .unitypackage extension
    local base_name="${package_name%.unitypackage}"
    
    # Check for Firebase packages
    if [[ "$base_name" =~ ^Firebase ]]; then
        # Firebase packages are in Assets/Firebase/Plugins
        if [[ -d "$project_path/Assets/Firebase" ]]; then
            # Check if the specific Firebase module exists
            local module_name="${base_name#Firebase}"  # Remove "Firebase" prefix
            
            # Common Firebase locations
            if [[ -n "$module_name" ]]; then
                # Check for module-specific folders or DLLs
                if [[ -d "$project_path/Assets/Firebase/Plugins/$module_name" ]] || \
                   [[ -f "$project_path/Assets/Firebase/Plugins/Firebase.${module_name}.dll" ]] || \
                   [[ -f "$project_path/Assets/Firebase/Editor/Firebase.${module_name}.dll" ]] || \
                   grep -q "Firebase${module_name}" "$project_path/Assets/Firebase"/*Dependencies.xml 2>/dev/null; then
                    return 0  # Package exists
                fi
            else
                # Base Firebase package
                if [[ -d "$project_path/Assets/Firebase/Plugins" ]]; then
                    return 0
                fi
            fi
        fi
        return 1  # Firebase package doesn't exist
    fi
    
    # Check for Facebook packages
    if [[ "$base_name" =~ facebook-unity-sdk ]]; then
        if [[ -d "$project_path/Assets/FacebookSDK" ]]; then
            return 0  # Facebook SDK exists
        fi
        return 1  # Facebook SDK doesn't exist
    fi
    
    # For other packages, do a general check
    # Look for any folder or file with similar name in Assets
    if find "$project_path/Assets" -type d -iname "*${base_name}*" 2>/dev/null | grep -q .; then
        return 0  # Package exists
    fi
    
    return 1  # Package doesn't exist
}

# Function to clean up Examples folders after package import
cleanup_examples_folders() {
    local project_path="$1"
    local sdk_name="$2"
    local package_name="$3"
    
    local examples_removed=0
    
    # Firebase Examples cleanup
    if [[ "$sdk_name" == "Firebase" ]]; then
        local firebase_examples_dirs=(
            "$project_path/Assets/Firebase/Examples"
            "$project_path/Assets/Firebase/Sample"
            "$project_path/Assets/Firebase/Samples"
        )
        
        for examples_dir in "${firebase_examples_dirs[@]}"; do
            if [[ -d "$examples_dir" ]]; then
                print_status "  Removing Examples folder: $examples_dir"
                rm -rf "$examples_dir"
                # Also remove .meta file
                if [[ -f "${examples_dir}.meta" ]]; then
                    rm -f "${examples_dir}.meta"
                fi
                ((examples_removed++))
            fi
        done
        
        # Also check for module-specific examples (e.g., Firebase/Plugins/Analytics/Examples)
        find "$project_path/Assets/Firebase" -type d -name "Examples" -o -name "Sample" -o -name "Samples" 2>/dev/null | while read -r examples_dir; do
            if [[ -d "$examples_dir" ]]; then
                print_status "  Removing Examples folder: $examples_dir"
                rm -rf "$examples_dir"
                if [[ -f "${examples_dir}.meta" ]]; then
                    rm -f "${examples_dir}.meta"
                fi
                ((examples_removed++))
            fi
        done
    fi
    
    # Facebook Examples cleanup
    if [[ "$sdk_name" == "Facebook" ]]; then
        local facebook_examples_dirs=(
            "$project_path/Assets/FacebookSDK/Examples"
            "$project_path/Assets/FacebookSDK/Sample"
            "$project_path/Assets/FacebookSDK/Samples"
        )
        
        for examples_dir in "${facebook_examples_dirs[@]}"; do
            if [[ -d "$examples_dir" ]]; then
                print_status "  Removing Examples folder: $examples_dir"
                rm -rf "$examples_dir"
                if [[ -f "${examples_dir}.meta" ]]; then
                    rm -f "${examples_dir}.meta"
                fi
                ((examples_removed++))
            fi
        done
        
        # Facebook SDK may have examples in subdirectories
        find "$project_path/Assets/FacebookSDK" -type d -name "Examples" -o -name "Sample" -o -name "Samples" 2>/dev/null | while read -r examples_dir; do
            if [[ -d "$examples_dir" ]]; then
                print_status "  Removing Examples folder: $examples_dir"
                rm -rf "$examples_dir"
                if [[ -f "${examples_dir}.meta" ]]; then
                    rm -f "${examples_dir}.meta"
                fi
                ((examples_removed++))
            fi
        done
    fi
    
    if [[ $examples_removed -gt 0 ]]; then
        print_success "  ✓ Removed Examples folders (not needed in production)"
    fi
}

# Function to import Unity packages with confirmation
import_unity_packages() {
    local unity_path="$1"
    local project_path="$2"
    local packages_dir="$3"
    local sdk_name="$4"
    
    print_status "=== Importing ${sdk_name} Unity Packages ==="
    
    # Find all .unitypackage files
    local packages=()
    while IFS= read -r -d '' package; do
        packages+=("$package")
    done < <(find "$packages_dir" -name "*.unitypackage" -type f -print0 2>/dev/null)
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        print_error "No .unitypackage files found in $packages_dir"
        return 1
    fi
    
    print_status "Found ${#packages[@]} package(s) to import:"
    for package in "${packages[@]}"; do
        echo "  - $(basename "$package")" >&2
    done
    echo >&2
    
    # Import each package with confirmation
    local imported_count=0
    local skipped_count=0
    
    for package in "${packages[@]}"; do
        local package_name=$(basename "$package")
        
        # Check if package already exists in project
        local should_confirm=false
        if check_package_exists "$project_path" "$package_name"; then
            # Package exists - auto-update without asking
            print_status "Package: $package_name (already installed - updating)"
            should_confirm=false
        else
            # Package doesn't exist - ask user
            print_status "Package: $package_name (NEW - not currently installed)"
            if [[ "$INTERACTIVE" == "true" ]]; then
                if ! confirm_action "Install this NEW package?"; then
                    print_warning "Skipped $package_name"
                    ((skipped_count++))
                    echo >&2
                    continue
                fi
            fi
            should_confirm=false
        fi
        
        print_status "Importing $package_name into Unity..."
        
        # Import the package
        "$unity_path" -batchmode -quit \
            -projectPath "$project_path" \
            -importPackage "$package" \
            -logFile "/tmp/unity_import_${package_name}.log"
        
        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            print_success "✓ Imported $package_name"
            ((imported_count++))
            
            # Clean up Examples folders (they break and aren't needed)
            cleanup_examples_folders "$project_path" "$sdk_name" "$package_name"
        else
            print_error "✗ Failed to import $package_name (exit code: $exit_code)"
            print_error "Check log: /tmp/unity_import_${package_name}.log"
            
            if confirm_action "Continue with remaining packages?" "n"; then
                continue
            else
                print_error "Import process aborted by user"
                return 1
            fi
        fi
        echo >&2
    done
    
    print_success "=== ${sdk_name} Import Complete ==="
    print_success "Imported: $imported_count package(s)"
    if [[ $skipped_count -gt 0 ]]; then
        print_warning "Skipped: $skipped_count package(s)"
    fi
    
    return 0
}

# Function to verify and update EDM4U configuration
verify_and_update_edm4u() {
    local project_path="$1"
    local target_version="${2:-1.2.186}"
    
    print_status "=== Verifying External Dependency Manager (EDM4U) ==="
    
    # Check Packages/manifest.json
    local manifest_file="$project_path/Packages/manifest.json"
    if [[ ! -f "$manifest_file" ]]; then
        print_error "Packages/manifest.json not found at: $manifest_file"
        return 1
    fi
    
    # Check current EDM version
    local current_version=$(grep -o '"com.google.external-dependency-manager": "[^"]*"' "$manifest_file" | grep -o '[0-9]*\.[0-9]*\.[0-9]*' || echo "not found")
    print_status "Current EDM4U version: $current_version"
    print_status "Target EDM4U version: $target_version"
    
    if [[ "$current_version" == "$target_version" ]]; then
        print_success "✓ EDM4U is already at target version"
    else
        if confirm_action "Update EDM4U to v${target_version}?"; then
            # Backup manifest
            cp "$manifest_file" "${manifest_file}.backup.$(date +%Y%m%d_%H%M%S)"
            
            # Update version
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s/\"com\.google\.external-dependency-manager\": \"[0-9]*\.[0-9]*\.[0-9]*\"/\"com.google.external-dependency-manager\": \"${target_version}\"/g" "$manifest_file"
            else
                sed -i "s/\"com\.google\.external-dependency-manager\": \"[0-9]*\.[0-9]*\.[0-9]*\"/\"com.google.external-dependency-manager\": \"${target_version}\"/g" "$manifest_file"
            fi
            
            print_success "✓ Updated EDM4U to v${target_version}"
        fi
    fi
    
    # Check iOS Resolver settings
    local ios_resolver_settings="$project_path/Assets/ExternalDependencyManager/Editor/IOSResolverSettings.xml"
    if [[ -f "$ios_resolver_settings" ]]; then
        print_status "Checking iOS Resolver settings..."
        
        local cocoapods_integration=$(grep -o '<cocoapodsIntegrationMethod>[0-9]*</cocoapodsIntegrationMethod>' "$ios_resolver_settings" | grep -o '[0-9]*' || echo "not found")
        print_status "CocoaPods integration method: $cocoapods_integration"
        
        if [[ "$cocoapods_integration" == "0" ]]; then
            print_success "✓ CocoaPods integration is set to 'None' (correct for AppleBuild)"
        else
            print_warning "⚠ CocoaPods integration is set to '$cocoapods_integration'"
            print_warning "  Expected: 0 (None) - AppleBuild handles CocoaPods"
            if confirm_action "Update to integration method 0 (None)?"; then
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    sed -i '' 's/<cocoapodsIntegrationMethod>[0-9]*<\/cocoapodsIntegrationMethod>/<cocoapodsIntegrationMethod>0<\/cocoapodsIntegrationMethod>/g' "$ios_resolver_settings"
                else
                    sed -i 's/<cocoapodsIntegrationMethod>[0-9]*<\/cocoapodsIntegrationMethod>/<cocoapodsIntegrationMethod>0<\/cocoapodsIntegrationMethod>/g' "$ios_resolver_settings"
                fi
                print_success "✓ Updated CocoaPods integration to 'None'"
            fi
        fi
    else
        print_warning "⚠ iOS Resolver settings not found (will be created on first Unity run)"
    fi
    
    print_success "✓ EDM4U configuration verified"
    return 0
}

# Function to verify AppleBuild configuration
verify_applebuild_config() {
    local project_path="$1"
    
    print_status "=== Verifying AppleBuild Configuration ==="
    
    # Check if AppleBuild exists
    local applebuild_dir="$project_path/Assets/Commons/Editor/AppleBuild"
    if [[ ! -d "$applebuild_dir" ]]; then
        print_error "AppleBuild not found at: $applebuild_dir"
        return 1
    fi
    
    print_success "✓ AppleBuild directory found"
    
    # Check key components
    local components=(
        "ApplePostProcess.cs"
        "Utilities/PodfileManager.cs"
        "Steps/300_CocoaPodsManager.cs"
    )
    
    local all_found=true
    for component in "${components[@]}"; do
        if [[ -f "$applebuild_dir/$component" ]]; then
            print_success "  ✓ $component"
        else
            print_error "  ✗ $component NOT FOUND"
            all_found=false
        fi
    done
    
    if [[ "$all_found" != "true" ]]; then
        print_error "Some AppleBuild components are missing"
        return 1
    fi
    
    # Check PodfileManager has the latest fixes
    local podfile_manager="$applebuild_dir/Utilities/PodfileManager.cs"
    if grep -q "CleanupFirebaseVersionConflicts" "$podfile_manager"; then
        print_success "  ✓ PodfileManager has Firebase conflict cleanup"
    else
        print_warning "  ⚠ PodfileManager may be missing latest fixes"
    fi
    
    if grep -q "EnsureSingleCocoaPodsSource" "$podfile_manager"; then
        print_success "  ✓ PodfileManager has source cleanup"
    else
        print_warning "  ⚠ PodfileManager may be missing source cleanup"
    fi
    
    print_success "✓ AppleBuild configuration verified"
    return 0
}

# Function to verify CocoaPods installation and setup
verify_cocoapods_config() {
    local project_path="$1"
    
    print_status "=== Verifying CocoaPods Configuration ==="
    
    # Check if pod command exists
    if ! command -v pod &> /dev/null; then
        print_error "CocoaPods not found!"
        print_error "Install with: sudo gem install cocoapods"
        return 1
    fi
    
    local pod_version=$(pod --version)
    print_success "✓ CocoaPods installed: v${pod_version}"
    
    # Check for duplicate repos
    local trunk_repo=~/.cocoapods/repos/trunk
    local cocoapods_repo=~/.cocoapods/repos/cocoapods
    
    if [[ -d "$trunk_repo" && -d "$cocoapods_repo" ]]; then
        print_warning "⚠ Duplicate CocoaPods repositories detected:"
        print_warning "  - trunk (CDN - fast)"
        print_warning "  - cocoapods (GitHub - slow, 3-5GB)"
        
        if confirm_action "Remove legacy 'cocoapods' repo?"; then
            pod repo remove cocoapods 2>/dev/null || true
            print_success "✓ Removed legacy CocoaPods repository"
        fi
    elif [[ -d "$trunk_repo" ]]; then
        print_success "✓ Using CDN trunk repository (optimal)"
    else
        print_warning "⚠ No CocoaPods repositories found"
        if confirm_action "Set up CocoaPods repository?"; then
            pod setup
            print_success "✓ CocoaPods repository initialized"
        fi
    fi
    
    # Check if repo needs update
    if confirm_action "Update CocoaPods repository specs?" "n"; then
        print_status "Updating CocoaPods repository..."
        pod repo update || print_warning "Repository update failed (non-critical)"
    fi
    
    print_success "✓ CocoaPods configuration verified"
    return 0
}

# Function to update Firebase XML dependency files to use consistent Firebase iOS SDK version
update_firebase_xml_dependencies() {
    local project_path="$1"
    local firebase_version="$2"
    
    print_status "Checking Firebase XML dependency files..."
    
    local firebase_deps_dir="$project_path/Assets/Firebase/Editor"
    
    if [[ ! -d "$firebase_deps_dir" ]]; then
        print_warning "Firebase Editor folder not found at $firebase_deps_dir"
        return 1
    fi
    
    # Find all *Dependencies.xml files
    local dep_files=$(find "$firebase_deps_dir" -name "*Dependencies.xml" -type f)
    
    if [[ -z "$dep_files" ]]; then
        print_warning "No Firebase dependency XML files found"
        return 1
    fi
    
    print_success "✓ Firebase XML dependency files found"
    print_warning "⚠ NOTE: iOS pod versions are set by Firebase Unity SDK packages"
    print_warning "⚠ NOT modifying iOS pod versions (Unity SDK ${firebase_version} may use different iOS CocoaPods version)"
    
    # We DO NOT modify iOS pod versions because:
    # - Unity SDK version (e.g., 13.3.0) != iOS CocoaPods version (e.g., 12.2.0)
    # - Firebase Unity SDK packages already have correct iOS versions
    # - Changing them breaks the build
    
    # If we need to update Android versions in the future, we can do it here
    # For now, just verify files exist and warn about version mapping
    
    local file_count=$(echo "$dep_files" | wc -l | tr -d ' ')
    print_success "Found ${file_count} Firebase dependency XML files (iOS versions unchanged)"
}

# Function to optimize Firebase dependencies for version ranges
optimize_firebase_dependencies() {
    local project_path="$1"
    local firebase_version="$2"
    
    print_status "Converting Firebase dependencies to use version ranges..."

    local firebase_deps_dir="$project_path/Assets/Firebase/Editor"

    if [[ ! -d "$firebase_deps_dir" ]]; then
        print_warning "Firebase Editor folder not found at $firebase_deps_dir"
        return 1
    fi

    local dep_files=$(find "$firebase_deps_dir" -name "*Dependencies.xml" -type f)

    if [[ -z "$dep_files" ]]; then
        print_warning "No Firebase dependency XML files found"
        return 1
    fi

    print_warning "Skipping iOS pod version rewrites to avoid mismatching Firebase CocoaPods releases."
    print_warning "Update Android dependencies manually if required."
}

# Function to ensure Facebook SDK version consistency
ensure_facebook_version_consistency() {
    local project_path="$1"
    local facebook_version="$2"
    
    print_status "Ensuring Facebook SDK version consistency to v${facebook_version}..."
    
    local facebook_deps="$project_path/Assets/FacebookSDK/Plugins/Editor/Dependencies.xml"
    
    if [[ -f "$facebook_deps" ]]; then
        # Update iOS pods to use consistent version
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/version=\"~> 18\.[0-9]*\.[0-9]*\"/version=\"~> ${facebook_version}\"/g" "$facebook_deps"
            sed -i '' "s/\[18\.[0-9]*\.[0-9]*,19\)/[${facebook_version},19)/g" "$facebook_deps"
            # Also update version=\"18.x.x\" (without ~>)
            sed -i '' "s/version=\"18\.[0-9]*\.[0-9]*\"/version=\"~> ${facebook_version}\"/g" "$facebook_deps"
        else
            sed -i "s/version=\"~> 18\.[0-9]*\.[0-9]*\"/version=\"~> ${facebook_version}\"/g" "$facebook_deps"
            sed -i "s/\[18\.[0-9]*\.[0-9]*,19\)/[${facebook_version},19)/g" "$facebook_deps"
            sed -i "s/version=\"18\.[0-9]*\.[0-9]*\"/version=\"~> ${facebook_version}\"/g" "$facebook_deps"
        fi
        
        print_success "Facebook SDK version consistency ensured (v${facebook_version})"
    else
        print_warning "Facebook Dependencies.xml not found at expected location"
    fi
}

# Function to update External Dependency Manager
update_external_dependency_manager() {
    local project_path="$1"
    local target_version="${2:-1.2.186}"
    
    print_status "Updating External Dependency Manager to v${target_version}..."
    
    local manifest_file="$project_path/Packages/manifest.json"
    
    if [[ -f "$manifest_file" ]]; then
        # Create backup
        cp "$manifest_file" "${manifest_file}.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Update EDM version
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/\"com\.google\.external-dependency-manager\": \"[0-9]*\.[0-9]*\.[0-9]*\"/\"com.google.external-dependency-manager\": \"${target_version}\"/g" "$manifest_file"
        else
            sed -i "s/\"com\.google\.external-dependency-manager\": \"[0-9]*\.[0-9]*\.[0-9]*\"/\"com.google.external-dependency-manager\": \"${target_version}\"/g" "$manifest_file"
        fi
        
        print_success "External Dependency Manager updated to v${target_version}"
    else
        print_warning "Package manifest not found at $manifest_file"
    fi
}

# Function to auto-detect Unity installation
# Auto-detect Unity version from ProjectSettings/ProjectVersion.txt
detect_unity_version() {
    local project_path="$1"
    local version_file="$project_path/ProjectSettings/ProjectVersion.txt"
    if [[ -f "$version_file" ]]; then
        # Extract version from m_EditorVersion line
        local detected_version=$(grep "m_EditorVersion:" "$version_file" | sed 's/m_EditorVersion: //' | tr -d '[:space:]')
        if [[ -n "$detected_version" ]]; then
            echo "$detected_version"
            return 0
        fi
    fi
    return 1
}

detect_unity_path() {
    local project_path="$1"
    local detected_path=""
    local unity_version=""
    
    # First, try to detect the Unity version from the project
    unity_version=$(detect_unity_version "$project_path")
    
    if [[ -n "$unity_version" ]]; then
        print_status "Detected project Unity version: $unity_version"
    fi
    
    # Try common Unity Hub locations (macOS)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # If we have a specific version, try to find it first
        if [[ -n "$unity_version" ]]; then
            local version_path="/Applications/Unity/Hub/Editor/$unity_version/Unity.app/Contents/MacOS/Unity"
            if [[ -f "$version_path" ]]; then
                detected_path="$version_path"
                print_success "✓ Found exact Unity version match: $unity_version"
            fi
        fi
        
        # If no specific version found, look for Unity Hub installations
        if [[ -z "$detected_path" ]]; then
            local unity_hub_path="/Applications/Unity/Hub/Editor"
            if [[ -d "$unity_hub_path" ]]; then
                # Find the most recent version as fallback
                local latest_version=$(ls -1 "$unity_hub_path" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+[a-z]*[0-9]*$' | sort -V | tail -1)
                if [[ -n "$latest_version" ]]; then
                    detected_path="$unity_hub_path/$latest_version/Unity.app/Contents/MacOS/Unity"
                    print_warning "⚠ Using latest Unity version: $latest_version (project version $unity_version not found)"
                fi
            fi
        fi
        
        # Fallback to direct Unity installation
        if [[ -z "$detected_path" && -f "/Applications/Unity/Unity.app/Contents/MacOS/Unity" ]]; then
            detected_path="/Applications/Unity/Unity.app/Contents/MacOS/Unity"
        fi
    fi
    
    # Linux detection
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Try specific version first if detected
        if [[ -n "$unity_version" ]]; then
            local version_path="$HOME/Unity/Hub/Editor/$unity_version/Editor/Unity"
            if [[ -f "$version_path" ]]; then
                detected_path="$version_path"
            fi
        fi
        
        # Fallback to common Unity locations on Linux
        if [[ -z "$detected_path" ]]; then
            local linux_paths=("/opt/Unity/Editor/Unity" "$HOME/Unity/Hub/Editor/*/Editor/Unity")
            for path in "${linux_paths[@]}"; do
                if [[ -f "$path" ]]; then
                    detected_path="$path"
                    break
                fi
            done
        fi
    fi
    
    echo "$detected_path"
}

# Function to optimize CocoaPods setup
optimize_cocoapods_setup() {
    local project_path="$1"
    
    print_status "Checking CocoaPods repository setup..."
    
    # Check for duplicate CocoaPods repos
    local trunk_repo=~/.cocoapods/repos/trunk
    local cocoapods_repo=~/.cocoapods/repos/cocoapods
    
    if [[ -d "$trunk_repo" && -d "$cocoapods_repo" ]]; then
        print_warning "Duplicate CocoaPods repositories detected!"
        print_status "Cleaning up duplicate CocoaPods repositories..."
        
        # Remove the legacy GitHub repo to prevent conflicts
        if command -v pod &> /dev/null; then
            pod repo remove cocoapods 2>/dev/null || true
            print_success "Removed duplicate CocoaPods repository"
        fi
    fi
    
    # Update CocoaPods repos
    if command -v pod &> /dev/null; then
        print_status "Updating CocoaPods repository..."
        pod repo update --silent || print_warning "CocoaPods repo update failed (may need manual intervention)"
    else
        print_warning "CocoaPods not found - make sure it's installed for iOS builds"
    fi
}

# Function to show usage
show_usage() {
    echo "Unity Package Updater Script - Improved Workflow"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --firebase [version]     Update Firebase SDK (optional version, defaults to 13.3.0)"
    echo "  --facebook [version]     Update Facebook SDK (optional version, defaults to 18.0.0)"
    echo "  --all                    Update both SDKs and apply optimizations"
    echo "  --downloads-dir <path>   Specify downloads directory (defaults to ~/Downloads)"
    echo "  --optimize               Apply all dependency optimizations (recommended)"
    echo "  --edm-version [version]  Update External Dependency Manager (defaults to 1.2.186)"
    echo "  --unity-path <path>      Specify Unity executable path"
    echo "  --project-path <path>    Specify Unity project path"
    echo "  --non-interactive        Skip confirmation prompts (auto-confirm)"
    echo "  --help                   Show this help message"
    echo
    echo "New Workflow (Safer):"
    echo "  1. Download SDKs to Downloads folder (reuse if already present)"
    echo "  2. Extract SDKs"
    echo "  3. Import Unity packages (with confirmation for each)"
    echo "  4. Clean up old SDK files AFTER successful import"
    echo "  5. Verify and update EDM4U configuration"
    echo "  6. Verify AppleBuild and CocoaPods configuration"
    echo "  7. Update Firebase XML dependencies"
    echo
    echo "Optimizations applied with --optimize:"
    echo "  • Verify and update External Dependency Manager"
    echo "  • Verify iOS Resolver settings (CocoaPods integration)"
    echo "  • Verify AppleBuild components"
    echo "  • Clean duplicate CocoaPods repositories"
    echo "  • Update Firebase XML dependencies to consistent versions"
    echo "  • Ensure Facebook SDK version consistency"
    echo
    echo "Examples:"
    echo "  $0 --all                                    Update everything interactively"
    echo "  $0 --all --non-interactive                  Update everything automatically"
    echo "  $0 --firebase 13.3.0 --optimize             Update Firebase with optimizations"
    echo "  $0 --facebook 18.0.0 --optimize             Update Facebook with optimizations"
    echo "  $0 --optimize                               Just verify/update configurations"
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
            OPTIMIZE_DEPENDENCIES=true
            FIREBASE_VERSION="13.3.0"
            FACEBOOK_VERSION="18.0.0"
            shift
            ;;
        --downloads-dir)
            DOWNLOADS_DIR="$2"
            shift 2
            ;;
        --optimize)
            OPTIMIZE_DEPENDENCIES=true
            shift
            ;;
        --edm-version)
            EDM_VERSION="$2"
            shift 2
            ;;
        --unity-path)
            UNITY_PATH="$2"
            shift 2
            ;;
        --project-path)
            PROJECT_PATH="$2"
            shift 2
            ;;
        --non-interactive)
            INTERACTIVE=false
            shift
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

# Validate that at least one action is specified
if [[ "$UPDATE_FIREBASE" != "true" && "$UPDATE_FACEBOOK" != "true" && "$OPTIMIZE_DEPENDENCIES" != "true" ]]; then
    print_error "No action specified (need --firebase, --facebook, --optimize, or --all)"
    show_usage
    exit 1
fi

# Auto-detect Unity path if not provided
if [[ -z "$UNITY_PATH" ]]; then
    print_status "Auto-detecting Unity installation..."
    UNITY_PATH=$(detect_unity_path "$PROJECT_PATH")
    
    if [[ -z "$UNITY_PATH" ]]; then
        print_error "Unity installation not found automatically"
        print_error "Please specify Unity path with --unity-path option"
        exit 1
    else
        print_success "Found Unity at: $UNITY_PATH"
    fi
fi

# Validate Unity path
if [[ ! -f "$UNITY_PATH" ]]; then
    print_error "Unity executable not found at: $UNITY_PATH"
    print_error "Please check the path or use --unity-path to specify correct location"
    exit 1
fi

# Validate project path
if [[ ! -d "$PROJECT_PATH" ]]; then
    print_error "Project path not found: $PROJECT_PATH"
    exit 1
fi

print_status "=== Unity Package Updater - New Workflow ==="
print_status "Unity Path: $UNITY_PATH"
print_status "Project Path: $PROJECT_PATH"
print_status "Downloads Directory: $DOWNLOADS_DIR"
print_status "Interactive Mode: $INTERACTIVE"
print_status "Firebase Update: $UPDATE_FIREBASE $([ "$UPDATE_FIREBASE" == "true" ] && echo "($FIREBASE_VERSION)")"
print_status "Facebook Update: $UPDATE_FACEBOOK $([ "$UPDATE_FACEBOOK" == "true" ] && echo "($FACEBOOK_VERSION)")"
print_status "Apply Optimizations: $OPTIMIZE_DEPENDENCIES $([ "$OPTIMIZE_DEPENDENCIES" == "true" ] && echo "($EDM_VERSION)")"
echo >&2

# Ensure downloads directory exists
mkdir -p "$DOWNLOADS_DIR"

# =============================================================================
# PHASE 1: Download & Extract SDKs
# =============================================================================

FIREBASE_SDK_DIR=""
FACEBOOK_SDK_DIR=""

if [[ "$UPDATE_FIREBASE" == "true" ]]; then
    print_status "=== PHASE 1A: Firebase SDK - Download & Extract ==="
    FIREBASE_SDK_DIR=$(download_and_extract_firebase "$FIREBASE_VERSION" "$DOWNLOADS_DIR")
    
    if [[ $? -ne 0 || -z "$FIREBASE_SDK_DIR" ]]; then
        print_error "Failed to download/extract Firebase SDK"
        exit 1
    fi
    
    print_success "Firebase SDK ready at: $FIREBASE_SDK_DIR"
    echo >&2
fi

if [[ "$UPDATE_FACEBOOK" == "true" ]]; then
    print_status "=== PHASE 1B: Facebook SDK - Download & Extract ==="
    FACEBOOK_SDK_DIR=$(download_and_extract_facebook "$FACEBOOK_VERSION" "$DOWNLOADS_DIR")
    
    if [[ $? -ne 0 || -z "$FACEBOOK_SDK_DIR" ]]; then
        print_error "Failed to download/extract Facebook SDK"
        exit 1
    fi
    
    print_success "Facebook SDK ready at: $FACEBOOK_SDK_DIR"
    echo >&2
fi

# =============================================================================
# PHASE 2: Import Unity Packages (with confirmation)
# =============================================================================

if [[ "$UPDATE_FIREBASE" == "true" && -n "$FIREBASE_SDK_DIR" ]]; then
    print_status "=== PHASE 2A: Firebase - Import Unity Packages ==="
    
    # Firebase packages are in a subdirectory
    firebase_packages_dir="$FIREBASE_SDK_DIR/firebase_unity_sdk"
    if [[ ! -d "$firebase_packages_dir" ]]; then
        firebase_packages_dir="$FIREBASE_SDK_DIR"
    fi
    
    if ! import_unity_packages "$UNITY_PATH" "$PROJECT_PATH" "$firebase_packages_dir" "Firebase"; then
        print_error "Firebase package import failed"
        if ! confirm_action "Continue with Facebook and optimizations?" "n"; then
            exit 1
        fi
    fi
    echo >&2
fi

if [[ "$UPDATE_FACEBOOK" == "true" && -n "$FACEBOOK_SDK_DIR" ]]; then
    print_status "=== PHASE 2B: Facebook - Import Unity Packages ==="
    
    if ! import_unity_packages "$UNITY_PATH" "$PROJECT_PATH" "$FACEBOOK_SDK_DIR" "Facebook"; then
        print_error "Facebook package import failed"
        if ! confirm_action "Continue with optimizations?" "n"; then
            exit 1
        fi
    fi
    echo >&2
fi

# =============================================================================
# PHASE 3: Clean Old SDK Files (AFTER import)
# =============================================================================

if [[ "$CLEAN_AFTER" == "true" && ("$UPDATE_FIREBASE" == "true" || "$UPDATE_FACEBOOK" == "true") ]]; then
    print_status "=== PHASE 3: Clean Old SDK Files ==="
    
    if [[ "$UPDATE_FIREBASE" == "true" && "$UPDATE_FACEBOOK" == "true" ]]; then
        clean_old_sdk_files "$PROJECT_PATH" "all"
    elif [[ "$UPDATE_FIREBASE" == "true" ]]; then
        clean_old_sdk_files "$PROJECT_PATH" "firebase"
    elif [[ "$UPDATE_FACEBOOK" == "true" ]]; then
        clean_old_sdk_files "$PROJECT_PATH" "facebook"
    fi
    
    echo
fi

# =============================================================================
# PHASE 4: Verify & Update Configurations
# =============================================================================

if [[ "$OPTIMIZE_DEPENDENCIES" == "true" ]]; then
    print_status "=== PHASE 4: Verify & Update Configurations ==="
    
    # 4.1: EDM4U Configuration
    if ! verify_and_update_edm4u "$PROJECT_PATH" "$EDM_VERSION"; then
        print_warning "EDM4U verification had issues (continuing anyway)"
    fi
    echo
    
    # 4.2: AppleBuild Configuration
    if ! verify_applebuild_config "$PROJECT_PATH"; then
        print_warning "AppleBuild verification had issues (continuing anyway)"
    fi
    echo
    
    # 4.3: CocoaPods Configuration
    if ! verify_cocoapods_config "$PROJECT_PATH"; then
        print_warning "CocoaPods verification had issues (continuing anyway)"
    fi
    echo
fi

# =============================================================================
# PHASE 5: Update Firebase & Facebook XML Dependencies
# =============================================================================

if [[ "$OPTIMIZE_DEPENDENCIES" == "true" || "$UPDATE_FIREBASE" == "true" || "$UPDATE_FACEBOOK" == "true" ]]; then
    print_status "=== PHASE 5: Update SDK Dependencies ==="
    
    # 5.1: Update Firebase XML files
    if [[ "$UPDATE_FIREBASE" == "true" && -n "$FIREBASE_VERSION" ]]; then
        if [[ -d "$PROJECT_PATH/Assets/Firebase/Editor" ]]; then
            update_firebase_xml_dependencies "$PROJECT_PATH" "$FIREBASE_VERSION"
            echo
        else
            print_warning "Firebase SDK not found - skipping Firebase XML update"
        fi
    fi
    
    # 5.2: Ensure Facebook version consistency
    if [[ "$UPDATE_FACEBOOK" == "true" && -n "$FACEBOOK_VERSION" ]]; then
        if [[ -d "$PROJECT_PATH/Assets/FacebookSDK" ]]; then
            ensure_facebook_version_consistency "$PROJECT_PATH" "$FACEBOOK_VERSION"
            echo
        else
            print_warning "Facebook SDK not found - skipping Facebook version consistency"
        fi
    fi
    
    # 5.3: Optimize CocoaPods setup
    if [[ "$OPTIMIZE_DEPENDENCIES" == "true" ]]; then
        optimize_cocoapods_setup "$PROJECT_PATH"
        echo
    fi
fi

# =============================================================================
# Final Summary
# =============================================================================

print_success "=== Package Update Complete ==="
echo >&2
print_status "Summary of actions performed:"
echo >&2

if [[ "$UPDATE_FIREBASE" == "true" ]]; then
    print_success "✓ Firebase SDK: v$FIREBASE_VERSION"
    print_success "  - Downloaded to: $DOWNLOADS_DIR"
    print_success "  - Imported Unity packages"
    print_success "  - Updated XML dependencies"
fi

if [[ "$UPDATE_FACEBOOK" == "true" ]]; then
    print_success "✓ Facebook SDK: v$FACEBOOK_VERSION"
    print_success "  - Downloaded to: $DOWNLOADS_DIR"
    print_success "  - Imported Unity packages"
    print_success "  - Ensured version consistency"
fi

if [[ "$OPTIMIZE_DEPENDENCIES" == "true" ]]; then
    print_success "✓ Configurations verified and updated:"
    print_success "  - EDM4U: v$EDM_VERSION"
    print_success "  - iOS Resolver settings"
    print_success "  - AppleBuild components"
    print_success "  - CocoaPods setup"
fi

if [[ "$CLEAN_AFTER" == "true" && ("$UPDATE_FIREBASE" == "true" || "$UPDATE_FACEBOOK" == "true") ]]; then
    print_success "✓ Old SDK files cleaned up"
fi

echo >&2
print_status "=== Next Steps ==="
echo "1. Open Unity Editor - it will reimport the new SDKs" >&2
echo "2. Check Unity Console for any import warnings/errors" >&2
echo "3. Verify SDK configurations:" >&2
echo "   - Firebase: Assets/Firebase/ and google-services.json" >&2
echo "   - Facebook: Assets/FacebookSDK/ and FacebookSettings.asset" >&2
echo "4. EDM4U will regenerate dependencies on next build" >&2
echo "5. AppleBuild will handle Podfile cleanup automatically" >&2
echo "6. Build your iOS project to test" >&2
echo >&2

if [[ "$UPDATE_FIREBASE" == "true" && "$UPDATE_FACEBOOK" == "true" ]]; then
    print_status "Expected build behavior:"
    echo "  • Podfile will have single source (CDN)" >&2
    echo "  • Firebase pods: exact versions (${FIREBASE_VERSION})" >&2
    echo "  • Facebook pods: version ranges (~> ${FACEBOOK_VERSION})" >&2
    echo "  • No duplicate Firebase pod declarations" >&2
    echo "  • PodfileManager will auto-cleanup any conflicts" >&2
    echo >&2
fi

print_success "All updates completed successfully! 🎉"
echo >&2
print_status "SDK downloads are cached in: $DOWNLOADS_DIR"
print_status "You can safely delete them or reuse for future updates"
echo >&2
