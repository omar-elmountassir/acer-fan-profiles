# acer-fan-profiles

Smart fan profile daemon for **Acer Predator PTX17-71** on Pop!\_OS 24.04 LTS.

Works alongside `system76-power` to provide intelligent, load-aware, automatic switching across all 5 Acer ACPI platform profiles.

## Problem

Pop!\_OS ships with `system76-power` which only maps to 3 of 5 available Acer platform profiles:

| system76-power | platform_profile | Fan behavior |
| -------------- | ---------------- | ------------ |
| Battery        | low-power        | Minimal      |
| Balanced       | balanced         | Moderate     |
| Performance    | performance      | Full blast   |

The `quiet` and `balanced-performance` profiles are never used, and switching is manual only — no response to CPU load, GPU activity, or temperature.

## Solution

`acer-fan-profiles` monitors system state and automatically selects the optimal profile:

| Condition                                     | Profile                | Fan behavior   |
| --------------------------------------------- | ---------------------- | -------------- |
| Battery + idle                                | `low-power`            | Silent         |
| Battery + light load, or AC + idle            | `quiet`                | Low noise      |
| AC + light-moderate load                      | `balanced`             | Moderate       |
| AC + sustained medium load or GPU active      | `balanced-performance` | Active cooling |
| AC + heavy load, gaming, or thermal emergency | `performance`          | Full blast     |

### Features

- **Load-aware**: Monitors CPU load (`/proc/stat`) and GPU utilization (`nvidia-smi`)
- **Temperature-aware**: Escalates to `performance` when CPU exceeds 92°C, emergency at 97°C
- **Power-aware**: Detects AC/battery state instantly
- **Hysteresis**: Prevents rapid profile flapping (5s upgrade delay, 15s downgrade delay)
- **Manual override**: Lock to any profile with `afp set <profile>`
- **Desktop notifications**: Optional `notify-send` on profile changes
- **Configurable**: All thresholds tunable via `~/.config/acer-fan-profiles/config.yaml`
- **Safe**: Fails to `performance` if sensors are unreadable. No EC access.

## Prerequisites

- Acer Predator PTX17-71 (or compatible Predator with platform_profile support)
- Pop!\_OS 24.04 LTS (or any Linux with kernel 6.8+)
- Kernel parameter: `acer_wmi.predator_v4=1`

```bash
# Add kernel parameter (one-time, persists across reboots)
sudo kernelstub -a "acer_wmi.predator_v4=1"
sudo reboot
```

## Install

```bash
cd ~/nexus/hardware/acer-fan-profiles
sudo ./install.sh
```

This installs:

- `/usr/local/bin/acer-fan-profiles` — daemon
- `/usr/local/bin/afp` — CLI
- `/etc/systemd/system/acer-fan-profiles.service` — systemd unit
- `~/.config/acer-fan-profiles/config.yaml` — user config (not overwritten on reinstall)

## Uninstall

```bash
cd ~/nexus/hardware/acer-fan-profiles
sudo ./uninstall.sh
```

Config is preserved at `~/.config/acer-fan-profiles/`. Kernel parameter is not removed.

## CLI Usage

### `afp status`

Shows current state:

```
  Profile:    balanced-performance
  Mode:       auto
  Rule:       ac_medium (AC + medium load (CPU 42%))

  Power:      ac (battery 88%)
  CPU Load:   42%  ████████░░░░░░░░░░░░
  GPU Util:   8%   ██░░░░░░░░░░░░░░░░░░
  CPU Temp:   78°C ████████████████░░░░
  Fan RPM:    3200 / 3400 (via Linuwu)

  Uptime:     2h 34m
  Last:       balanced → balanced-performance 4m ago
```

### `afp status --json`

JSON output for scripting.

### `afp monitor`

Live terminal dashboard (refreshes every 3s):

