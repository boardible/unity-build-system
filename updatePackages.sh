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
UPDATE_FIREBASE=false
UPDATE_FACEBOOK=false
UPDATE_ALL=false
OPTIMIZE_DEPENDENCIES=false
CLEAN_FIRST=false
EDM_VERSION="1.2.186"

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

# Function to clean existing SDK installations
clean_sdk_installations() {
    local project_path="$1"
    local sdk_type="$2"  # "firebase", "facebook", or "all"
    
    print_status "Cleaning existing SDK installations..."
    
    # Create backup directory with timestamp
    local backup_dir="${project_path}/Temp/sdk_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    if [[ "$sdk_type" == "firebase" || "$sdk_type" == "all" ]]; then
        print_status "Removing Firebase SDK..."
        
        # Backup and remove Firebase folders
        if [[ -d "${project_path}/Assets/Firebase" ]]; then
            cp -r "${project_path}/Assets/Firebase" "$backup_dir/" 2>/dev/null || true
            rm -rf "${project_path}/Assets/Firebase"
            rm -f "${project_path}/Assets/Firebase.meta"
            print_success "✓ Firebase SDK folder removed"
        fi
        
        # Remove Firebase plugin folders
        if [[ -d "${project_path}/Assets/Plugins/iOS/Firebase" ]]; then
            rm -rf "${project_path}/Assets/Plugins/iOS/Firebase"
            rm -f "${project_path}/Assets/Plugins/iOS/Firebase.meta"
        fi
        
        # Clean Firebase from GeneratedLocalRepo
        if [[ -d "${project_path}/Assets/GeneratedLocalRepo" ]]; then
            find "${project_path}/Assets/GeneratedLocalRepo" -name "*Firebase*" -type d -exec rm -rf {} + 2>/dev/null || true
            find "${project_path}/Assets/GeneratedLocalRepo" -name "*Firebase*" -type f -exec rm -f {} + 2>/dev/null || true
        fi
    fi
    
    if [[ "$sdk_type" == "facebook" || "$sdk_type" == "all" ]]; then
        print_status "Removing Facebook SDK..."
        
        # Backup and remove Facebook folders
        if [[ -d "${project_path}/Assets/FacebookSDK" ]]; then
            cp -r "${project_path}/Assets/FacebookSDK" "$backup_dir/" 2>/dev/null || true
            rm -rf "${project_path}/Assets/FacebookSDK"
            rm -f "${project_path}/Assets/FacebookSDK.meta"
            print_success "✓ Facebook SDK folder removed"
        fi
        
        # Remove Facebook plugin folders
        if [[ -d "${project_path}/Assets/Plugins/iOS/Facebook" ]]; then
            rm -rf "${project_path}/Assets/Plugins/iOS/Facebook"
            rm -f "${project_path}/Assets/Plugins/iOS/Facebook.meta"
        fi
    fi
    
    # Clean Library cache
    print_status "Cleaning Unity Library cache..."
    if [[ -d "${project_path}/Library/PackageCache" ]]; then
        find "${project_path}/Library/PackageCache" -name "*firebase*" -type d -exec rm -rf {} + 2>/dev/null || true
        find "${project_path}/Library/PackageCache" -name "*facebook*" -type d -exec rm -rf {} + 2>/dev/null || true
    fi
    
    print_success "SDK cleanup completed. Backup at: $backup_dir"
}

