#!/bin/bash
# Manual smoke test against the live hardware.
# Run this once after `sudo install` of a new version to confirm everything works.
#
# Each check prints the relevant data and asks for visual confirmation.
# Not automated — manual checklist that reuses the live state.

set -u

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

step() { echo -e "\n${YELLOW}── $* ──${RESET}"; }
ok()   { echo -e "${GREEN}✓ $*${RESET}"; }
ko()   { echo -e "${RED}✗ $*${RESET}"; }
ask()  { read -r -p "$* (y/N) "; [[ "$REPLY" == "y" || "$REPLY" == "Y" ]]; }

PASS=0
FAIL=0
record() { if "$@"; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); fi; }

# ─── Step 0: precondition checks ─────────────────────────────────────────────
step "Step 0 — preconditions"
if systemctl is-active acer-fan-profiles >/dev/null 2>&1; then
    ok "daemon active"
else
    ko "daemon not active — run: sudo systemctl start acer-fan-profiles"
    exit 2
fi

if [[ -e /sys/firmware/acpi/platform_profile ]]; then
    ok "platform_profile sysfs present"
else
    ko "platform_profile sysfs missing — acer_wmi loaded?"
    exit 2
fi

# ─── Step 1: cooperative_mode is parsed and active ──────────────────────────
step "Step 1 — cooperative_mode parsing"
LOAD_LINE=$(journalctl -u acer-fan-profiles --since "1 hour ago" --no-pager 2>/dev/null | grep "Config loaded:" | tail -1)
echo "$LOAD_LINE"
if echo "$LOAD_LINE" | grep -q "cooperative=true"; then
    record ok "cooperative_mode parsed as true"
elif echo "$LOAD_LINE" | grep -q "cooperative=false"; then
    record ok "cooperative_mode parsed as false (set in user config?)"
else
    record ko "cooperative_mode NOT in load_config log — patch 1A not applied"
fi

# ─── Step 2: afp status shows expected fields ───────────────────────────────
step "Step 2 — afp status output"
afp status
echo ""
ask "Status shows Profile/Mode/Rule/Linuwu/Power/CPU Load/GPU Util/CPU Temp/Fan RPM/Uptime ?" \
    && record ok "status output structure OK" \
    || record ko "status output incomplete"

# ─── Step 3: curve mode visible when active ─────────────────────────────────
step "Step 3 — curve mode visibility"
echo "If the daemon is in curve mode (rule = ac_idle, fan_curve_enabled=true), you"
echo "should see lines like 'Profile: <name> (curve active)' in afp status."
afp status | grep -E "curve active|Curve:|Recent:" || echo "(no curve lines — daemon may not be in curve mode right now)"
ask "Does the output reflect curve state correctly (active line if curve, absent if not) ?" \
    && record ok "curve visibility OK" \
    || record ko "curve visibility broken"

# ─── Step 4: temp baseline at idle ──────────────────────────────────────────
step "Step 4 — temperature at idle"
PKG=$(sensors 2>/dev/null | grep "Package id 0" | grep -oP '\+\d+\.\d+°C' | head -1)
echo "CPU Package: $PKG"
ask "Temp is below 85°C at idle ?" \
    && record ok "thermal baseline OK" \
    || record ko "temp too high at idle — investigate"

# ─── Step 5: fans at reasonable RPM in idle ─────────────────────────────────
step "Step 5 — fan RPM at idle"
sensors 2>/dev/null | grep -E "fan[12]:"
ask "Fans below 4000 RPM at idle ?" \
    && record ok "fan baseline OK" \
    || record ko "fans too high at idle"

# ─── Step 6: no profile-loop in logs ────────────────────────────────────────
step "Step 6 — no profile flapping in logs"
FLAPS=$(journalctl -u acer-fan-profiles --since "5 minutes ago" --no-pager 2>/dev/null \
    | grep -c "External profile change detected")
echo "External profile change events last 5 min: $FLAPS"
if [[ $FLAPS -lt 3 ]]; then
    record ok "no excessive flapping (< 3 in 5 min)"
else
    record ko "profile flapping detected (>= 3 in 5 min)"
fi

# ─── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "──────────────────────"
echo "PASS: $PASS  FAIL: $FAIL"
if [[ $FAIL -eq 0 ]]; then
    ok "smoke-test: OK"
    exit 0
else
    ko "smoke-test: $FAIL failures"
    exit 1
fi
