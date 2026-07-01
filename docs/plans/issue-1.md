# afp Issue #1 — Implementation Plan (Final)

> **Status**: Ready for implementation  
> **Target**: 9.5+/10 (adversarial-reviewed through 6 rounds)  
> **Date**: 2026-05-31  
> **Issue**: https://github.com/omar-elmountassir/acer-fan-profiles/issues/1

---

## Overview

Refactor afp for portability: generic systemd unit, global config with user override, clean install/uninstall, shared config library. Single PR covering all changes.

---

## Phase 0: Relocalisation (operational, separate from PR)

Move repo from `~/hub/envs/` (unstable) to `~/work/tools/` (stable).

### Pre-flight checks

```bash
if ! systemctl is-active --quiet acer-fan-profiles.service; then
    echo "ERROR: afp service is not running. Start it first."
    exit 1
fi
if [[ ! -d ~/hub/envs/acer-fan-profiles ]]; then
    echo "ERROR: Source repo not found at ~/hub/envs/acer-fan-profiles"
    exit 1
fi
```

### Execution

```bash
mkdir -p ~/work/tools/
mv ~/hub/envs/acer-fan-profiles ~/work/tools/
# Verify move succeeded before touching symlink
[[ ! -f ~/work/tools/acer-fan-profiles/acer-fan-profiles ]] && { echo "ERROR: Move failed — aborting"; mv ~/work/tools/acer-fan-profiles ~/hub/envs/ 2>/dev/null; exit 1; }
sudo ln -sf ~/work/tools/acer-fan-profiles/acer-fan-profiles /usr/local/bin/acer-fan-profiles
# Verify symlink target resolves
[[ ! -f /usr/local/bin/acer-fan-profiles ]] && { echo "ERROR: Symlink broken — aborting"; exit 1; }
sudo systemctl restart acer-fan-profiles.service
afp status  # verify
```

### Rollback

```bash
mv ~/work/tools/acer-fan-profiles ~/hub/envs/
sudo ln -sf ~/hub/envs/acer-fan-profiles/acer-fan-profiles /usr/local/bin/acer-fan-profiles
sudo systemctl restart acer-fan-profiles.service
```

---

## Phase 1: Shared config library + config chain refactor

### New file: `lib/config.sh`

Single source of truth for config resolution. Sourced by both daemon and CLI.

```bash
#!/bin/bash
# lib/config.sh — shared config resolution for afp daemon and CLI

_USER_CONFIG_DIR="${HOME}/.config/acer-fan-profiles"
_USER_CONFIG_FILE="${_USER_CONFIG_DIR}/config.yaml"
_GLOBAL_CONFIG_DIR="/etc/acer-fan-profiles"
_GLOBAL_CONFIG_FILE="${_GLOBAL_CONFIG_DIR}/config.yaml"

# Returns the resolved config file path, or empty string for compiled defaults.
# Priority: user (readable) > global (readable) > defaults
resolve_config_file() {
    if [[ -f "$_USER_CONFIG_FILE" && -r "$_USER_CONFIG_FILE" ]]; then
        echo "$_USER_CONFIG_FILE"
        return
    fi
    if [[ -f "$_GLOBAL_CONFIG_FILE" && -r "$_GLOBAL_CONFIG_FILE" ]]; then
        echo "$_GLOBAL_CONFIG_FILE"
        return
    fi
    echo ""
}

# Returns the directory containing the resolved config (for mkdir, state writes).
resolve_config_dir() {
    local resolved
    resolved=$(resolve_config_file)
    if [[ -n "$resolved" ]]; then
        dirname "$resolved"
    else
        echo "$_USER_CONFIG_DIR"  # default writable dir for new configs
    fi
}
```

### Daemon changes (`acer-fan-profiles`)

**Replace lines 26-27** (`readonly CONFIG_DIR=...` and `readonly CONFIG_FILE=...`) with:

```bash
SCRIPT_LIB="$(dirname "${BASH_SOURCE[0]}")/lib"
source "${SCRIPT_LIB}/config.sh"
CONFIG_DIR=$(resolve_config_dir)
CONFIG_FILE=$(resolve_config_file)
```