```
┌─ Acer Fan Profiles ──────────────────────────────────┐
│ Profile: balanced-performance      Mode: AUTO         │
│ Rule:    ac_medium                                    │
│                                                       │
│ CPU Load:  42%  ████████░░░░░░░░░░░░  (threshold: 70%)│
│ GPU Util:   8%  ██░░░░░░░░░░░░░░░░░░  (threshold: 15%)│
│ CPU Temp:  78°C ████████████████░░░░  (TJ: 100°C)    │
│ Power:     AC   Battery: 88%                          │
│                                                       │
│ History (recent changes):                             │
│  14:32:05 balanced → balanced-performance (ac_medium) │
│  14:28:12 quiet → balanced (ac_light)                 │
└───────────────────────────────────────────────────────┘
```

### `afp set <profile>`

Lock to a specific profile (disables auto-switching):

```bash
afp set performance    # Lock to max fans
afp set quiet          # Lock to low noise
afp set balanced       # Lock to moderate
```

### `afp auto`

Return to automatic mode:

```bash
afp auto
```

### `afp profiles`

List all available profiles with descriptions:

```
  1. low-power
     Minimal fans — silent, battery saving
  2. quiet
     Low noise — light office work
  3. balanced
     Moderate — general use
  4. balanced-performance
     Active cooling — sustained workloads
> 5. performance
     Full blast — gaming, heavy rendering
```

### `afp config [edit]`

```bash
afp config        # Show current config
afp config edit   # Open in $EDITOR
afp reload        # Apply changes without restart
```

## Configuration

Edit `~/.config/acer-fan-profiles/config.yaml`:

```yaml
# How often to check sensors (seconds)
polling_interval: 3

# CPU load thresholds (% average across all cores)
cpu_load_low: 15 # Below this = idle
cpu_load_medium: 40 # Below this = light load
cpu_load_high: 70 # Above this = heavy load

# GPU utilization threshold (%)
gpu_util_active: 15 # Above this = GPU active

# Temperature thresholds (°C)
# i9-13900HX TJunction is 100°C
temp_escalate: 92 # Force performance profile
temp_critical: 97 # Emergency + desktop notification

# Hysteresis delays (seconds)
upgrade_delay: 5 # Wait before switching to higher profile
downgrade_delay: 15 # Wait before switching to lower profile

# Desktop notifications
notify_enabled: true
notify_debounce: 10 # Min seconds between notifications

# Logging: debug, info, warn, error
log_level: info
```

### Decision Rules

Rules are evaluated top-to-bottom, first match wins:

| Priority | Rule             | Condition                       | Profile              |
| -------- | ---------------- | ------------------------------- | -------------------- |
| 100      | thermal_critical | CPU >= 97°C                     | performance          |
| 90       | thermal_escalate | CPU >= 92°C                     | performance          |
| —        | battery_idle     | Battery + CPU < 15% + GPU < 15% | low-power            |
| —        | battery_active   | Battery + any load              | quiet                |
| —        | ac_idle          | AC + CPU < 15% + GPU < 15%      | quiet                |
| —        | ac_light         | AC + CPU < 40% + GPU < 15%      | balanced             |
| —        | ac_medium        | AC + CPU < 70% + GPU < 15%      | balanced-performance |
| —        | ac_heavy         | AC + CPU >= 70% or GPU >= 15%   | performance          |

### Hysteresis

Prevents rapid profile switching when load fluctuates:

- **Upgrade** (e.g., balanced → performance): Requires sustained high load for **5 seconds**
- **Downgrade** (e.g., performance → balanced): Requires sustained low load for **15 seconds**
- **Thermal emergency**: Instant, bypasses all delays
- **Manual override**: Bypasses all rules

## Bash Aliases

Add to `~/.bashrc` for convenience:

```bash
alias fan-status='afp status'
alias fan-max='afp set performance'
alias fan-auto='afp auto'
alias fan-quiet='afp set quiet'
alias fan-monitor='afp monitor'
```

## Architecture

