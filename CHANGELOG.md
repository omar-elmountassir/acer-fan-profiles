# Changelog

## [2.0.0] - 2026-04-10

### Added
- Continuous temperature-based fan curve for AC+load scenarios
- Piecewise linear interpolation between configurable temp:speed points
- Fan speed step limiter for smooth, inaudible transitions
- Curve floor setting (minimum fan speed when curve is active)
- CLI shows curve mode with percentage and ramp direction
- Sensor watchdog alerts after consecutive failures
- Battery path auto-detection (no more hardcoded BAT1)
- loginctl-based notification user detection with fallback

### Fixed
- CPU temp returns 100 on sensor failure (fail-safe hot) instead of 0
- GPU util returns active threshold on nvidia-smi failure instead of silent 0
- Signal handlers now flag-based (no re-entrancy risk)

### Changed
- Default log_level changed from debug to info
- Version bumped from 1.0.0 to 2.0.0

## [1.0.0] - 2026-01-31

### Added
- Initial release
- 6 fan profiles with automatic load-based switching
- Thermal hysteresis bands (7°C) for stable transitions
- Linuwu-Sense + ACPI dual-layer fan control
- CLI tool (afp) for status, monitoring, and manual overrides
- Systemd service with safety hardening
- Config validation
- Atomic state file writes
