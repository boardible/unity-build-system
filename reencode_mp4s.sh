#!/usr/bin/env bash

# Re-encode all MP4 assets under Assets/ using ffmpeg + libx265.
# Creates a timestamped backup under Backup/original_mp4s-* before overwriting.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
assets_dir="$repo_root/Assets"

if [[ ! -d "$assets_dir" ]]; then
  echo "Assets directory not found at $assets_dir; run from inside the repo." >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg not found in PATH. Install ffmpeg before running this script." >&2
  exit 1
fi

# Allow tweaking encoder quality/bitrate via environment variables.
crf="${CRF:-28}"
audio_bitrate="${AUDIO_BITRATE:-128k}"
preset="${PRESET:-slow}"

timestamp="$(date +%Y%m%d_%H%M%S)"
backup_root="$repo_root/Backup/original_mp4s-$timestamp"

echo "Backing up originals to: $backup_root"
mkdir -p "$backup_root"

# Find every .mp4 below Assets (handles spaces via -print0).
found_any=0
while IFS= read -r -d '' rel_entry; do
  rel_entry="${rel_entry#./}"
  src="$repo_root/$rel_entry"
  found_any=1

  rel_path="$rel_entry"
  backup_path="$backup_root/$rel_path"
  backup_dir="$(dirname "$backup_path")"
  mkdir -p "$backup_dir"
  cp "$src" "$backup_path"

  tmp_path="${src%.mp4}.tmp.mp4"

  echo "Re-encoding $rel_path"
  if ffmpeg -hide_banner -loglevel error -y \
    -i "$backup_path" \
    -c:v libx265 -preset "$preset" -crf "$crf" -tag:v hvc1 -pix_fmt yuv420p \
    -c:a aac -b:a "$audio_bitrate" \
    -movflags +faststart \
    "$tmp_path"; then
    mv "$tmp_path" "$src"
  else
    echo "Failed to encode $rel_path; restoring original." >&2
    rm -f "$tmp_path"
    cp "$backup_path" "$src"
  fi
done < <(cd "$repo_root" && find Assets -type f -name '*.mp4' -print0)

if [[ $found_any -eq 0 ]]; then
  echo "No MP4 files found under Assets/."
  exit 0
fi

echo "Re-encoding complete. Originals are stored in $backup_root"
