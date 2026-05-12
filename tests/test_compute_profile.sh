#!/bin/bash
# Unit tests for evaluate_rules() — the core decision function of the daemon.
#
# Strategy: source the daemon with AFP_NO_MAIN=1 (skips init + main_loop), then
# directly call evaluate_rules() with controlled (cpu_load, gpu_util, cpu_temp,
# power) arguments. The function returns a "profile|rule|reason" string we parse.
#
# State variables (thermal_*, current_profile, COOPERATIVE_MODE, LINUWU_AVAILABLE)
# are global in the daemon — we override them per-test before each call.

# shellcheck disable=SC2034 # vars assigned here are read by the sourced daemon
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source daemon — guard prevents main_loop from starting
# shellcheck disable=SC1091
AFP_NO_MAIN=1 source "$REPO_ROOT/acer-fan-profiles"

PASS=0
FAIL=0

assert_rule() {
    local name="$1"
    local expected_rule="$2"
    local actual_result="$3"
    local actual_rule
    actual_rule=$(echo "$actual_result" | cut -d'|' -f2)
    if [[ "$actual_rule" == "$expected_rule" ]]; then
        echo "PASS: $name (rule=$actual_rule)"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name: expected rule=$expected_rule got rule=$actual_rule (full: $actual_result)"
        FAIL=$((FAIL + 1))
    fi
}

assert_profile() {
    local name="$1"
    local expected_profile="$2"
    local actual_result="$3"
    local actual_profile
    actual_profile=$(echo "$actual_result" | cut -d'|' -f1)
    if [[ "$actual_profile" == "$expected_profile" ]]; then
        echo "PASS: $name (profile=$actual_profile)"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name: expected profile=$expected_profile got profile=$actual_profile"
        FAIL=$((FAIL + 1))
    fi
}

# ─── Reset state helpers ─────────────────────────────────────────────────────

# shellcheck disable=SC2034 # All vars below are consumed by the sourced daemon
reset_state() {
    thermal_elevated=false
    thermal_escalate=false
    thermal_critical=false
    current_profile="balanced"
    LINUWU_AVAILABLE=true
    # Apply config defaults explicitly so tests don't depend on user config.yaml
    TEMP_ELEVATED_TRIGGER=78
    TEMP_ELEVATED_RELEASE=71
    TEMP_ESCALATE_TRIGGER=88
    TEMP_ESCALATE_RELEASE=81
    TEMP_CRITICAL_TRIGGER=93
    TEMP_CRITICAL_RELEASE=86
    CPU_LOAD_LOW=12
    CPU_LOAD_MEDIUM=25
    CPU_LOAD_HIGH=50
    GPU_UTIL_ACTIVE=50
    FAN_CURVE_ENABLED=false
    COOPERATIVE_MODE=false
}

# Stub write_thermal_state — evaluate_rules calls it for persistence, ignore in tests
write_thermal_state() { :; }

# Stub log() to keep test output clean (suppress info/debug)
log() { :; }

# ─── Test cases ──────────────────────────────────────────────────────────────

# T1: Idle AC, no curve → balanced or ac_idle rule
reset_state
result=$(evaluate_rules 5 10 55 ac)
assert_rule "T1 idle AC no curve" "ac_idle" "$result"

# T2: Battery idle → low-power
reset_state
result=$(evaluate_rules 5 10 55 battery)
assert_rule "T2 battery idle" "battery_idle" "$result"
assert_profile "T2 battery idle profile" "low-power" "$result"

# T3: Battery + load → quiet
reset_state
result=$(evaluate_rules 30 60 70 battery)
assert_rule "T3 battery active" "battery_active" "$result"
assert_profile "T3 battery active profile" "quiet" "$result"

# T4: AC + high CPU load → ac_heavy rule (75°C is in elevated band but we test load path)
# Use temp=65 to avoid triggering thermal_elevated
reset_state
result=$(evaluate_rules 60 20 65 ac)
assert_rule "T4 ac high load" "ac_heavy" "$result"

# T5: thermal_critical → turbo (if Linuwu) or performance
reset_state
result=$(evaluate_rules 5 10 95 ac)
assert_rule "T5 thermal_critical triggers" "thermal_critical" "$result"
assert_profile "T5 thermal_critical profile" "turbo" "$result"

# T6: thermal_critical without Linuwu → performance fallback
reset_state
LINUWU_AVAILABLE=false
result=$(evaluate_rules 5 10 95 ac)
assert_profile "T6 thermal_critical no Linuwu" "performance" "$result"

# T7: thermal_elevated legacy mode (cooperative_mode=false) → performance
reset_state
COOPERATIVE_MODE=false
result=$(evaluate_rules 5 10 80 ac)
assert_rule "T7 elevated legacy rule" "thermal_elevated" "$result"
assert_profile "T7 elevated legacy profile" "performance" "$result"

# T8: thermal_elevated cooperative mode → preserve current_profile + new rule
reset_state
COOPERATIVE_MODE=true
current_profile="balanced"
result=$(evaluate_rules 5 10 80 ac)
assert_rule "T8 elevated coop rule" "thermal_elevated_coop" "$result"
assert_profile "T8 elevated coop profile preserves current" "balanced" "$result"

# T9: thermal_elevated coop with current_profile=curve:N → preserves curve target
reset_state
COOPERATIVE_MODE=true
current_profile="curve:30"
result=$(evaluate_rules 5 10 80 ac)
assert_rule "T9 elevated coop preserves curve profile" "thermal_elevated_coop" "$result"
assert_profile "T9 elevated coop profile=curve:30" "curve:30" "$result"

# T10: Hysteresis — elevated active at 75°C, should stay active (75 < release 71? no — > release)
reset_state
thermal_elevated=true
result=$(evaluate_rules 5 10 75 ac)
assert_rule "T10 elevated stays active above release" "thermal_elevated" "$result"

# T11: Hysteresis — elevated active drops below release (70°C < 71) → deactivates
reset_state
thermal_elevated=true
result=$(evaluate_rules 5 10 70 ac)
# After deactivation, falls through to other rules → expect ac_idle
assert_rule "T11 elevated deactivates below release" "ac_idle" "$result"

# T12: Hysteresis — escalate triggers at 88°C, doesn't trigger at 87°C
reset_state
result=$(evaluate_rules 5 10 87 ac)
# 87 >= 78 elevated trigger but < 88 escalate, expect elevated
assert_rule "T12 below escalate trigger stays elevated" "thermal_elevated" "$result"

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "─────────────────────────"
echo "PASS: $PASS  FAIL: $FAIL"
if [[ $FAIL -eq 0 ]]; then
    echo "test_compute_profile: OK"
    exit 0
else
    echo "test_compute_profile: FAILED"
    exit 1
fi
