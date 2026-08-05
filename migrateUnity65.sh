#!/usr/bin/env bash

set -euo pipefail

UNITY_VERSION="6000.5.3f1"
UNITY_REVISION="c2eb47b3a2a9"
PROJECT_PATH=""
APPLY=false

usage() {
    cat <<'EOF'
Usage: migrateUnity65.sh --project <path> [--apply]

Without --apply, audits a Unity project for the shared Unity 6.5 migration
requirements. With --apply, performs only deterministic text migrations, then
runs the same audit. Package lockfiles and Unity-serialized settings are left to
Unity 6.5.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)
            PROJECT_PATH="${2:-}"
            shift 2
            ;;
        --apply)
            APPLY=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$PROJECT_PATH" ]]; then
    echo "--project is required" >&2
    exit 2
fi

PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"
MANIFEST="$PROJECT_PATH/Packages/manifest.json"
PROJECT_VERSION="$PROJECT_PATH/ProjectSettings/ProjectVersion.txt"
PLAYER_SETTINGS="$PROJECT_PATH/ProjectSettings/ProjectSettings.asset"

for required in "$MANIFEST" "$PROJECT_VERSION" "$PLAYER_SETTINGS"; do
    if [[ ! -f "$required" ]]; then
        echo "Required Unity project file not found: $required" >&2
        exit 2
    fi
done

replace_in_file() {
    local file="$1"
    local from="$2"
    local to="$3"
    [[ -f "$file" ]] || return 0
    FROM="$from" TO="$to" perl -0pi -e 's/\Q$ENV{FROM}\E/$ENV{TO}/g' "$file"
}

