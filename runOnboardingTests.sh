#!/bin/bash

set -e

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
HAS_FILTER=0

for arg in "$@"; do
    if [ "$arg" = "--filter" ]; then
        HAS_FILTER=1
        break
    fi
done

if [ $HAS_FILTER -eq 1 ]; then
    exec "$SCRIPT_DIR/runSmokeTests.sh" "$@"
fi

exec "$SCRIPT_DIR/runSmokeTests.sh" --filter OnboardingPlayModeTests "$@"