`CONFIG_DIR` and `CONFIG_FILE` are no longer `readonly` — they're resolved dynamically at startup and on each SIGHUP reload.

**Refactor `load_config()`**:

1. **DELETE** the early-return line: `[[ ! -f "$CONFIG_FILE" ]] && return 0`  
   (resolve_config_file() already handles the no-file case)

2. **Add at top of load_config()**:

   ```bash
   local resolved_config
   resolved_config=$(resolve_config_file)
   [[ -z "$resolved_config" ]] && return 0
   log info "Loading config from $resolved_config"
   ```

3. **Replace ALL `$CONFIG_FILE` references** inside `load_config()` with `$resolved_config`:
   - The `while IFS=': ' read` loop's input: `done < "$resolved_config"`
   - The `fan_curve_points` grep block: replace `$CONFIG_FILE` with `$resolved_config`
4. **After refactoring**: `grep -n 'CONFIG_FILE' acer-fan-profiles` must return ZERO matches inside `load_config()`. `CONFIG_FILE` is only used in `init()` for `mkdir -p "$CONFIG_DIR"` and in the CLI's config edit commands.

5. **SIGHUP reload**: `load_config()` is already called on SIGHUP. Since it now calls `resolve_config_file()` which re-evaluates paths, reload correctly picks up changes to either global or user config.

6. **Log on startup**: When using user config, log:
   ```bash
   log info "Using user config: $resolved_config (global available at ${_GLOBAL_CONFIG_FILE})"
   ```

**`CONFIG_DIR` consumers** (complete audit):

1. `init()`: `mkdir -p "$CONFIG_DIR"` — uses `resolve_config_dir()`. Correct.
2. State file is in `/run/acer-fan-profiles/` (RuntimeDirectory). Unaffected.
3. PID file is in `/run/acer-fan-profiles/`. Unaffected.

Only 1 consumer. Handled.

### CLI changes (`afp`)

**Replace line 10** (`readonly CONFIG_FILE=...`) with:

```bash
SCRIPT_LIB="$(dirname "${BASH_SOURCE[0]}")/lib"
source "${SCRIPT_LIB}/config.sh"
CONFIG_FILE=$(resolve_config_file)
```

**`cmd_config()`** — full rewrite:

```bash
cmd_config() {
    local subcmd="${1:-show}"
    case "$subcmd" in
        edit)
            local resolved=$(resolve_config_file)
            if [[ -z "$resolved" || "$resolved" != "$_USER_CONFIG_FILE" ]]; then
                # No user config — seed from global or warn
                mkdir -p "$(dirname "$_USER_CONFIG_FILE")"
                if [[ -f "$_GLOBAL_CONFIG_FILE" ]]; then
                    cp "$_GLOBAL_CONFIG_FILE" "$_USER_CONFIG_FILE"
                    echo "Created user config from global defaults: $_USER_CONFIG_FILE"
                else
                    echo "WARNING: Creating new user config. This overrides ALL defaults."
                    touch "$_USER_CONFIG_FILE"
                fi
            fi
            ${EDITOR:-nano} "$_USER_CONFIG_FILE"
            # Auto-reload daemon (no sudo needed — PID file is world-readable)
            if [[ -f /run/acer-fan-profiles/daemon.pid ]]; then
                kill -SIGHUP "$(cat /run/acer-fan-profiles/daemon.pid)" 2>/dev/null || true
                echo "Config reloaded."
            fi
            ;;
        show)
            local resolved=$(resolve_config_file)
            if [[ -z "$resolved" ]]; then
                echo -e "${YELLOW}No config file found (using compiled defaults)${RESET}"
            else
                local source_type="user"
                [[ "$resolved" == "$_GLOBAL_CONFIG_FILE" ]] && source_type="global"
                echo -e "${BOLD}Config source: $source_type ($resolved)${RESET}"
                cat "$resolved"
            fi
            ;;
        *)
            echo "Usage: afp config [edit|show]"
            ;;
    esac
}
```

