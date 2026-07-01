---
date: 2026-01-31
status: closed
type: audit
closed-in: v2.0.0 (2026-04-10)
---

# AFP Audit 2026-01-31 — Code Quality Review

**Date** : 2026-01-31
**Code Quality Score** : 7/10
**Status** : CLOSED — all critical and important fixes deployed in v2.0.0 (2026-04-10)
**Origin** : migrated from `~/vault/projects/stream/active/afp-improvements.md` (2026-05-12)

---

## Issues by Priority

### CRITICAL (3) — all closed

#### C1: YAML Parser sans validation — ✅ deployed v2.0.0

Aucune validation numérique/range/type des valeurs config. Risque d'accepter `polling_interval: "abc"` ou `cpu_load_high: 500`.

**Fix** : validation explicite par type, range checks (0-100% pour pourcentages, 0-120°C pour temps), refus de démarrage sur config invalide.

#### C2: Race condition state file — ✅ deployed v2.0.0

```bash
source "$HYSTERESIS_STATE_FILE"  # Read
# daemon killed here = corruption
echo "..." > "$HYSTERESIS_STATE_FILE"  # Write
```

**Fix** : atomic write (tmp + mv) sur tous les state files (hysteresis + thermal).

#### C3: Sourcing external file sans validation — ✅ deployed v2.0.0

`source "$THERMAL_STATE_FILE"` = arbitrary code execution si le fichier est corrompu.

**Fix** : parsing explicite `while IFS='=' read -r key value; do case "$key" in...`.

---

### IMPORTANT (6) — all closed

| ID  | Issue                               | Fix                                                          | Closed |
| --- | ----------------------------------- | ------------------------------------------------------------ | ------ |
| I1  | Pas de watchdog sensors             | Counter consecutive failures, escalate à performance après 5 | v2.0.0 |
| I2  | CPU temp returns 0 on failure       | Return 100 (fail-safe hot)                                   | v2.0.0 |
| I3  | GPU util failure silencieux         | Log warnings, fail-safe to active threshold                  | v2.0.0 |
| I4  | Signal handler re-entrancy          | Flag-based handlers, processed in main loop                  | v2.0.0 |
| I5  | Notification user detection fragile | `loginctl`-based detection                                   | v2.0.0 |
| I6  | Hardcoded battery path              | Dynamic detection via `/sys/class/power_supply/` glob        | v2.0.0 |

---

### NICE-TO-HAVE (8) — non bloquant

N1-N8 (config validation hot-reload, min polling interval, JSON escaping, PID staleness, service deps, monitor signal, log routing, log rotation docs). Non bloquant, à traiter au cas par cas si nécessaire.

---

### DOCUMENTATION (3) — partiel

| ID  | Issue                                  | Status                                                          |
| --- | -------------------------------------- | --------------------------------------------------------------- |
| D1  | README temperature thresholds outdated | Closed v2.1.0 (2026-05-12)                                      |
| D2  | COOPERATIVE_MODE not documented        | **Open** (à compléter dans `docs/concepts/cooperative-mode.md`) |
| D3  | No man page                            | Open (P3)                                                       |

---

### SERVICE RELIABILITY (2) — open

| ID  | Issue                    | Action                                           |
| --- | ------------------------ | ------------------------------------------------ |
| R1  | RestartSec=5s trop court | Add `StartLimitBurst`/`Interval` to systemd unit |
| R2  | Pas de resource limits   | Add `MemoryMax=50M, CPUQuota=5%`                 |

---

## Positive Aspects (à conserver)

- `set -euo pipefail` strict
- Thermal hysteresis bands bien implémentées (v1.1.0)
- Cooperative mode opt-in (mais voir bug 2026-05-12)
- State persistence via JSON
- Linuwu-Sense integration avec graceful degradation
- Signal handling SIGHUP/SIGTERM
- Security hardening dans systemd unit
- Variable naming clair
- Version tracking explicite

---

## Lessons learned

- **Audit → fix → close** cycle de 70 jours (audit 2026-01-31, déploiement v2.0.0 le 2026-04-10). Acceptable pour un daemon non-critique mais pourrait être plus court avec tests automatiques (cf. Phase 2 du plan global 2026-05-12).
- **Pas de tests** lors de l'audit = découverte des problèmes en prod (incident fan failure 2026-02-09). Phase 2 a ajouté `tests/` en 2026-05-12 pour éviter ce cycle.
- **Doc dispersée** entre vault, holon, nova — c'est ce qui motive la consolidation Phase 3 (2026-05-12).
