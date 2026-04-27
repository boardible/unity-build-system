#!/usr/bin/env bash
# Static Code Quality Checks for Unity Project
# Run this script in CI or locally before commits

set -e  # Exit on any error

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ERRORS=0

echo "🔍 Running Static Code Quality Checks..."
echo "Project Root: $PROJECT_ROOT"
echo ""

# Check 1: Debug.Log in production code
echo "📋 Check 1: Searching for Debug.Log in production code..."
if grep -r "Debug\.Log\|Debug\.LogWarning" \
    "$PROJECT_ROOT/Assets/App" \
    "$PROJECT_ROOT/Assets/Commons/Runtime" \
    --include="*.cs" \
    --exclude-dir="Editor" \
    --exclude-dir="Tests" \
    | grep -v "#if.*EDITOR" \
    | grep -v "#if.*BUILD_TYPE_DEV" \
    | grep -v "LogError" \
    | grep -v "LogException"; then
    
    echo "❌ Found Debug.Log/LogWarning in production code"
    echo "   Use Debug.LogError for errors, or wrap in #if BUILD_TYPE_DEV"
    ERRORS=$((ERRORS + 1))
else
    echo "✅ No Debug.Log found in production code"
fi
echo ""

# Check 2: .Forget() without .LogAndForget()
echo "📋 Check 2: Searching for .Forget() without error logging..."
if grep -r "\.Forget()" \
    "$PROJECT_ROOT/Assets/App" \
    "$PROJECT_ROOT/Assets/Commons/Runtime" \
    --include="*.cs" \
    | grep -v "LogAndForget" \
    | grep -v "// OK: No error handling needed" \
    | grep -v "Tests/"; then
    
    echo "❌ Found .Forget() calls without .LogAndForget()"
    echo "   Use .LogAndForget() to ensure errors are tracked"
    ERRORS=$((ERRORS + 1))
else
    echo "✅ All async operations use .LogAndForget()"
fi
echo ""

# Check 3: Duplicate SerializeField attributes
echo "📋 Check 3: Searching for duplicate SerializeField attributes..."
if grep -r "\[SerializeField\].*\[field: SerializeField\]" \
    "$PROJECT_ROOT/Assets" \
    --include="*.cs"; then
    
    echo "❌ Found duplicate [SerializeField] attributes"
    echo "   Use only [field: SerializeField] for properties"
    ERRORS=$((ERRORS + 1))
else
    echo "✅ No duplicate SerializeField attributes"
fi
echo ""

# Check 4: SafeRegisterListener usage (prevent memory leaks)
echo "📋 Check 4: Checking for unsafe event subscriptions..."
UNSAFE_PATTERNS=(
    "OnNotificationEvent\.AddListener"
    "OnChange\.AddListener"
    "valueUpdated\.AddListener"
    "AllUpdated\.AddListener"
)

for pattern in "${UNSAFE_PATTERNS[@]}"; do
    if grep -r "$pattern" \
        "$PROJECT_ROOT/Assets/App" \
        --include="*.cs" \
        | grep -v "SafeRegisterListener" \
        | grep -v "Tests/"; then
        
        echo "⚠️  Found unsafe event subscription: $pattern"
        echo "   Use this.SafeRegisterListener() to prevent memory leaks"
        # Don't increment errors - this is a warning
    fi
done
echo "✅ Event subscription check complete"
echo ""

# Check 5: MainMenu/Gameplay namespace violations
echo "📋 Check 5: Checking for assembly boundary violations..."
if grep -r "using Boardible\.Gameplay" \
    "$PROJECT_ROOT/Assets/App/MainMenu" \
    --include="*.cs"; then
    
    echo "❌ Found Gameplay namespace in MainMenu code"
    echo "   MainMenu cannot reference Gameplay (assembly boundary)"
    ERRORS=$((ERRORS + 1))
fi

if grep -r "using Boardible\.MainMenu" \
    "$PROJECT_ROOT/Assets/App/Gameplay" \
    --include="*.cs"; then
    
    echo "❌ Found MainMenu namespace in Gameplay code"
    echo "   Gameplay cannot reference MainMenu (assembly boundary)"
    ERRORS=$((ERRORS + 1))
fi

echo "✅ Assembly boundaries respected"
echo ""

# Check 6: App-specific types in Commons
echo "📋 Check 6: Checking for app-specific types in Commons..."
APP_TYPES=(
    "INEUJConfigs"
    "AppRoom"
    "GameInfo"
)

for type in "${APP_TYPES[@]}"; do
    if grep -r "$type" \
        "$PROJECT_ROOT/Assets/Commons/Runtime" \
        --include="*.cs" \
        --exclude-dir="Tests" \
        | grep -v "// OK: Commons extension point"; then
        
        echo "❌ Found app-specific type '$type' in Commons"
        echo "   Commons must remain project-agnostic"
        ERRORS=$((ERRORS + 1))
    fi
done
echo "✅ Commons remains project-agnostic"
echo ""

# Check 7: Legacy hidden game-root references
echo "📋 Check 7: Checking for legacy hidden game-root references..."
if python3 "$PROJECT_ROOT/Scripts/check_no_gamesrepo_refs.py"; then
    echo "✅ No unexpected hidden game-root references found"
else
    echo "❌ Found unexpected hidden game-root references"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Summary
echo "═══════════════════════════════════════"
if [ $ERRORS -eq 0 ]; then
    echo "✅ All checks passed! Code quality is good."
    exit 0
else
    echo "❌ $ERRORS check(s) failed. Please fix the issues above."
    exit 1
fi
