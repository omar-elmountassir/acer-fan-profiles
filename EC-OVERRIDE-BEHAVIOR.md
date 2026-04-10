# EC Thermal Override Behavior

**Date**: 2026-01-31
**Status**: Documented
**Component**: Linuwu-Sense / Acer Embedded Controller

## Finding

The Acer Embedded Controller (EC) overrides ALL Linuwu fan_speed writes when thermal protection is active.

## Evidence

Testing conducted with high CPU temperature (thermal protection active):

| Linuwu Write | Expected | Actual  |
|--------------|----------|---------|
| `50,50`      | 50%,50%  | 100,100 |
| `0,0`        | 0%,0%    | 100,100 |
| `25,25`      | 25%,25%  | 100,100 |

All writes were successfully sent to `/sys/devices/platform/linuwu-wmi/fan_speed` but the EC ignored them and maintained 100,100 (full speed) throughout the thermal event.

## Implication

The AFP daemon (and any software using Linuwu) can **request** fan speeds, but the EC has **final authority** over actual fan behavior.

This creates a two-tier control hierarchy:

```
┌─────────────────────────────────────────┐
│            EC (Hardware)                │
│  - Final authority on fan speed         │
│  - Thermal protection overrides ALL     │
│  - Cannot be bypassed by software       │
└─────────────────────────────────────────┘
                    ▲
                    │ Requests (may be ignored)
                    │
┌─────────────────────────────────────────┐
│         Linuwu-Sense (Driver)           │
│  - Provides userspace interface         │
│  - Writes accepted but not guaranteed   │
│  - Effective only when EC permits       │
└─────────────────────────────────────────┘
                    ▲
                    │ Commands
                    │
┌─────────────────────────────────────────┐
│          AFP Daemon (Software)          │
│  - Profile-based fan management         │
│  - Sends speed requests via Linuwu      │
│  - No direct hardware control           │
└─────────────────────────────────────────┘
```

## When EC Overrides

- **During thermal protection**: When CPU/GPU temperatures exceed EC safety thresholds
- **During BIOS-level events**: POST, firmware updates, hardware initialization
- **Hardware stress conditions**: EC prioritizes component safety over user preferences

## When Linuwu Works

- **At idle/moderate temperatures**: When EC determines no thermal intervention is needed
- **Normal operating conditions**: EC respects Linuwu values as "suggestions"
- **Post-thermal event**: Once temperatures normalize, EC releases override

## Design Rationale

**Hardware safety > Software control**

This is correct and expected behavior:

1. **Component Protection**: Prevents software bugs from damaging hardware
2. **Fail-Safe Design**: Even if AFP crashes, EC maintains thermal safety
3. **Liability Shield**: OEM cannot be blamed for thermal damage from third-party software
4. **Universal Pattern**: All laptop ECs implement similar override behavior

## Implications for AFP Development

1. **Accept EC authority**: Do not attempt to "fight" EC decisions
2. **Monitor, don't assume**: Read actual fan speeds, don't assume writes succeeded
3. **Graceful degradation**: When EC overrides, log it and wait for release
4. **No infinite retries**: Repeatedly writing during thermal override wastes cycles
5. **User communication**: Inform users when EC has taken control

## Related Files

- `acer-fan-profiles.sh` - AFP daemon implementation
- `README.md` - AFP overview and usage
- `CHANGELOG.md` - Version history
- `/sys/devices/platform/linuwu-wmi/fan_speed` - Linuwu control interface
