# afp — acer-fan-profiles

Fan control daemon for Acer Predator laptops. Bash, 1600 lines.

## Dev Workflow

**CRITICAL — two copies exist. The repo is NOT what runs.**

```
~/hub/envs/acer-fan-profiles/acer-fan-profiles  ← repo (git source)
/usr/local/bin/acer-fan-profiles                 ← installed binary (systemd runs this)
```

When modifying code:
1. Edit the REPO copy (`./acer-fan-profiles`)
2. Copy to installed location: `sudo cp ./acer-fan-profiles /usr/local/bin/acer-fan-profiles`
3. Restart: `sudo systemctl restart acer-fan-profiles.service`
4. Test (see Testing section below)
5. If validated: commit + push in repo

**Never edit `/usr/local/bin/acer-fan-profiles` directly. Always edit the repo copy first.**

## Architecture

- `evaluate_rules()` (~line 674) — determines target profile based on CPU load, GPU util, temp, AC/battery
- `set_profile()` (~line 962) — writes to ACPI + Linuwu-Sense sysfs
- `apply_hysteresis()` (~line 855) — prevents rapid profile switching
- `calculate_curve_fan_speed()` (~line 149) — piecewise linear interpolation from temp to fan %
- `apply_step_limit()` (~line 183) — limits fan speed change per cycle
- Main loop (~line 1500) — polls sensors, evaluates, applies

## Key Files

| File | Path | Purpose |
|---|---|---|
| Daemon (repo) | `./acer-fan-profiles` | Git source |
| Daemon (installed) | `/usr/local/bin/acer-fan-profiles` | Systemd runs this |
| CLI | `/usr/local/bin/afp` | User-facing CLI |
| Config | `~/.config/acer-fan-profiles/config.yaml` | Runtime config |
| Systemd unit | `/etc/systemd/system/acer-fan-profiles.service` | Service definition |
| State | `/run/acer-fan-profiles/state.json` | Runtime state (JSON) |
| Thermal state | `/run/acer-fan-profiles/thermal.state` | Thermal mode persistence |
| Linuwu fan control | `/sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/predator_sense/fan_speed` | Fan speed sysfs |
| ACPI profile | `/sys/firmware/acpi/platform_profile` | Platform profile sysfs |

## Machine Context

- Acer Predator Triton 17X (PTX17-71)
- i9-13900HX: idle temp 70-76°C (normal for this chip, NOT a problem)
- RTX 4090 Laptop: GPU util fluctuates 8-50% at idle desktop
- Pop!_OS 24.04, kernel 6.18.7
- linuwu_sense 1.0.0 via DKMS
- cooperative_mode: false (afp manages fans + platform_profile autonomously, system76-power is masked)

## Testing

After any code change:
```bash
sudo cp ./acer-fan-profiles /usr/local/bin/acer-fan-profiles
sudo systemctl restart acer-fan-profiles.service
sleep 5

# Quick check
cat /run/acer-fan-profiles/state.json | python3 -m json.tool

# Monitor 3 minutes
for i in $(seq 1 60); do
  cat /run/acer-fan-profiles/state.json | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(f'{d[\"profile\"]:20s} | {d[\"rule\"]:20s} | GPU:{d[\"gpu_util\"]:3s}% | Temp:{d[\"cpu_temp\"]:3s}C | Fans:{d[\"linuwu_fan_speed\"]}')" 2>/dev/null
  sleep 3
done

# Check journal
journalctl -u acer-fan-profiles.service --since "5 min ago" --no-pager | tail -20
```

## Active Issues

- #1: Portability / multi-user / install workflow
- #2: Flapping bug (RCA with 6 sub-bugs, Bug 1 fixed)

## Config Defaults (important for threshold tuning)

- `temp_elevated_trigger: 78°C` / `release: 71°C` — too close to i9-13900HX idle (70-76°C)
- `gpu_util_active: 50` — catches desktop compositor spikes
- `fan_curve_floor: 10` — minimum fan speed in curve mode
- `fan_curve_step_limit: 5` — max % change per 3s cycle
