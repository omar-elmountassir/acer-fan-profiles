# Acer Fan Profiles (AFP)

Smart, load-aware fan control daemon for the Acer Predator Triton 17X (PTX17-71) running Linux.

## Why

Stock `acer_wmi` exposes `platform_profile` but changing it has zero effect on fan RPMs on the PTX17-71. This daemon uses [Linuwu-Sense](https://github.com/JafarAkhondali/linuwu-sense) for real fan control with automatic profile switching based on CPU load, GPU utilization, temperature, and power state.

## Features

- **Continuous fan curve** (v2.0) — smooth temperature-based fan speed instead of discrete jumps
- **6 discrete profiles** — low-power (0%), quiet (20%), balanced (50%), balanced-performance (60%), performance (75%), turbo (100%)
- **Automatic switching** — load-based rules with thermal priority override
- **Thermal safety** — 3-tier emergency system (elevated/escalate/critical) with hysteresis bands
- **Dual-layer control** — ACPI platform_profile + Linuwu-Sense fan_speed in correct write order
- **CLI tool** (`afp`) — status, monitoring, manual overrides, config management
- **Systemd service** — hardened with safety nets and auto-restart

## Requirements

- Acer Predator Triton 17X (PTX17-71) or similar with `acer_wmi` driver
- [Linuwu-Sense](https://github.com/JafarAkhondali/linuwu-sense) kernel module (DKMS recommended)
- Linux with systemd
- `nvidia-smi` (optional, for GPU utilization monitoring)

## Installation

```bash
git clone https://github.com/omar-elmountassir/acer-fan-profiles.git
cd acer-fan-profiles
sudo ./install.sh
```

## Usage

```bash
afp                   # Show current status
afp status            # Same as above
afp status --json     # Raw JSON state
afp monitor           # Live monitoring TUI
afp profiles          # List all profiles
afp set <profile>     # Lock to a specific profile
afp auto              # Return to automatic mode
afp config            # Show config file
afp config edit       # Edit config in $EDITOR
afp reload            # Reload config (no restart needed)
```

## Configuration

Config file: `~/.config/acer-fan-profiles/config.yaml`

### Fan Curve (v2.0)

When enabled, replaces discrete profiles with a smooth continuous curve for AC+load scenarios:

```yaml
fan_curve_enabled: true
fan_curve_points: "55:15 65:25 72:40 78:60 85:80 92:100"
fan_curve_floor: 10        # minimum fan speed (%)
fan_curve_step_limit: 5    # max change per 3s cycle (%)
```

The curve uses piecewise linear interpolation between the defined temperature:speed points. The step limiter ensures smooth, inaudible transitions.

Battery and idle rules still use fixed profiles. Thermal emergency rules always override the curve.

### Thermal Thresholds

Three tiers with hysteresis bands to prevent oscillation:

| Tier | Trigger | Release | Band | Action |
|------|---------|---------|------|--------|
| Elevated | 78°C | 71°C | 7°C | performance (75%) |
| Escalate | 88°C | 81°C | 7°C | turbo (100%) |
| Critical | 96°C | 89°C | 7°C | emergency turbo (100%) |

### Load Thresholds

```yaml
cpu_load_low: 12       # Below → quiet
cpu_load_medium: 25    # Below → balanced
cpu_load_high: 50      # Above → performance/turbo
gpu_util_active: 50    # GPU considered active above this
```

## Architecture

Three-layer fan control stack:

1. **Hardware** — Embedded Controller (EC) via ACPI `platform_profile`
2. **Kernel** — Linuwu-Sense module provides `fan_speed` sysfs node
3. **Userspace** — AFP daemon reads sensors, applies rules, writes both layers

Critical write order: ACPI `platform_profile` first → 0.5s delay → Linuwu `fan_speed`. Writing ACPI resets Linuwu to 0,0.

## Safety

- Thermal emergency rules always override everything
- Fail-safe sensor readings (returns hot/active on failure)
- Sensor watchdog alerts after consecutive failures
- Signal handlers are re-entrant safe
- EC has final authority during thermal protection
- `afp set performance` provides instant safe fallback

## Troubleshooting

### Fans not spinning
```bash
afp status                           # Check daemon state
systemctl status acer-fan-profiles   # Check service
lsmod | grep linuwu                  # Check module loaded
afp set performance                  # Force 75% fans
```

### Temperature too high
```bash
afp set turbo                        # Force 100% fans immediately
```

### Reset to defaults
```bash
afp auto                             # Remove manual override
sudo systemctl restart acer-fan-profiles
```

## License

MIT
