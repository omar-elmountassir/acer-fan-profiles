---
date: 2026-01-31
status: resolved
type: investigation
resolved-in: v1.1.0 (hysteresis bands)
---

# Threshold Dancing — RCA & Fix

**Date** : 2026-01-31 04:46 +01
**System** : Acer Predator PTX17-71 / Phase 2 (Average Core Temp)
**Status** : RESOLVED in v1.1.0 (hysteresis bands deployed)
**Origin** : migrated from `~/holon/hands/infra/services/nexus/hardware/acer-fan-profiles/threshold-dancing-analysis.md` (2026-05-12)

---

## Executive Summary

Le système restait coincé en `performance` à cause d'un **threshold dancing** à 65°C : la règle `thermal_elevated` bypassait l'hystérésis et le timer de downgrade se réinitialisait avant complétion.

Fix appliqué en v1.1.0 : **bandes d'hystérésis 7°C** (trigger/release séparés) sur les 3 tiers thermiques.

---

## Root Cause

Température oscille 55-65°C → système stuck en `performance` même à load 6% / GPU <35%.

```
Time  Temp  Rule             Target      Hysteresis State
----  ----  ----             ------      ----------------
T+0   62°C  ac_idle          quiet       Start 15s timer to quiet
T+3   65°C  thermal_elevated performance TIMER RESET (thermal bypass)
T+6   62°C  ac_idle          quiet       Start 15s timer to quiet
T+9   65°C  thermal_elevated performance TIMER RESET (thermal bypass)
...   ...   ...              ...         TIMER NEVER COMPLETES
```

Le timer de downgrade ne franchit jamais 15s → blocage en performance perpétuel.

---

## Bugs identifiés (5)

1. **Single-point threshold** sans release band — oscille au boundary
2. **Pas de logging** des rule matches et hysteresis state
3. **Thermal bypass** réinitialise le pending timer inconditionnellement
4. **Pas de smoothing température** — single spike déclenche
5. **Seuil 65°C trop bas** pour `average temp` (vs 68°C pour `package temp` qui marchait en Phase 1)

---

## Fix déployé (v1.1.0, 2026-01-31)

### Configuration

Bandes d'hystérésis 7°C sur 3 tiers :

| Tier | Trigger | Release | Action |
|---|---|---|---|
| Elevated | 78°C | 71°C | performance (75% fans) |
| Escalate | 88°C | 81°C | turbo (100%) |
| Critical | 96°C | 89°C | emergency turbo (100%) |

### Code

```bash
# evaluate_rules() : thermal_elevated avec band
if $thermal_elevated; then
    # Déjà actif → vérifier release threshold
    if [[ $cpu_temp -lt $TEMP_ELEVATED_RELEASE ]]; then
        thermal_elevated=false
    fi
else
    # Pas actif → vérifier trigger threshold
    if [[ $cpu_temp -ge $TEMP_ELEVATED_TRIGGER ]]; then
        thermal_elevated=true
    fi
fi
```

Plus observabilité : logs `Thermal elevated activated/deactivated (temp X°C ≥/< Y°C)`.

---

## Lessons

- **Phase 1 marche, Phase 2 cassait** : la `package temp` est plus stable (50-65°C operating range, 6-11°C margin à 68°C). L'`average temp` est plus volatile (55-65°C operating, margin 2-7°C seulement à 65°C — insuffisant).
- **Margin > volatility** est la règle empirique : si la fluctuation typique dépasse l'écart entre seuil et operating range, threshold dancing inévitable.
- **Hystérésis = bandes, pas points** : tout seuil thermique doit avoir trigger ≠ release avec gap ≥ volatility band.

---

## Related

- [system76-governor-2026-04-24.md](system76-governor-2026-04-24.md) — confirme que le fix v1.1.0 a tenu
- [cooperative-mode-bug-2026-05-12.md](cooperative-mode-bug-2026-05-12.md) — bug suivant : `thermal_elevated` correctement bandé mais `→ performance` hardcoded ignorait `cooperative_mode`
- `docs/concepts/configuration.md` — config actuelle (TODO: à créer post-split de la KB)