### New test file: `tests/test_config_chain.sh`

```bash
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/config.sh"

pass=0; fail=0
assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  ✅ $desc"; ((pass++))
    else
        echo "  ❌ $desc: expected '$expected', got '$actual'"; ((fail++))
    fi
}

ORIG_HOME="$HOME"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "=== Config Chain Tests ==="

# Test 1: No config → defaults
echo "--- Test 1: No config → defaults ---"
HOME="$TMPDIR"
result=$(resolve_config_file)
assert_eq "No config returns empty" "" "$result"

# Test 2: Global only → returns global path
echo "--- Test 2: Global config only ---"
mkdir -p "$TMPDIR/etc"
echo "polling_interval: 3" > "$TMPDIR/etc/config.yaml"
export _GLOBAL_CONFIG_FILE="$TMPDIR/etc/config.yaml"
HOME="$TMPDIR"
result=$(resolve_config_file)
assert_eq "Global config returned" "$TMPDIR/etc/config.yaml" "$result"
unset _GLOBAL_CONFIG_FILE

# Test 3: User only → returns user path
echo "--- Test 3: User config only ---"
mkdir -p "$TMPDIR/.config/acer-fan-profiles"
echo "polling_interval: 5" > "$TMPDIR/.config/acer-fan-profiles/config.yaml"
HOME="$TMPDIR"
result=$(resolve_config_file)
assert_eq "User config returned" "$TMPDIR/.config/acer-fan-profiles/config.yaml" "$result"

# Test 4: Both exist → user wins
echo "--- Test 4: Both exist → user wins ---"
export _GLOBAL_CONFIG_FILE="$TMPDIR/etc/config.yaml"
HOME="$TMPDIR"
result=$(resolve_config_file)
assert_eq "User wins over global" "$TMPDIR/.config/acer-fan-profiles/config.yaml" "$result"
unset _GLOBAL_CONFIG_FILE

# Test 5: Unreadable user → global fallback
echo "--- Test 5: Unreadable user → global fallback ---"
export _GLOBAL_CONFIG_FILE="$TMPDIR/etc/config.yaml"
chmod 000 "$TMPDIR/.config/acer-fan-profiles/config.yaml"
HOME="$TMPDIR"
result=$(resolve_config_file)
assert_eq "Falls back to global" "$TMPDIR/etc/config.yaml" "$result"
chmod 644 "$TMPDIR/.config/acer-fan-profiles/config.yaml"
unset _GLOBAL_CONFIG_FILE

# Test 6: SIGHUP reload (daemon integration — skip if daemon not running)
if systemctl is-active --quiet acer-fan-profiles.service 2>/dev/null; then
    echo "--- Test 6: SIGHUP reload ---"
    echo "polling_interval: 99" >> "$TMPDIR/.config/acer-fan-profiles/config.yaml"
    kill -SIGHUP "$(cat /run/acer-fan-profiles/daemon.pid)" 2>/dev/null || true
    sleep 2
    # Verify daemon state reflects new interval
    new_interval=$(grep -o '"polling_interval":[[:space:]]*99' /run/acer-fan-profiles/state.json 2>/dev/null || echo "")
    assert_eq "SIGHUP reload active" "99" "$(echo "$new_interval" | grep -o '[0-9]*' | head -1)"
    sed -i '/polling_interval: 99/d' "$TMPDIR/.config/acer-fan-profiles/config.yaml"
    kill -SIGHUP "$(cat /run/acer-fan-profiles/daemon.pid)" 2>/dev/null || true
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]] || exit 1
```

---

## Phase 2: Systemd unit fix

### New file: `acer-fan-profiles.service.template`

