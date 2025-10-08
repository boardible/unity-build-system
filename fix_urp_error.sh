#!/bin/bash
# Fix URP Global Settings NullReferenceException

echo "🔧 Fixing URP Global Settings error..."
echo ""
echo "Unity Editor should be closed!"
echo ""
read -p "Press Enter to continue with cleanup..."

# Backup current Library
echo ""
echo "📦 Creating backup of Library/ScriptAssemblies..."
if [ -d "Library/ScriptAssemblies" ]; then
    cp -r Library/ScriptAssemblies Library/ScriptAssemblies.backup
    echo "✅ Backup created"
fi

# Clear problematic caches
echo ""
echo "🗑️ Clearing Unity caches..."
rm -rf Library/ScriptAssemblies
rm -rf Library/Artifacts
rm -rf Library/StateCache
rm -rf Library/APIUpdater
rm -rf Temp

# Clear Addressables temp data
echo "🗑️ Clearing Addressables temporary data..."
rm -rf Library/aa
find Library/PackageCache -type d -name "LinkXMLGenerator" -exec rm -rf {} + 2>/dev/null || true

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "📝 Next steps:"
echo "   1. Reopen your project in Unity Editor"
echo "   2. Wait for Unity to reimport and recompile"
echo "   3. The error should be resolved"
echo ""