# Function to optimize Firebase dependencies for version ranges
optimize_firebase_dependencies() {
    local project_path="$1"
    local firebase_version="$2"
    
    print_status "Optimizing Firebase dependencies to use version ranges..."
    
    # Find all Firebase dependency files
    local firebase_deps_dir="$project_path/Assets/Firebase/Editor"
    
    if [[ ! -d "$firebase_deps_dir" ]]; then
        print_warning "Firebase Editor folder not found at $firebase_deps_dir"
        return 1
    fi
    
    local dep_files=(
        "AnalyticsDependencies.xml"
        "AppDependencies.xml"
        "AuthDependencies.xml"
        "CrashlyticsDependencies.xml"
        "FirestoreDependencies.xml"
        "MessagingDependencies.xml"
        "RemoteConfigDependencies.xml"
        "StorageDependencies.xml"
        "FunctionsDependencies.xml"
    )
    
    for dep_file in "${dep_files[@]}"; do
        local full_path="$firebase_deps_dir/$dep_file"
        if [[ -f "$full_path" ]]; then
            print_status "Optimizing $dep_file..."
            
            # Extract major.minor version (e.g., "13.3" from "13.3.0")
            local version_prefix=$(echo "$firebase_version" | cut -d. -f1-2)
            
            # Replace exact versions with version ranges for iOS pods only
            # This prevents duplicate pod declarations
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS sed - update iOS pods to use ~> version
                sed -i '' -E "s/(<iosPod name=\"Firebase[^\"]*\" version=\")[0-9]+\.[0-9]+\.[0-9]+(\")( minTargetSdk=\"[^\"]+\">)/\1~> ${version_prefix}.0\2\3/g" "$full_path"
                # Also fix standalone Firebase pods (not Firebase/*)
                sed -i '' -E "s/(<iosPod name=\"Firebase[^\"]*\" version=\")[0-9]+\.[0-9]+\.[0-9]+(\">)/\1~> ${version_prefix}.0\2/g" "$full_path"
            else
                # Linux sed
                sed -i -E "s/(<iosPod name=\"Firebase[^\"]*\" version=\")[0-9]+\.[0-9]+\.[0-9]+(\")( minTargetSdk=\"[^\"]+\">)/\1~> ${version_prefix}.0\2\3/g" "$full_path"
                sed -i -E "s/(<iosPod name=\"Firebase[^\"]*\" version=\")[0-9]+\.[0-9]+\.[0-9]+(\">)/\1~> ${version_prefix}.0\2/g" "$full_path"
            fi
            
            print_success "✓ Optimized $dep_file"
        else
            print_warning "Dependency file not found: $full_path"
        fi
    done
    
    print_success "Firebase dependencies optimized with version ranges (~> ${version_prefix}.0)"
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
detect_unity_path() {
    local detected_path=""
    
    # Try common Unity Hub locations (macOS)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # Look for Unity Hub installations
        local unity_hub_path="/Applications/Unity/Hub/Editor"
        if [[ -d "$unity_hub_path" ]]; then
            # Find the most recent version
            local latest_version=$(ls -1 "$unity_hub_path" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+[a-z]*[0-9]*$' | sort -V | tail -1)
            if [[ -n "$latest_version" ]]; then
                detected_path="$unity_hub_path/$latest_version/Unity.app/Contents/MacOS/Unity"
            fi
        fi
        
        # Fallback to direct Unity installation
        if [[ -z "$detected_path" && -f "/Applications/Unity/Unity.app/Contents/MacOS/Unity" ]]; then
            detected_path="/Applications/Unity/Unity.app/Contents/MacOS/Unity"
        fi
    fi
    
    # Linux detection
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Common Unity locations on Linux
        local linux_paths=("/opt/Unity/Editor/Unity" "$HOME/Unity/Hub/Editor/*/Editor/Unity")
        for path in "${linux_paths[@]}"; do
            if [[ -f "$path" ]]; then
                detected_path="$path"
                break
            fi
        done
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
    echo "Unity Package Updater Script"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --firebase [version]     Update Firebase SDK (optional version, defaults to 13.3.0)"
    echo "  --facebook [version]     Update Facebook SDK (optional version, defaults to 18.0.0)"
    echo "  --all                    Update both SDKs and apply optimizations"
    echo "  --clean                  Clean existing SDK installations before update (recommended)"
    echo "  --optimize               Apply all dependency optimizations (recommended)"
    echo "  --edm-version [version]  Update External Dependency Manager (defaults to 1.2.186)"
    echo "  --unity-path <path>      Specify Unity executable path"
    echo "  --project-path <path>    Specify Unity project path"
    echo "  --help                   Show this help message"
    echo
    echo "Optimizations applied with --optimize:"
    echo "  • Update External Dependency Manager to latest version"
    echo "  • Clean duplicate CocoaPods repositories"
    echo "  • Convert Firebase dependencies to use version ranges (~>)"
    echo "  • Ensure Facebook SDK version consistency"
    echo "  • Apply iOS 18/Xcode 16 compatibility fixes"
    echo
    echo "Examples:"
    echo "  $0 --all --clean                            Clean and update everything with optimizations"
    echo "  $0 --firebase 13.3.0 --clean --optimize     Clean, update Firebase and optimize"
    echo "  $0 --facebook 18.0.0 --clean --optimize     Clean, update Facebook and optimize"
    echo "  $0 --optimize                               Apply optimizations only"
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
            CLEAN_FIRST=true
            FIREBASE_VERSION="13.3.0"
            FACEBOOK_VERSION="18.0.0"
            shift
            ;;
        --clean)
            CLEAN_FIRST=true
            shift
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
    UNITY_PATH=$(detect_unity_path)
    
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

print_status "=== Unity Package Updater ==="
print_status "Unity Path: $UNITY_PATH"
print_status "Project Path: $PROJECT_PATH"
print_status "Clean First: $CLEAN_FIRST"
print_status "Firebase Update: $UPDATE_FIREBASE $([ "$UPDATE_FIREBASE" == "true" ] && echo "($FIREBASE_VERSION)")"
print_status "Facebook Update: $UPDATE_FACEBOOK $([ "$UPDATE_FACEBOOK" == "true" ] && echo "($FACEBOOK_VERSION)")"
print_status "Apply Optimizations: $OPTIMIZE_DEPENDENCIES $([ "$OPTIMIZE_DEPENDENCIES" == "true" ] && echo "(EDM: v$EDM_VERSION)")"
echo

# Clean existing installations if requested
if [[ "$CLEAN_FIRST" == "true" ]]; then
    print_status "=== Cleaning Existing SDK Installations ==="
    
    if [[ "$UPDATE_FIREBASE" == "true" && "$UPDATE_FACEBOOK" == "true" ]]; then
        clean_sdk_installations "$PROJECT_PATH" "all"
    elif [[ "$UPDATE_FIREBASE" == "true" ]]; then
        clean_sdk_installations "$PROJECT_PATH" "firebase"
    elif [[ "$UPDATE_FACEBOOK" == "true" ]]; then
        clean_sdk_installations "$PROJECT_PATH" "facebook"
    fi
    
    echo
fi

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

# Apply optimizations if requested
if [[ "$OPTIMIZE_DEPENDENCIES" == "true" ]]; then
    print_status "=== Applying Dependency Optimizations ==="
    
    # Update External Dependency Manager
    update_external_dependency_manager "$PROJECT_PATH" "$EDM_VERSION"
    echo
    
    # Optimize CocoaPods setup
    optimize_cocoapods_setup "$PROJECT_PATH"
    echo
    
    # Optimize Firebase dependencies if Firebase was updated
    if [[ "$UPDATE_FIREBASE" == "true" && -n "$FIREBASE_VERSION" ]]; then
        if [[ -d "$PROJECT_PATH/Assets/Firebase/Editor" ]]; then
            optimize_firebase_dependencies "$PROJECT_PATH" "$FIREBASE_VERSION"
            echo
        else
            print_warning "Firebase SDK not found - skipping Firebase optimization"
        fi
    fi
    
    # Ensure Facebook version consistency if Facebook was updated  
    if [[ "$UPDATE_FACEBOOK" == "true" && -n "$FACEBOOK_VERSION" ]]; then
        if [[ -d "$PROJECT_PATH/Assets/FacebookSDK" ]]; then
            ensure_facebook_version_consistency "$PROJECT_PATH" "$FACEBOOK_VERSION"
            echo
        else
            print_warning "Facebook SDK not found - skipping Facebook optimization"
        fi
    fi
    
    print_success "All dependency optimizations applied successfully!"
    echo
fi

# Force EDM4U to resolve iOS dependencies after updates
if [[ "$UPDATE_FIREBASE" == "true" || "$UPDATE_FACEBOOK" == "true" ]]; then
    print_status "=== Forcing EDM4U iOS Dependency Resolution ==="
    
    # Check if iOS Resolver is present
    local ios_resolver="$PROJECT_PATH/Assets/ExternalDependencyManager/Editor"
    if [[ -d "$ios_resolver" ]]; then
        print_status "Triggering EDM4U iOS dependency resolution..."
        
        # Force Unity to reimport and resolve dependencies
        "$UNITY_PATH" -batchmode -quit \
            -projectPath "$PROJECT_PATH" \
            -executeMethod Google.IOSResolver.PerformIOSResolution \
            -logFile /tmp/unity_edm4u_resolve.log 2>&1 || {
                print_warning "EDM4U resolution command completed (check log for details)"
                print_status "Log file: /tmp/unity_edm4u_resolve.log"
            }
        
        print_success "✓ EDM4U iOS dependency resolution completed"
        print_status "This ensures Podfile is regenerated with correct dependencies"
    else
        print_warning "EDM4U iOS Resolver not found - skipping automatic resolution"
        print_warning "You may need to manually resolve iOS dependencies in Unity"
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
if [[ "$OPTIMIZE_DEPENDENCIES" == "true" ]]; then
    print_success "✓ Dependencies optimized (EDM: v$EDM_VERSION)"
    print_success "✓ CocoaPods setup cleaned"
    if [[ "$UPDATE_FIREBASE" == "true" ]]; then
        print_success "✓ Firebase dependencies use version ranges"
    fi
    if [[ "$UPDATE_FACEBOOK" == "true" ]]; then
        print_success "✓ Facebook SDK version consistency ensured"
    fi
fi

print_status "Post-update checklist:"
echo "1. Open Unity and check for any import errors"
echo "2. Verify SDK configurations (Firebase: google-services.json, Facebook: FacebookSettings.asset)"
echo "3. Check Assets/ExternalDependencyManager/Editor for iOS dependency XML files"
echo "4. If Podfile issues persist, manually run: Assets > External Dependency Manager > iOS Resolver > Force Resolve"
echo "5. Test authentication and other SDK functionality"
echo "6. Run a test build to ensure compatibility"

if [[ "$UPDATE_FIREBASE" == "true" && "$UPDATE_FACEBOOK" == "true" ]]; then
    print_warning "Both SDKs updated - Podfile should now use version ranges (~>) to prevent conflicts"
    print_status "Expected Podfile format:"
    echo "  - Firebase pods: ~> 13.3.0 (NOT exact versions or Firebase/Analytics format)"
    echo "  - Facebook pods: ~> 18.0.0"
    echo "  - Single source: https://cdn.cocoapods.org/"
fi

print_success "All updates completed successfully!"