```ini
[Unit]
Description=Acer Fan Profiles — Smart platform profile manager
Documentation=https://github.com/omar-elmountassir/acer-fan-profiles
After=multi-user.target linuwu_sense.service
Requires=linuwu_sense.service

[Service]
Type=simple
ExecStartPre=/bin/sh -c 'for i in $(seq 1 30); do [ -f /sys/firmware/acpi/platform_profile ] && exit 0; sleep 1; done; echo "platform_profile not available after 30s"; exit 1'
ExecStart=/usr/local/bin/acer-fan-profiles
Restart=on-failure
RestartSec=5
StartLimitBurst=5
StartLimitIntervalSec=60
Environment=HOME=/home/__INSTALL_USER__

RuntimeDirectory=acer-fan-profiles
RuntimeDirectoryMode=0755

ProtectSystem=strict
ReadWritePaths=-/sys/firmware/acpi/platform_profile
ReadWritePaths=-/run/acer-fan-profiles
ReadWritePaths=-/home/__INSTALL_USER__/.config/acer-fan-profiles
ReadWritePaths=-/sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/predator_sense
ProtectHome=read-only
NoNewPrivileges=false
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

**Design notes**:

- `__INSTALL_USER__` replaced by `sed` at install time. No `User=` directive (runs as root for sysfs access).
- `Environment=HOME=` ensures daemon resolves `$HOME` to the installing user.
- `ReadWritePaths` split into 4 separate lines (not one fragile long line).
- system76-power references removed (already masked on this machine).
- `Requires=linuwu_sense.service` handles module availability — ExecStartPre only checks `platform_profile`.

---

## Phase 3: install.sh + uninstall.sh refactor

### install.sh

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_USER="${SUDO_USER:-$(whoami)}"
INSTALL_HOME=$(eval echo "~${INSTALL_USER}")

echo "=== acer-fan-profiles installer ==="

# Root check
[[ $EUID -ne 0 ]] && { echo "Error: Run with sudo"; exit 1; }

# Prerequisites
[[ ! -f /sys/firmware/acpi/platform_profile ]] && { echo "Error: platform_profile not found. Ensure acer_wmi.predator_v4=1 is set."; exit 1; }

# 1. Symlink binaries (detect and remove old copy/symlink)
for bin in acer-fan-profiles afp; do
    target="/usr/local/bin/$bin"
    [[ -L "$target" || -f "$target" ]] && rm "$target"
    ln -sf "${SCRIPT_DIR}/$bin" "$target"
    chmod 755 "${SCRIPT_DIR}/$bin"  # ensure source executable
done

# 2. Install shared config library
mkdir -p /usr/local/lib/acer-fan-profiles
cp -r "${SCRIPT_DIR}/lib/"* /usr/local/lib/acer-fan-profiles/

# 3. Template and install systemd unit
if [[ -f /etc/systemd/system/acer-fan-profiles.service ]]; then
    cp /etc/systemd/system/acer-fan-profiles.service \
       /etc/systemd/system/acer-fan-profiles.service.backup
fi
sed -e "s/__INSTALL_USER__/${INSTALL_USER}/g" \
    "${SCRIPT_DIR}/acer-fan-profiles.service.template" \
    > /etc/systemd/system/acer-fan-profiles.service

# 4. Install global default config (don't overwrite existing)
mkdir -p /etc/acer-fan-profiles
if [[ ! -f /etc/acer-fan-profiles/config.yaml ]]; then
    cp "${SCRIPT_DIR}/config.yaml" /etc/acer-fan-profiles/config.yaml
    echo "   Global config → /etc/acer-fan-profiles/config.yaml"
fi

# 5. Create user config dir (preserve existing config)
sudo -u "$INSTALL_USER" mkdir -p "${INSTALL_HOME}/.config/acer-fan-profiles"

# 6. Ensure runtime directory exists (for afp status before first service start)
mkdir -p /run/acer-fan-profiles
chmod 755 /run/acer-fan-profiles

# 7. Enable and start
systemctl daemon-reload
systemctl enable acer-fan-profiles.service
systemctl restart acer-fan-profiles.service

echo ""
echo "=== Installation complete ==="
echo "  afp status      Show current state"
echo "  afp monitor     Live monitoring"
echo "  afp config      Show/edit config"
echo "  afp reload      Reload config"
systemctl status acer-fan-profiles.service --no-pager
```

### uninstall.sh

