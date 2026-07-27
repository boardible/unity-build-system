#!/usr/bin/env bash
#
# Decodes a binary profiler capture written by the smoke performance phase
# (SMOKE_GC_ATTRIBUTION=true) into a managed-allocation attribution report.
#
# Usage:
#   Scripts/analyzeGcAttribution.sh <capture.raw> [report.txt]
#
# Capture first, then decode:
#   SMOKE_GC_ATTRIBUTION=true Scripts/runSmokeTests.sh --phase performance --games SecretHitler
#   Scripts/analyzeGcAttribution.sh Logs/gc-attribution/SecretHitler.raw

set -euo pipefail

PROJECT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNITY_PATH="${UNITY_PATH:-/Applications/Unity/Hub/Editor/6000.5.3f1/Unity.app/Contents/MacOS/Unity}"

if [ $# -lt 1 ]; then
    echo "usage: $0 <capture.raw> [report.txt]" >&2
    exit 2
fi

CAPTURE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
REPORT="${2:-${CAPTURE%.raw}.report.txt}"
LOG="${CAPTURE%.raw}.analyze.log"

if [ ! -f "$CAPTURE" ]; then
    echo "capture not found: $CAPTURE" >&2
    exit 1
fi

echo "Analyzing $CAPTURE"

set +e
"$UNITY_PATH" \
    -batchmode -nographics \
    -projectPath "$PROJECT_PATH" \
    -executeMethod SmokeGcAttributionAnalyzer.Run \
    -gcCapture "$CAPTURE" \
    -gcReport "$REPORT" \
    -logFile "$LOG"
status=$?
set -e

if [ $status -ne 0 ]; then
    echo "Analysis failed (exit $status). Unity log: $LOG" >&2
    grep -E '\[GcAttribution\]|error CS' "$LOG" | tail -20 >&2 || true
    exit $status
fi

echo "Report: $REPORT"
cat "$REPORT"
