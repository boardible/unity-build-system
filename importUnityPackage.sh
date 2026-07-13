#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <package.unitypackage> <unity-project-path>" >&2
    exit 2
fi

package_path="$1"
project_path="$2"

if [[ ! -f "$package_path" ]]; then
    echo "Unity package not found: $package_path" >&2
    exit 1
fi

if [[ ! -d "$project_path/Assets" ]]; then
    echo "Unity project not found: $project_path" >&2
    exit 1
fi

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/unitypackage.XXXXXX")"
trap 'rm -rf "$temp_dir"' EXIT

tar -xzf "$package_path" -C "$temp_dir"

imported=0
while IFS= read -r -d '' pathname_file; do
    source_dir="$(dirname "$pathname_file")"
    relative_path="$(<"$pathname_file")"

    case "$relative_path" in
        Assets/*|Packages/*) ;;
        *)
            echo "Refusing path outside Assets/Packages: $relative_path" >&2
            exit 1
            ;;
    esac

    target_path="$project_path/$relative_path"

    if [[ -f "$source_dir/asset" ]]; then
        mkdir -p "$(dirname "$target_path")"
        cp -p "$source_dir/asset" "$target_path"
    else
        mkdir -p "$target_path"
    fi

    if [[ -f "$source_dir/asset.meta" ]]; then
        mkdir -p "$(dirname "$target_path.meta")"
        cp -p "$source_dir/asset.meta" "$target_path.meta"
    fi

    imported=$((imported + 1))
done < <(find "$temp_dir" -name pathname -type f -print0)

echo "Imported $imported entries from $(basename "$package_path")"