```bash
#!/bin/bash
set -euo pipefail

echo "=== acer-fan-profiles uninstaller ==="
[[ $EUID -ne 0 ]] && { echo "Error: Run with sudo"; exit 1; }

# 1. Stop and disable service
systemctl stop acer-fan-profiles.service 2>/dev/null || true
systemctl disable acer-fan-profiles.service 2>/dev/null || true

# 2. Remove service file and backup
rm -f /etc/systemd/system/acer-fan-profiles.service
rm -f /etc/systemd/system/acer-fan-profiles.service.backup
systemctl daemon-reload

# 3. Remove binaries and symlinks
rm -f /usr/local/bin/acer-fan-profiles
rm -f /usr/local/bin/afp

# 4. Remove shared library
rm -rf /usr/local/lib/acer-fan-profiles

# 5. Remove runtime directory
rm -rf /run/acer-fan-profiles

# 6. Global config — ask first (not rm -i which hangs in scripts)
echo "Remove global config at /etc/acer-fan-profiles/? [y/N]"
read -r response
[[ "$response" =~ ^[Yy]$ ]] && rm -rf /etc/acer-fan-profiles/

echo ""
echo "=== Uninstalled ==="
echo "Note: User config preserved at ~/.config/acer-fan-profiles/"
echo "Note: Kernel parameter acer_wmi.predator_v4=1 NOT removed."
echo "      Remove with: sudo kernelstub -d 'acer_wmi.predator_v4=1'"
```

### Makefile update

No changes needed to targets. `install-tested` calls `install.sh` which now handles symlinks. Works as-is.

**Note**: After Phase 0 (relocalisation), always run `make` from the new path. Old path no longer exists.

---

## Phase 4: Documentation

### README.md updates

- Installation instructions (install.sh, config chain)
- Config chain documentation (user > global > defaults, no merge)
- `cooperative_mode: false` recommendation when system76-power is disabled
- "Never create partial config manually" warning

### CLAUDE.md updates

- New repo path (`~/work/tools/`)
- Service template approach (`__INSTALL_USER__` sed)
- `lib/config.sh` as SSOT for config resolution
- Testing: `test_config_chain.sh` + existing tests

### CHANGELOG.md

- Entry for v2.2.0: portability release

---

## Execution Order

```
Phase 0 (relocalisation) — separate, operational, no PR
       ↓
Phase 1 (lib/config.sh + config chain + tests)  ─┐
       ↓                                           ├─ SINGLE PR
Phase 2 (service template)                       ─┤
       ↓                                           │
Phase 3 (install/uninstall refactor)              ─┤
       ↓                                           │
Phase 4 (docs)                                    ─┘
```

**Phases 1-4 are one PR.** Rationale: Phases 1+2+3 are coupled (deploying Phase 1 alone is unsafe — daemon runs as root with HOME=/root, config resolution would miss user config). Phase 4 describes the behavior from Phases 1-3.

---

## Acceptance Criteria Mapping

| AC                                 | Phase     | How addressed                                           |
| ---------------------------------- | --------- | ------------------------------------------------------- |
| Repo relocalisé                    | Phase 0   | Moved to ~/work/tools/                                  |
| systemd unit generic               | Phase 2   | Template with sed, no hardcoded user                    |
| Config depuis /etc/ + override     | Phase 1   | Simple override chain via lib/config.sh                 |
| install.sh + uninstall.sh testés   | Phase 3   | Symlink + template + upgrade detection                  |
| Deux users même machine            | Phase 1+2 | Global config shared, each user overrides independently |
| cooperative_mode: false documented | Phase 4   | In README                                               |
| README mis à jour                  | Phase 4   | Full update                                             |
| Makefile avec make install         | Phase 3   | install.sh handles symlink (Makefile unchanged)         |

---

## Out of Scope

- DKMS linuwu_sense (already handled)
- TCC Offset service (already separate)
- Multi-instance daemon (overkill for 2 users on same machine)
- GUI / web interface
- Distribution packaging (deb/rpm)
- Config merge (explicitly rejected — simple override)
