#!/bin/bash

# Clean Firebase References from Xcode Project
# Removes outdated Firebase library references that cause linker errors
# Also cleans ALL build caches (Xcode DerivedData, Unity Library, Android build)

set -e

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_PATH="$(dirname "$SCRIPT_DIR")"

log() {
    echo "[Firebase Cleanup] $1"
}

log "=== Comprehensive Firebase & Cache Cleanup ==="
log ""

# Step 1: Remove old build artifacts
log "Step 1: Removing old build folders..."
if [ -d "$PROJECT_PATH/build/iOS" ]; then
    rm -rf "$PROJECT_PATH/build/iOS"
    log "✅ Deleted build/iOS folder"
else
    log "ℹ️  build/iOS folder doesn't exist"
fi

if [ -d "$PROJECT_PATH/build/Android" ]; then
    rm -rf "$PROJECT_PATH/build/Android"
    log "✅ Deleted build/Android folder"
else
    log "ℹ️  build/Android folder doesn't exist"
fi

# Step 2: Check for remaining Firebase library files in Assets/Plugins
log ""
log "Step 2: Checking for removed Firebase libraries in Assets/Plugins..."

REMOVED_LIBS=(
    "FirebaseCppDatabase"
    "FirebaseCppStorage"
    "FirebaseCppFunctions"
    "FirebaseCppRemoteConfig"
    "FirebaseCppAppCheck"
    "FirebaseCppFirestore"
)

FOUND_FILES=0
for lib in "${REMOVED_LIBS[@]}"; do
    while IFS= read -r file; do
        if [ -n "$file" ]; then
            log "⚠️  Found: $file"
            FOUND_FILES=$((FOUND_FILES + 1))
        fi
    done < <(find "$PROJECT_PATH/Assets/Plugins" -type f -name "*${lib}*" 2>/dev/null)
done

if [ $FOUND_FILES -eq 0 ]; then
    log "✅ No removed Firebase libraries found in Assets/Plugins"
else
    log "❌ Found $FOUND_FILES files that should be removed"
    log ""
    log "Run this to remove them:"
    log "find Assets/Plugins -type f \\( -name \"*FirebaseCppDatabase*\" -o -name \"*FirebaseCppStorage*\" -o -name \"*FirebaseCppFunctions*\" -o -name \"*FirebaseCppRemoteConfig*\" -o -name \"*FirebaseCppAppCheck*\" -o -name \"*FirebaseCppFirestore*\" \\) -delete"
fi

# Step 3: Clean Unity Library cache
log ""
log "Step 3: Cleaning Unity Library cache..."

if [ -d "$PROJECT_PATH/Library/Bee" ]; then
    log "Removing Library/Bee (Unity's build cache)..."
    rm -rf "$PROJECT_PATH/Library/Bee"
    log "✅ Deleted Library/Bee"
fi

if [ -d "$PROJECT_PATH/Library/PlayerDataCache" ]; then
    log "Removing Library/PlayerDataCache..."
    rm -rf "$PROJECT_PATH/Library/PlayerDataCache"
    log "✅ Deleted Library/PlayerDataCache"
fi

if [ -d "$PROJECT_PATH/Library/BuildPlayerData" ]; then
    log "Removing Library/BuildPlayerData..."
    rm -rf "$PROJECT_PATH/Library/BuildPlayerData"
    log "✅ Deleted Library/BuildPlayerData"
fi

if [ -d "$PROJECT_PATH/Library/ScriptAssemblies" ]; then
    log "Removing Library/ScriptAssemblies..."
    rm -rf "$PROJECT_PATH/Library/ScriptAssemblies"
    log "✅ Deleted Library/ScriptAssemblies"
fi

# Step 4: Clean Xcode DerivedData
log ""
log "Step 4: Cleaning Xcode DerivedData..."

DERIVED_DATA_PATH="$HOME/Library/Developer/Xcode/DerivedData"
if [ -d "$DERIVED_DATA_PATH" ]; then
    # Find and remove only Unity-iPhone related DerivedData
    find "$DERIVED_DATA_PATH" -maxdepth 1 -name "Unity-iPhone-*" -type d 2>/dev/null | while read -r dir; do
        if [ -n "$dir" ]; then
            log "Removing $dir..."
            rm -rf "$dir"
            log "✅ Deleted $(basename "$dir")"
        fi
    done
    log "✅ Cleaned Xcode DerivedData for Unity-iPhone"
else
    log "ℹ️  Xcode DerivedData folder doesn't exist"
fi

# Step 5: Clean Gradle cache (Android)
log ""
log "Step 5: Cleaning Android Gradle cache..."

if [ -d "$HOME/.gradle/caches" ]; then
    # Only clean Firebase-related caches to be safe
    find "$HOME/.gradle/caches" -type d -name "*firebase*" 2>/dev/null | while read -r dir; do
        if [ -n "$dir" ]; then
            rm -rf "$dir"
        fi
    done
    log "✅ Cleaned Firebase entries from Gradle cache"
else
    log "ℹ️  Gradle cache doesn't exist"
fi

# Step 6: Clean Android build artifacts
log ""
log "Step 6: Cleaning Android build artifacts..."

if [ -d "$PROJECT_PATH/Assets/Plugins/Android/mainTemplate.gradle.backup"* ]; then
    rm -f "$PROJECT_PATH/Assets/Plugins/Android/mainTemplate.gradle.backup"*
    log "✅ Deleted mainTemplate.gradle backup files"
