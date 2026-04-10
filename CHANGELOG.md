# Changelog

All notable changes to the acer-fan-profiles daemon.

## [1.1.0] - 2026-01-31

### Critical Finding: EC Thermal Override

**EC overrides ALL Linuwu writes during thermal protection.** Testing confirmed that writes of `50,50`, `0,0`, and `25,25` were all ignored while EC maintained `100,100` during high CPU temperature. This is expected hardware safety behavior - EC has final authority over fan control regardless of software requests.

See `EC-OVERRIDE-BEHAVIOR.md` for full documentation.

### Important Discovery

**system76-power conflict identified**: Pop!_OS's `com.system76.PowerDaemon.service` conflicts with AFP on non-System76 hardware. Must be disabled for AFP to have sole control of fan profiles:

```bash
sudo systemctl disable --now com.system76.PowerDaemon.service
```

See `~/nexus/quirks/system76-power-conflict.md` for details.

### Security & Stability (Post-Audit Hardening)

**Status**: Audit complete, all findings addressed in post-audit hardening (see version 1.1.0 below)

Fixed all 9 HIGH-risk issues identified in security audit (EM-190):

1. **Pipeline error handling** (Lines 212, 513-514, 817)
   - Replaced `2>/dev/null` suppression with explicit error checks
   - All pipelines now fail loudly with logged errors

2. **grep/head pipeline failures** (Lines 511, 703, 707, 717)
   - Added explicit exit code checks after each pipeline stage
   - systemd context now properly propagates pipeline errors

3. **read_fan_value() error masking** (Lines 520-569)
   - Function now returns distinct error codes instead of "0" for all failures
   - Callers can differentiate between "fan stopped" and "read failed"

4. **date command race condition** (Lines 70, 342, 489, 583, 725)
   - Added `TZ=UTC` prefix to all `date +%s` invocations
   - Prevents timezone-related race conditions in systemd context

5. **HOME variable unset in systemd** (Lines 16-19, 23-24, 246)
   - Added `${HOME:-/root}` fallback throughout
   - Config paths now resolve correctly under systemd

6. **Config value validation** (Lines 97-108)
   - Added numeric validation for all threshold values
   - Daemon fails fast with clear error on invalid config

7. **Subshell exit code handling** (Lines 695, 703-709)
   - Replaced subshell patterns with explicit variable capture
   - Exit codes now properly checked and logged

8. **Hardware loss recovery** (Lines 163-180)
   - Added hwmon existence check at startup
   - Graceful degradation and retry on hardware disappearance

9. **Infinite retry loop** (Lines 788-831)
   - Implemented exponential backoff (1s, 2s, 4s, 8s, max 30s)
   - Maximum retry count before daemon gives up

### Backup Location

Pre-hardening code is preserved in git history (commit tags available)

## [1.0.0] - 2026-01-30

### Added

- Initial daemon implementation
- Cooperative Mode with system76-power integration
- Linuwu-Sense detection for turbo profile
- 5 profile support: low-power, quiet, balanced, balanced-performance, performance
- Turbo profile via Linuwu-Sense direct fan control
- GPU utilization threshold (30%) to prevent compositor cycling
- CLI tool (`afp`) for manual control
- Systemd service with auto-restart
- YAML configuration support
- State file persistence for profile tracking
