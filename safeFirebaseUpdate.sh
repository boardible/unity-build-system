#!/bin/bash

# Safe Firebase Update Script
# Temporarily handles compilation issues during Firebase SDK updates

set -e

FIREBASE_VERSION=${1:-"13.3.0"}
UNITY_PATH=${2:-"/Applications/Unity/Hub/Editor/6000.0.58f1/Unity.app/Contents/MacOS/Unity"}
PROJECT_PATH=${3:-"/Users/pedromartinez/Dev/ineuj"}

echo "=== Safe Firebase Unity SDK Update ==="
echo "Version: $FIREBASE_VERSION"
echo "This script will temporarily disable scripts that cause compilation errors"
echo

# Backup problematic scripts
FACEBOOK_SCRIPT="$PROJECT_PATH/Assets/Commons/Runtime/Services/AppFacebook.cs"
FACEBOOK_BACKUP="$PROJECT_PATH/Assets/Commons/Runtime/Services/AppFacebook.cs.backup"

if [[ -f "$FACEBOOK_SCRIPT" ]]; then
    echo "Backing up AppFacebook.cs to prevent compilation errors..."
    cp "$FACEBOOK_SCRIPT" "$FACEBOOK_BACKUP"
    
    # Create a temporary stub file
    cat > "$FACEBOOK_SCRIPT" << 'EOF'
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using UnityEngine;
using Cysharp.Threading.Tasks;
using System;

// Temporary stub during Firebase SDK update
public class AppFacebook : AppBaseSystem<AppFacebook>
{
    private List<Action> callbacksAfterInit = new List<Action>();
    private UniTaskCompletionSource<bool> internalTask;
    private UniTaskCompletionSource<bool> loginTask;

    protected override async UniTask OnLoad()
    {
        Debug.LogWarning("AppFacebook is temporarily disabled during Firebase SDK update");
        await UniTask.CompletedTask;
    }

    public void Initialize(System.Action callback = null)
    {
        Debug.LogWarning("AppFacebook.Initialize called but temporarily disabled");
        callback?.Invoke();
    }

    // Add minimal stubs for common methods
    public bool IsLoggedIn { get { return false; } }
    public void Login(System.Action<bool> callback) { callback?.Invoke(false); }
    public void Logout() { }
}
EOF
    echo "Created temporary AppFacebook stub"
fi

# Run the Firebase update
echo "Running Firebase SDK update..."
"$PROJECT_PATH/Scripts/updateFirebase.sh" "$FIREBASE_VERSION" "$UNITY_PATH" "$PROJECT_PATH"

FIREBASE_RESULT=$?

# Restore the original Facebook script
if [[ -f "$FACEBOOK_BACKUP" ]]; then
    echo "Restoring original AppFacebook.cs..."
    mv "$FACEBOOK_BACKUP" "$FACEBOOK_SCRIPT"
    echo "Original AppFacebook.cs restored"
fi

if [[ $FIREBASE_RESULT -eq 0 ]]; then
    echo "Firebase SDK update completed successfully!"
    echo "Note: You may need to update Facebook SDK to resolve any remaining compilation issues"
else
    echo "Firebase SDK update failed"
    exit 1
fi