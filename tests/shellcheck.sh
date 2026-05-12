#!/bin/bash
# Static analysis with shellcheck.
# Exits 0 if no critical issues, 1 otherwise.
# SC1090 disabled (cannot follow non-constant source on sourced daemon in tests).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v shellcheck >/dev/null 2>&1; then
    echo "shellcheck not installed — install with: sudo apt install shellcheck"
    exit 2
fi

TARGETS=(
    "acer-fan-profiles"
    "afp"
    "install.sh"
    "uninstall.sh"
    "tests/test_compute_profile.sh"
    "tests/test_fan_curve.sh"
    "tests/smoke-test.sh"
)

EXIT=0
for f in "${TARGETS[@]}"; do
    if [[ -f "$f" ]]; then
        echo "=== shellcheck $f ==="
        # -S error: only fail on errors (not warnings/info/style).
        # -e SC1090,SC1091: cannot follow dynamic source paths in tests.
        if ! shellcheck -e SC1090,SC1091 -S error "$f"; then
            EXIT=1
        fi
    fi
done

if [[ $EXIT -eq 0 ]]; then
    echo ""
    echo "shellcheck: PASS"
else
    echo ""
    echo "shellcheck: FAIL"
fi

exit $EXIT
