#!/bin/bash
# Unit tests for calculate_curve_fan_speed() — piecewise linear interpolation.
#
# Default curve: "55:15 65:25 72:40 78:60 85:80 92:100"
# Below 55°C → fan_curve_floor (10%)
# Above 92°C → 100%

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
AFP_NO_MAIN=1 source "$REPO_ROOT/acer-fan-profiles"

PASS=0
FAIL=0

assert_eq() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "PASS: $name (=$actual)"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name: expected $expected got $actual"
        FAIL=$((FAIL + 1))
    fi
}

# Set up default curve for tests (consumed by sourced daemon)
# shellcheck disable=SC2034
FAN_CURVE_POINTS="55:15 65:25 72:40 78:60 85:80 92:100"
# shellcheck disable=SC2034
FAN_CURVE_FLOOR=10

# Stub log
log() { :; }

# ─── Test cases ──────────────────────────────────────────────────────────────

# Below lowest point → floor
result=$(calculate_curve_fan_speed 40)
assert_eq "T1 below floor (40°C) → floor 10%" "10" "$result"

result=$(calculate_curve_fan_speed 54)
assert_eq "T2 just below first point (54°C) → floor" "10" "$result"

# At exact first point: current daemon uses `temp -le ${temps[0]}` → returns floor at boundary.
# This is the current behavior — at 55°C exactly, we get floor (10%), not 15%.
# TODO: consider tightening to `-lt` so the first point itself maps to its declared speed.
result=$(calculate_curve_fan_speed 55)
assert_eq "T3 at first point (55°C) → floor (current behavior, see TODO)" "10" "$result"

result=$(calculate_curve_fan_speed 56)
assert_eq "T3b just above first point (56°C) → interpolated ~16%" "16" "$result"

result=$(calculate_curve_fan_speed 65)
assert_eq "T4 at 65°C → 25%" "25" "$result"

result=$(calculate_curve_fan_speed 72)
assert_eq "T5 at 72°C → 40%" "40" "$result"

result=$(calculate_curve_fan_speed 78)
assert_eq "T6 at 78°C → 60%" "60" "$result"

result=$(calculate_curve_fan_speed 85)
assert_eq "T7 at 85°C → 80%" "80" "$result"

result=$(calculate_curve_fan_speed 92)
assert_eq "T8 at 92°C → 100%" "100" "$result"

# Above max point → 100%
result=$(calculate_curve_fan_speed 95)
assert_eq "T9 above max (95°C) → 100%" "100" "$result"

# Interpolation between points: 55→15, 65→25, so at 60 expect 20
result=$(calculate_curve_fan_speed 60)
assert_eq "T10 interpolation midway 55-65 (60°C) → 20%" "20" "$result"

# 78→60, 85→80, at 81.5 (rounded to 81) expect ~~(60 + (3/7)*20) ~~ 68
# Linear: 78→60, +1°C = +20/7 ≈ +2.857%. At 81 (3°C over): +8.57 → 68
result=$(calculate_curve_fan_speed 81)
# Allow 67 or 68 due to integer arithmetic in bash
if [[ "$result" == "67" || "$result" == "68" ]]; then
    echo "PASS: T11 interpolation 78-85 (81°C) → 67-68% (got $result)"
    PASS=$((PASS + 1))
else
    echo "FAIL: T11: expected 67-68 got $result"
    FAIL=$((FAIL + 1))
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "─────────────────────────"
echo "PASS: $PASS  FAIL: $FAIL"
if [[ $FAIL -eq 0 ]]; then
    echo "test_fan_curve: OK"
    exit 0
else
    echo "test_fan_curve: FAILED"
    exit 1
fi
