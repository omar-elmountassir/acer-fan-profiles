# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Smart fan control daemon for the Acer Predator Triton 17X (PTX17-71) running Linux. Bash-only — no build step, no dependencies beyond Linux coreutils. Two bash scripts: the daemon (`acer-fan-profiles`) and a CLI (`afp`).

## Dev Workflow

The repo copy at `./` is the git source. The installed binary is a **symlink** to the repo:

```
/usr/local/bin/acer-fan-profiles → ~/hub/envs/acer-fan-profiles/acer-fan-profiles
```

When modifying:

```bash
make test                  # lint + unit tests first
sudo systemctl restart acer-fan-profiles   # symlink means no cp needed
afp status                 # verify
# then commit when satisfied
```

No `sudo cp` needed — the symlink means editing the repo file IS editing the installed binary. Just restart the service. Use `make install-tested` to run tests + install in one step (for fresh installs or CI).

## Commands

```bash
make test       # shellcheck lint + both unit test suites
make lint       # shellcheck only (SC1090/SC1091 excluded for dynamic source)
make smoke      # interactive hardware verification (manual checklist)
make install    # sudo install.sh — copies binaries + service file
```

Run a single test file directly: `bash tests/test_compute_profile.sh`

## Architecture

Single-file daemon (`acer-fan-profiles`, ~1500 lines). Key sections in order:

1. **Config defaults + runtime state** (lines 35-100) — all globals, overridable by `~/.config/acer-fan-profiles/config.yaml`
2. **Config parser** (`load_config` + `validate_config`) — simple YAML key:value parser with range validation
3. **Fan curve** (`calculate_curve_fan_speed` + `apply_step_limit`) — piecewise linear interpolation between temp:speed points, step-limited to ±N%/cycle
4. **Sensor readers** (`get_cpu_load`, `get_gpu_util`, `get_cpu_temp`, `get_power_state`) — read `/proc/stat`, `nvidia-smi`, coretemp sysfs, power supply sysfs. All fail-safe: return hot/active on error
5. **Decision engine** (`evaluate_rules`) — priority chain: thermal critical > thermal escalate > thermal elevated > battery rules > AC load rules. Returns `profile|rule|reason`
6. **Profile application** (`set_profile`) — maps curve speed to ACPI tier (quiet/balanced/performance). Only writes ACPI + sleep 0.5 when tier **changes** (cached in `LAST_ACPI_PROFILE`). Then writes Linuwu-Sense fan speed directly. Order matters: ACPI write resets Linuwu fans to 0,0
7. **Main loop** — polls sensors every N seconds, runs `evaluate_rules`, applies profile if changed, writes state JSON to `/run/acer-fan-profiles/state.json`
8. **Signal handlers** — flag-based (not direct function calls) to avoid re-entrancy. SIGHUP = reload config, SIGTERM/SIGINT = shutdown

CLI (`afp`) reads the daemon's state JSON and sysfs nodes — no daemon communication beyond the override file and PID signal.

## Key Constraints

- **Write order is critical**: ACPI `platform_profile` must be written before Linuwu-Sense `fan_speed`, with a 0.5s gap. Writing ACPI resets Linuwu fans to 0,0
- **ACPI tier caching**: `LAST_ACPI_PROFILE` tracks the last written tier. Only re-write ACPI when tier changes (quiet↔balanced↔performance). This avoids unnecessary 0.5s sleeps on every cycle.
- **Curve deadzone**: `fan_curve_min_delta` (default 3%) — if both current and target are curve profiles and the delta is below this threshold, the write is skipped entirely. State JSON still updates.
- **Step limiter**: `fan_curve_step_limit` (default 5%) — limits fan speed change per cycle to prevent abrupt jumps. This is a SAFETY feature, not a bug. Do not lower.
- **i9-13900HX idle temp is 70-76°C** — this is normal for this CPU, not a bug
- **`cooperative_mode: false`** — system76-power is masked; AFP owns profile decisions entirely
- **Thermal hysteresis**: 7°C bands on all three tiers (elevated/escalate/critical). Trigger and release temps are separate to prevent flapping
- **Linuwu-Sense is optional**: turbo profile requires it; without it, the daemon falls back to `performance` (75%) for thermal emergencies
- **Runtime state**: `CURRENT_FAN_SPEED` and `LAST_ACPI_PROFILE` are runtime-only, not persisted. They reset on daemon restart.

## Testing

Tests source the daemon with `AFP_NO_MAIN=1` to skip init and main loop, then call internal functions directly:

- `tests/test_compute_profile.sh` — exercises `evaluate_rules()` with controlled cpu_load/gpu_util/temp/power inputs, verifies profile and rule selection
- `tests/test_fan_curve.sh` — exercises `calculate_curve_fan_speed()` interpolation at boundaries and midpoints
- `tests/shellcheck.sh` — static analysis at error severity

## State Files (runtime, in `/run/acer-fan-profiles/`)

| File                 | Purpose                                                                 |
| -------------------- | ----------------------------------------------------------------------- |
| `state.json`         | Current daemon state (profile, temps, fans, rule, mode) — read by `afp` |
| `override`           | Manual profile lock set by `afp set`, cleared by `afp auto`             |
| `daemon.pid`         | PID file for signal dispatch                                            |
| `thermal.state`      | Hysteresis flags (elevated/escalate/critical booleans)                  |
| `temp_history.state` | Last 3 raw temp readings for smoothing                                  |

## Project Management

Issues and bug tracking on GitHub: `gh issue list`

Do NOT hardcode issue numbers or bug status in this file — it goes stale. Check GitHub for current state.

## Machine Reference

MUST READ THIS FILE BEFORE WORKING ON THE PROJECT to understand the machine we are working on.
Full machine docs at `~/work/el-mountassir/machines/acer-predator-triton-17x.md`

## Config

User config at `~/.config/acer-fan-profiles/config.yaml`. Repo ships `config.yaml` as defaults. `afp reload` sends SIGHUP for live reload without restart. All values validated on load — invalid config is rejected with previous values kept.
