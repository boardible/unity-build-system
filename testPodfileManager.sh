#!/bin/bash

# Test script to verify PodfileManager.EnsureSingleCocoaPodsSource() works

echo "=== Testing Podfile Source Cleanup ==="
echo ""

# Create a test Podfile with duplicate sources
TEST_PODFILE="/tmp/test_podfile_$(date +%s).rb"

cat > "$TEST_PODFILE" << 'EOF'
source 'https://cdn.cocoapods.org/'
source 'https://cdn.cocoapods.org/'

platform :ios, '16.0'

target 'UnityFramework' do
  pod 'Firebase/Core', '11.14.0'
end
EOF

echo "Created test Podfile with duplicate sources:"
echo "---"
cat "$TEST_PODFILE"
echo "---"
echo ""

# Run Unity command to test the PodfileManager
echo "Running Unity test..."
/Applications/Unity/Hub/Editor/6000.2.12f1/Unity.app/Contents/MacOS/Unity \
  -quit \
  -batchmode \
  -nographics \
  -projectPath "$(pwd)" \
  -executeMethod TestPodfileManager.TestEnsureSingleSource \
  -logFile /tmp/unity_podfile_test.log \
  -testPodfile "$TEST_PODFILE"

if [ $? -eq 0 ]; then
    echo ""
    echo "Unity command completed. Check results:"
    echo "---"
    cat "$TEST_PODFILE"
    echo "---"
    echo ""
    
    # Count sources
    SOURCE_COUNT=$(grep "^source" "$TEST_PODFILE" | wc -l | tr -d ' ')
    
    if [ "$SOURCE_COUNT" -eq 1 ]; then
        echo "✅ SUCCESS: Only one source line found"
        SOURCE=$(grep "^source" "$TEST_PODFILE")
        if [[ "$SOURCE" == *"cdn.cocoapods.org"* ]]; then
            echo "✅ SUCCESS: Source is CDN (correct)"
        else
            echo "❌ FAIL: Source is not CDN: $SOURCE"
        fi
    else
        echo "❌ FAIL: Found $SOURCE_COUNT source lines (should be 1)"
        grep "^source" "$TEST_PODFILE"
    fi
else
    echo "❌ Unity command failed"
    echo "Check log: /tmp/unity_podfile_test.log"
fi

# Cleanup
rm -f "$TEST_PODFILE"