```
                     ┌──────────────────┐
                     │   Power State    │  /sys/class/power_supply/ACAD
                     │   (AC/Battery)   │
                     └────────┬─────────┘
                              │
┌──────────────┐              │
│  CPU Load    │──────────────┤
│  /proc/stat  │              │
└──────────────┘              ▼
                    ┌─────────────────────┐
┌──────────────┐    │   Decision Engine   │
│  GPU Usage   │───►│   (rule-based +     │
│  nvidia-smi  │    │    hysteresis)      │
└──────────────┘    └──────────┬──────────┘
                               │
┌──────────────┐               │
│  CPU Temp    │───►           │
│  /sys/thermal│    ┌──────────▼──────────┐
└──────────────┘    │  /sys/firmware/acpi/ │
                    │  platform_profile    │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │  Desktop Notify     │
                    │  + journald Log     │
                    └─────────────────────┘
```

### Interaction with system76-power

The daemon cooperates with — not replaces — `system76-power`:

| Component         | Manages                       | Interface        |
| ----------------- | ----------------------------- | ---------------- |
| system76-power    | CPU frequency, GPU power      | D-Bus, sysfs CPU |
| acer-fan-profiles | Fan curves (platform_profile) | sysfs ACPI       |

No conflicts. They manage different kernel interfaces.

### Safety

- **Read-only monitoring** of CPU, GPU, temp, power — no risk
- **Single write target**: `/sys/firmware/acpi/platform_profile`
- **Fails safe**: If daemon crashes, last profile stays active
- **No EC access**: Only uses safe sysfs interface
- **Watchdog**: Sets `performance` if sensors become unreadable

## Logs

```bash
# View daemon logs
journalctl -u acer-fan-profiles.service -f

# View recent profile changes
journalctl -u acer-fan-profiles.service --since "1 hour ago" | grep "Profile changed"
```

## Troubleshooting

### Daemon won't start

```bash
# Check status
systemctl status acer-fan-profiles.service

# Check if kernel parameter is set
cat /sys/module/acer_wmi/parameters/predator_v4
# Should show: Y

# Check if platform_profile exists
cat /sys/firmware/acpi/platform_profile
```

### Profile not switching

```bash
# Check daemon state
afp status

# Enable debug logging
afp config edit
# Change: log_level: debug
afp reload

# Watch decisions in real-time
journalctl -u acer-fan-profiles.service -f
```

### Fan RPM sensor accuracy

**With stock acer-wmi driver**: The sensor may show ~1413 RPM constantly (bitmask limitation).

**With Linuwu-Sense module**: The sensor shows accurate, varying RPM values (1900-6200 RPM range). Linuwu-Sense provides proper WMI integration for accurate readings.

## Hardware Info

| Component  | Value                               |
| ---------- | ----------------------------------- |
| Model      | Acer Predator PTX17-71              |
| Board      | Carrera_RTX (RPL, V1.09)            |
| CPU        | Intel i9-13900HX (TJunction: 100°C) |
| GPU        | NVIDIA RTX 4090 Laptop              |
| BIOS       | INSYDE V1.09 (2024-12-16)           |
| OS         | Pop!\_OS 24.04 LTS                  |
| Kernel     | 6.17.9-76061709-generic             |
| WMI Module | acer_wmi (predator_v4=Y)            |

## Files

| File     | Location                                        | Purpose                        |
| -------- | ----------------------------------------------- | ------------------------------ |
| Daemon   | `/usr/local/bin/acer-fan-profiles`              | Main daemon script             |
| CLI      | `/usr/local/bin/afp`                            | Command-line interface         |
| Service  | `/etc/systemd/system/acer-fan-profiles.service` | systemd unit                   |
| Config   | `~/.config/acer-fan-profiles/config.yaml`       | User thresholds                |
| State    | `/run/acer-fan-profiles/state.json`             | Runtime state (CLI reads this) |
| Override | `/run/acer-fan-profiles/override`               | Manual lock file               |
| PID      | `/run/acer-fan-profiles/daemon.pid`             | Daemon PID                     |

## License

Free to use and modify. Created for Acer Predator PTX17-71 on Pop!\_OS 24.04 LTS.
