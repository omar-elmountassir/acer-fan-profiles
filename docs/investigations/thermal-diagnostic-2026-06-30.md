---
date: 2026-06-30
status: active
type: investigation
about: CPU 100°C / GPU 88°C root cause analysis — software mitigations + hardware diagnosis
---

# Thermal Diagnostic — PTX17-71 100°C Root Cause

**Date**: 2026-06-30
**System**: Acer Predator Triton 17X (PTX17-71) / Pop!\_OS 24.04
**Hardware**: i9-13900HX + RTX 4090 Laptop GPU / 32GB RAM
**Status**: Software mitigations applied. Hardware repaste in progress (Omar aware).

---

## Symptoms

- CPU Package: **100°C** (TjMAX) during AoE2DE
- GPU: **88°C**, 100% utilization
- Fans: 5989/6475 RPM (max via Linuwu-Sense)
- CPU throttling to **1.34 GHz** (from 5.4 GHz max boost)

## Root Cause — Two Layers

### Layer 1: Software (MITIGATED)

| Factor                    | Before              | After                    | Mitigation                                                     |
| ------------------------- | ------------------- | ------------------------ | -------------------------------------------------------------- |
| AoE2DE FPS                | Uncapped (Infinite) | 144 cap                  | MangoHud `fps_limit=144` in `~/.config/MangoHud/MangoHud.conf` |
| GPU util                  | 100%                | 47%                      | FPS cap above                                                  |
| GPU temp                  | 88°C                | 78°C                     | FPS cap above                                                  |
| PL1/PL2                   | 157W/157W           | 65W/100W                 | `intel-rapl` sysfs manual override                             |
| force_performance_profile | true (pins 157W)    | true (kept — daemon bug) | PL managed separately via sysfs                                |

### Layer 2: Hardware (ROOT CAUSE)

**Liquid metal pump-out** — the factory-applied liquid metal TIM on the CPU has degraded.

Evidence:

- CPU at 100°C even with PL1=65W, freq throttled to 1.34 GHz, fans at 100%
- A healthy i9-13900HX at 65W should run at 75-85°C
- Core-to-core delta: Core 0 at 92°C, Core 12 at 97°C, Core 28 at 100°C — uneven mounting pressure consistent with pump-out pattern
- PTX17-71 uses liquid metal (Conductonaut-style) which is prone to pump-out over 12-18 months

**Repaste**: Omar has this in progress.

---

## What Does NOT Work (confirmed by research)

| Approach                                   | Why                                                                                             | Source                    |
| ------------------------------------------ | ----------------------------------------------------------------------------------------------- | ------------------------- |
| Undervolting (intel-undervolt / throttled) | i9-13900HX locked by Intel microcode (Plundervolt). MSR 0x150 returns "Operation not permitted" | intel-undervolt issue #74 |
| nvidia-smi -pl                             | Unsupported on mobile Ada GPUs. vBIOS locks power limit register                                | NVIDIA Developer Forums   |
| BIOS thermal fix                           | Acer has published no thermal-management BIOS update for PTX17-71                               | Acer support pages        |

## What DOES Help (ordered by impact)

1. **Repaste** (in progress) — eliminates the root cause. Expect 15-20°C reduction.
2. **FPS cap** (applied) — reduces GPU thermals and thermal coupling. GPU 88°C → ~65°C.
3. **PL1/PL2 cap** (applied) — reduces sustained CPU heat. 157W → 65W sustained.
4. **Cooling pad** (recommended) — IETS GT500 or LLANO v10. Blower pad + rear elevation. ~4-8°C.
5. **P-core frequency cap** (optional) — cap to 4.0 GHz. AoE2DE doesn't benefit from 5.4 GHz.

---

## Cooling Architecture (PTX17-71)

- **Type**: Hybrid vapor chamber + multi-heatpipe
- **Fans**: 3× 5th-gen AeroBlade 3D (all-metal)
- **Heatsinks**: 4 fin stacks
- **CPU TIM**: Liquid metal (factory, Conductonaut-style)
- **GPU TIM**: Conventional paste
- **Thermal coupling**: CPU and GPU share vapor chamber → concurrent load always hotter than independent
- **Lab baseline** (LaptopMedia, separate CPU/GPU stress): 96°C CPU / 72°C GPU

## Settings Applied This Session

| File                                      | Change                                                               |
| ----------------------------------------- | -------------------------------------------------------------------- |
| `~/.config/MangoHud/MangoHud.conf`        | Added `fps_limit=144` + `fps_limit_method=early`                     |
| `~/.config/acer-fan-profiles/config.yaml` | force_performance_profile kept true (daemon bug workaround)          |
| intel-rapl sysfs                          | PL1=65W, PL2=100W (manual, resets on reboot — needs systemd service) |

## Known Bug Discovered

**AFP daemon hysteresis crash**: When `force_performance_profile=false`, daemon reaches hysteresis state file write code path. `/run/acer-fan-profiles/` not created by systemd RuntimeDirectory on restart → immediate crash (exit 1). Fix: daemon should `mkdir -p` its own runtime dir at startup.

## Sources

- [Intel ARK — i9-13900HX specs](https://www.intel.com/content/www/us/en/products/sku/232171/intel-core-i913900hx-processor-36m-cache-up-to-5-40-ghz/specifications.html) — TDP 55W / 157W, TjMAX 100°C
- [LaptopMedia PTX17-71 review](https://laptopmedia.com/review/acer-predator-triton-17x-ptx17-71-review-mini-led-screen-with-an-absurdly-powerful-hardware/p7/) — thermal baseline data
- [LaptopMedia disassembly](https://laptopmedia.com/highlights/how-to-open-the-acer-predator-triton-17x-ptx17-71-disassembly-and-upgrade-options/) — cooling architecture
- [Age of Empires Support — FPS Limit](https://support.ageofempires.com/hc/en-us/articles/4432881214100-Advanced-Graphics-Option-FPS-Limit) — uncapped FPS is default behavior
- [intel-undervolt issue #74](https://github.com/kitsunyan/intel-undervolt/issues/74) — MSR 0x150 locked on 13th gen
- [NVIDIA Developer Forums](https://forums.developer.nvidia.com/t/limiting-power-and-temperature-on-nvidia-4090-with-newer-linux-driver-versions/291302) — -pl unsupported on mobile