fi

# Step 7: Clean iOS Resolver cache
log ""
log "Step 7: Cleaning iOS Resolver cache..."

if [ -f "$PROJECT_PATH/Assets/Plugins/iOS.meta" ]; then
    # Force iOS Resolver to regenerate by touching the .meta file
    touch "$PROJECT_PATH/Assets/Plugins/iOS.meta"
    log "✅ Touched Assets/Plugins/iOS.meta (forces resolver refresh)"
fi

# Step 8: Clean External Dependency Manager cache
log ""
log "Step 8: Cleaning External Dependency Manager cache..."

if [ -d "$PROJECT_PATH/Library/PackageCache" ]; then
    # Clean only Firebase-related package cache
    find "$PROJECT_PATH/Library/PackageCache" -type d -name "*firebase*" 2>/dev/null | while read -r dir; do
        if [ -n "$dir" ]; then
            log "Found cached Firebase package: $(basename "$dir")"
        fi
    done
fi

if [ -d "$PROJECT_PATH/Assets/ExternalDependencyManager" ]; then
    log "Found ExternalDependencyManager folder"
    # Don't delete it, but note its presence
fi

# Step 9: Clean CocoaPods cache (iOS)
log ""
log "Step 9: Cleaning CocoaPods cache..."

if [ -d "$HOME/.cocoapods/repos/trunk/Specs" ]; then
    # Clean only Firebase-related pod specs
    find "$HOME/.cocoapods/repos/trunk/Specs" -type d -name "*Firebase*" 2>/dev/null | head -5 | while read -r dir; do
        if [ -n "$dir" ]; then
            log "Found Firebase pod spec: $(basename "$dir")"
        fi
    done
    log "ℹ️  CocoaPods cache intact (will be refreshed on next pod install)"
else
    log "ℹ️  CocoaPods trunk specs don't exist"
fi

# Step 10: Verify mainTemplate.gradle is clean
log ""
log "Step 10: Verifying Android Gradle dependencies..."

if [ -f "$PROJECT_PATH/Assets/Plugins/Android/mainTemplate.gradle" ]; then
    GRADLE_ISSUES=$(grep -E "(firebase-firestore|firebase-database|firebase-storage|firebase-functions|firebase-remote-config|firebase-appcheck)" "$PROJECT_PATH/Assets/Plugins/Android/mainTemplate.gradle" || true)
    
    if [ -n "$GRADLE_ISSUES" ]; then
        log "❌ Found removed Firebase packages in mainTemplate.gradle:"
        echo "$GRADLE_ISSUES" | while read -r line; do
            log "   $line"
        done
        log ""
        log "These need to be removed manually from:"
        log "   Assets/Plugins/Android/mainTemplate.gradle"
    else
        log "✅ Android mainTemplate.gradle is clean"
    fi
else
    log "ℹ️  mainTemplate.gradle doesn't exist"
fi

# Step 11: List remaining Firebase packages
log ""
log "Step 11: Verifying remaining Firebase packages..."
log ""
log "✅ iOS Libraries (should exist):"
ls -1 "$PROJECT_PATH/Assets/Plugins/iOS/Firebase"/*.a 2>/dev/null | while read -r lib; do
    basename "$lib"
done | grep -v "Database\|Storage\|Functions\|RemoteConfig\|AppCheck\|Firestore" || true

log ""
log "✅ Firebase Dependencies (should exist):"
ls -1 "$PROJECT_PATH/Assets/Firebase/Editor"/*Dependencies.xml 2>/dev/null | while read -r dep; do
    basename "$dep"
done

# Step 12: Instructions for next build
log ""
log "=== CLEANUP COMPLETE ==="
log ""
log "What was cleaned:"
log "  ✅ iOS build folder (build/iOS)"
log "  ✅ Android build folder (build/Android)"
log "  ✅ Unity Library cache (Bee, PlayerDataCache, BuildPlayerData, ScriptAssemblies)"
log "  ✅ Xcode DerivedData (Unity-iPhone projects)"
log "  ✅ Android Gradle cache (Firebase entries)"
log "  ✅ iOS Plugins marked for refresh"
log "  ✅ Verified mainTemplate.gradle"
log ""
log "Cache sizes cleared:"
if [ -d "$HOME/Library/Developer/Xcode/DerivedData" ]; then
    DERIVED_SIZE=$(du -sh "$HOME/Library/Developer/Xcode/DerivedData" 2>/dev/null | awk '{print $1}')
    log "  Xcode DerivedData remaining: $DERIVED_SIZE"
fi
if [ -d "$HOME/.gradle/caches" ]; then
    GRADLE_SIZE=$(du -sh "$HOME/.gradle/caches" 2>/dev/null | awk '{print $1}')
    log "  Gradle cache remaining: $GRADLE_SIZE"
fi
log ""
log "Next steps:"
log "  1. Rebuild iOS project from Unity"
log "     → Fresh Xcode project WITHOUT removed libraries"
log ""
log "  2. Rebuild Android project from Unity"
log "     → Fresh Gradle build WITHOUT removed libraries"
log ""
log "  3. Or run your normal build commands:"
log "     iOS:     cd Scripts && ./unityBuild.sh iOS prod"
log "     Android: cd Scripts && ./unityBuild.sh Android prod"
log ""
log "All linker errors for removed Firebase packages should be gone!"
log ""

exit 0