set_json_dependency_version() {
    local package="$1"
    local version="$2"
    PACKAGE="$package" VERSION="$version" perl -0pi -e '
        s/("\Q$ENV{PACKAGE}\E"\s*:\s*")[^"]+(")/$1$ENV{VERSION}$2/g
    ' "$MANIFEST"
}

apply_shared_migration() {
    printf 'm_EditorVersion: %s\nm_EditorVersionWithRevision: %s (%s)\n' \
        "$UNITY_VERSION" "$UNITY_VERSION" "$UNITY_REVISION" > "$PROJECT_VERSION"

    replace_in_file "$PROJECT_PATH/project-config.sh" 'export UNITY_VERSION="6000.3.7f1"' "export UNITY_VERSION=\"$UNITY_VERSION\""
    replace_in_file "$PROJECT_PATH/project-config.sh" 'export UNITY_VERSION="6000.3.17f1"' "export UNITY_VERSION=\"$UNITY_VERSION\""
    replace_in_file "$PROJECT_PATH/.github/workflows/main.yml" 'UNITY_VERSION: "6000.3.7f1"' "UNITY_VERSION: \"$UNITY_VERSION\""
    replace_in_file "$PROJECT_PATH/.github/workflows/main.yml" 'UNITY_VERSION: "6000.3.17f1"' "UNITY_VERSION: \"$UNITY_VERSION\""

    local script_file
    for script_file in \
        "$PROJECT_PATH/Scripts/project-config.template.sh" \
        "$PROJECT_PATH/Scripts/runAddressablesDoctor.sh" \
        "$PROJECT_PATH/Scripts/runBoardDoctor.sh" \
        "$PROJECT_PATH/Scripts/runGameDoctor.sh" \
        "$PROJECT_PATH/Scripts/runSmokeTests.sh" \
        "$PROJECT_PATH/Scripts/runSmokeTestsIsolated.sh" \
        "$PROJECT_PATH/Scripts/setupSelfHostedRunner-Linux.sh" \
        "$PROJECT_PATH/Scripts/setupSelfHostedRunner-Windows.ps1" \
        "$PROJECT_PATH/Scripts/testPodfileManager.sh" \
        "$PROJECT_PATH/Scripts/unityBuild.sh" \
        "$PROJECT_PATH/Scripts/updateFacebook.sh" \
        "$PROJECT_PATH/Scripts/updateFirebase.sh" \
        "$PROJECT_PATH/Scripts/verifyAndroidEnv.sh" \
        "$PROJECT_PATH/Scripts/.env.android.local"; do
        replace_in_file "$script_file" '6000.3.7f1' "$UNITY_VERSION"
        replace_in_file "$script_file" '6000.3.17f1' "$UNITY_VERSION"
    done

    set_json_dependency_version "com.coffee.ui-particle" "https://github.com/mob-sakai/ParticleEffectForUGUI.git?path=Packages/src#d4e7aa839f94b38aec1feb7f21ad12afee6712a2"
    set_json_dependency_version "com.google.external-dependency-manager" "1.2.187"
    set_json_dependency_version "com.google.ads.mobile" "11.2.0"
    set_json_dependency_version "com.unity.2d.animation" "15.1.0"
    set_json_dependency_version "com.unity.2d.psdimporter" "14.0.3"
    set_json_dependency_version "com.unity.addressables" "2.9.1"
    set_json_dependency_version "com.unity.ads" "4.19.0"
    set_json_dependency_version "com.unity.collab-proxy" "2.12.4"
    set_json_dependency_version "com.unity.ide.visualstudio" "2.0.27"
    set_json_dependency_version "com.unity.inputsystem" "1.19.0"
    set_json_dependency_version "com.unity.memoryprofiler" "1.1.12"
    set_json_dependency_version "com.unity.mobile.notifications" "2.4.3"
    set_json_dependency_version "com.unity.purchasing" "5.4.1"
    set_json_dependency_version "com.unity.render-pipelines.universal" "17.5.0"
    set_json_dependency_version "com.unity.services.authentication" "3.7.3"
    set_json_dependency_version "com.unity.services.vivox" "16.11.0"
    set_json_dependency_version "com.unity.test-framework" "1.7.0"
    set_json_dependency_version "com.unity.timeline" "1.8.12"
    set_json_dependency_version "com.unity.ugui" "2.5.0"
    set_json_dependency_version "com.unity.visualeffectgraph" "17.5.0"

    if ! grep -q '"com.unity.modules.physicscore2d"' "$MANIFEST"; then
        perl -0pi -e 's/("com\.unity\.modules\.physics2d"\s*:\s*"1\.0\.0",)/$1\n    "com.unity.modules.physicscore2d": "1.0.0",/' "$MANIFEST"
    fi
    perl -0pi -e 's/^\s*"com\.unity\.modules\.vr"\s*:\s*"1\.0\.0",?\r?\n//m' "$MANIFEST"

    perl -0pi -e 's/(AndroidMinSdkVersion:)\s*\d+/$1 26/' "$PLAYER_SETTINGS"
    perl -0pi -e 's/(AndroidTargetSdkVersion:)\s*\d+/$1 36/' "$PLAYER_SETTINGS"

    local gradle_properties="$PROJECT_PATH/Assets/Plugins/Android/gradleTemplate.properties"
    if [[ -f "$gradle_properties" ]]; then
        perl -0pi -e 's/^android\.enableJetifier\s*=.*\r?\n//m' "$gradle_properties"
    fi
}

errors=0
warnings=0

ok() { printf '  OK   %s\n' "$*"; }
warn() { printf '  WARN %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf '  FAIL %s\n' "$*"; errors=$((errors + 1)); }

check_literal() {
    local file="$1"
    local literal="$2"
    local label="$3"
    if [[ -f "$file" ]] && grep -Fq "$literal" "$file"; then
        ok "$label"
    else
        fail "$label"
    fi
}

audit_project() {
    echo "Unity 6.5 migration audit: $PROJECT_PATH"
    check_literal "$PROJECT_VERSION" "m_EditorVersion: $UNITY_VERSION" "Editor pinned to $UNITY_VERSION"
    check_literal "$MANIFEST" '"com.google.external-dependency-manager": "1.2.187"' "EDM4U 1.2.187"
    check_literal "$MANIFEST" '"com.unity.addressables": "2.9.1"' "Addressables 2.9.1"
    check_literal "$MANIFEST" '"com.unity.render-pipelines.universal": "17.5.0"' "URP 17.5.0"
    check_literal "$MANIFEST" '"com.unity.ugui": "2.5.0"' "UGUI 2.5.0"
    check_literal "$PLAYER_SETTINGS" 'AndroidMinSdkVersion: 26' "Android minSdk 26"

    if grep -q '"com.google.ads.mobile"' "$MANIFEST"; then
        check_literal "$MANIFEST" '"com.google.ads.mobile": "11.2.0"' "Google Mobile Ads 11.2.0"
    else
        warn "Google Mobile Ads package is not declared"
    fi

    if grep -Rqs '6000\.3\.' \
        "$PROJECT_PATH/project-config.sh" \
        "$PROJECT_PATH/.github/workflows" \
        "$PROJECT_PATH/Scripts" 2>/dev/null; then
        fail "Executable configuration still references Unity 6000.3"
    else
        ok "No executable configuration references Unity 6000.3"
    fi

    if grep -Rqs '^android\.enableJetifier\s*=\s*true' "$PROJECT_PATH/Assets/Plugins/Android" 2>/dev/null; then
        fail "Jetifier is still enabled"
    else
        ok "Jetifier is disabled/absent"
    fi

    if find "$PROJECT_PATH/Assets/Packages" -iname '*System.Runtime.CompilerServices.Unsafe*.dll' -print -quit 2>/dev/null | grep -q .; then
        fail "NuGet Unsafe DLL is still present"
    else
        ok "No NuGet Unsafe DLL"
    fi

    if find "$PROJECT_PATH/Assets/Packages" -path '*ZLinq.1.5.6*' -print -quit 2>/dev/null | grep -q .; then
        ok "ZLinq 1.5.6 present"
    else
        warn "ZLinq 1.5.6 not found"
    fi

    local androidlib gradle namespace_missing=0
    while IFS= read -r androidlib; do
        gradle="$androidlib/build.gradle"
        [[ -f "$gradle" ]] || continue
        if ! grep -Eq '(^|[[:space:]])namespace([[:space:]]|=)' "$gradle"; then
            printf '       missing namespace: %s\n' "${gradle#"$PROJECT_PATH/"}"
            namespace_missing=$((namespace_missing + 1))
        fi
    done < <(find "$PROJECT_PATH/Assets/Plugins/Android" -type d -name '*.androidlib' 2>/dev/null | sort)
    if [[ "$namespace_missing" -eq 0 ]]; then
        ok "All Android libraries declare namespaces"
    else
        fail "$namespace_missing Android libraries lack namespaces"
    fi

    local firebase_version
    firebase_version=$(find "$PROJECT_PATH/Assets/Firebase/m2repository/com/google/firebase/firebase-app-unity" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sed 's#.*/##' | sort -V | tail -1)
    if [[ "$firebase_version" == "13.13.0" ]]; then
        ok "Firebase Unity SDK 13.13.0"
    elif [[ -n "$firebase_version" ]]; then
        warn "Firebase Unity SDK detected: $firebase_version (expected 13.13.0)"
    else
        warn "Firebase Unity SDK version could not be detected"
    fi

    local gpgs_package="$PROJECT_PATH/Assets/GooglePlayGames/com.google.play.games/package.json"
    if [[ -f "$gpgs_package" ]]; then
        check_literal "$gpgs_package" '"version": "2.1.0"' "Google Play Games plugin 2.1.0"
    else
        warn "Google Play Games plugin is not installed"
    fi

    local facebook_dependencies="$PROJECT_PATH/Assets/FacebookSDK/Plugins/Editor/Dependencies.xml"
    if [[ -f "$facebook_dependencies" ]]; then
        check_literal "$facebook_dependencies" 'facebook-core:[18.3.0,19)' "Facebook SDK Android dependencies 18.3.x"
        check_literal "$facebook_dependencies" 'FBSDKCoreKit" version="~> 18.1.0"' "Facebook SDK iOS dependencies 18.1.x"
    else
        warn "Facebook SDK is not installed"
    fi

    if grep -Rqs 'UNITY_6000_5_OR_NEWER' "$PROJECT_PATH/Packages/com.esotericsoftware.spine.spine-unity" 2>/dev/null; then
        ok "Embedded Spine Unity 6.5 compatibility guards found"
    else
        warn "Embedded Spine Unity 6.5 compatibility package not found"
    fi

    echo "Audit result: $errors failure(s), $warnings warning(s)"
    [[ "$errors" -eq 0 ]]
}

if $APPLY; then
    echo "Applying deterministic Unity 6.5 migration to $PROJECT_PATH"
    apply_shared_migration
fi

audit_project
