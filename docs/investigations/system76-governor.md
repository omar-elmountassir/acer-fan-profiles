---
date: 2026-04-24
status: documented
type: investigation
about: AFP vs system76-power vs CPU governor interaction
---

# AFP / system76-power / Governor — Interaction Analysis

**Date** : 2026-04-24
**Status** : documented (no action item — informational)
**Origin** : migrated from `~/nova/.claude/plans/afp-system76-governor-investigation-2026-04-24.md` (2026-05-12)

---

## Verdict (1 ligne)

Persister `governor=performance` : **SAFE-WITH-CAVEATS** — AFP ne touche PAS au CPU governor, mais system76-power réécrit le governor en `powersave` (profil Balanced) à chaque boot. Il faut court-circuiter ce comportement proprement plutôt que d'écrire directement dans sysfs.

---

## Daemon inventory (état réel 2026-04-24)

| Daemon | État | Enabled | Notes |
|---|---|---|---|
| `com.system76.PowerDaemon` | **active (running)** | enabled | PID 1448, démarré 18:44:41 |
| `acer-fan-profiles` | **active (running)** | enabled | PID 2075, démarré 18:44:42 |

**Contradiction trouvée avec la KB legacy** : l'AFP Knowledge Base disait `system76-power masked`. **Faux** : il tourne en parallèle. La KB doit être corrigée (TODO Phase 3 split).

---

## 5 réponses

### 1. AFP touche-t-il au governor ?

**NON**. Grep `governor\|scaling_governor\|cpufreq\|cpupower` dans `acer-fan-profiles` → 0 résultats.

AFP opère exclusivement sur :
- `/sys/firmware/acpi/platform_profile` (ACPI EC hints + fan floor)
- `/sys/module/linuwu_sense/.../predator_sense/fan_speed` (Linuwu fan speed sysfs)

### 2. Cohabitation system76-power + AFP

Cohabitation active, conflit limité.

- AFP démarre 1s après system76-power
- system76-power échoue à contrôler les fans : `[ERROR] fan daemon: platform hwmon not found`
- AFP prend le contrôle des fans via Linuwu-Sense
- Conflit observable : les deux daemons écrivent dans `platform_profile`. AFP gagne car il tourne en boucle 3s.

### 3. Pourquoi le governor revert à `powersave` au boot ?

system76-power applique son profil Balanced par défaut au démarrage du daemon :
- `scaling_governor = powersave`
- `energy_performance_preference = balance_performance`
- Cap temporaire max freq 2.2 GHz lors de l'init (levé ensuite)

**Pas de fichier de config persisté** pour system76-power. `sudo system76-power profile performance` avant reboot ne survit pas — comportement hard-coded.

### 4. Méthode SAFE recommandée

**Option B — systemd oneshot après le daemon** :

```ini
# /etc/systemd/system/system76-performance-profile.service
[Unit]
Description=Set system76-power to performance profile at boot
After=com.system76.PowerDaemon.service
Requires=com.system76.PowerDaemon.service

[Service]
Type=oneshot
ExecStart=/usr/bin/system76-power profile performance
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Pourquoi B et pas autre :
- A (user service) ne peut pas changer un daemon root via DBus
- C (cpufrequtils) conflit avec intel_pstate
- D (sysfs direct) fragile : system76-power peut réécrire
- E (accepter powersave) acceptable si workload léger (intel_pstate active autorise boost)

### 5. Risque thermique en `performance` governor

Modéré. Le passage à `performance` pousse plus de chaleur. AFP suit avec ses bandes (`temp_escalate_trigger=88°C` → turbo 100%). TJunction = 100°C donc 12°C de marge. Pas dangereux, juste plus bruyant sous charge.

Mitigation : `EPP=balance_performance` (compromise actuel) reste un bon défaut.

---

## Suite donnée

**2026-05-12** : un nouveau bug a été découvert dans la même zone du code (AFP qui ignore `cooperative_mode`). Voir [cooperative-mode-bug.md](cooperative-mode-bug.md). Les findings ci-dessus restent valides — pas de régression sur l'interaction governor.

---

## Sources d'évidence

| Source | Evidence |
|---|---|
| `acer-fan-profiles` daemon source | Grep governor → 0 résultats |
| `journalctl -b -u com.system76.PowerDaemon` | "setting powersave with max 2200000" |
| `systemctl status com.system76.PowerDaemon` | active (running) |
| `system76-power profile` | "Power Profile: Balanced" |
| `/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor` | "powersave" |
| `/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference` | "balance_performance" |
| `/sys/devices/system/cpu/intel_pstate/status` | "active" |

---

## Incertitudes restantes

1. **Cap 2.2 GHz** : transitoire ou persistant ? Non instrumenté.
2. **COOPERATIVE_MODE** déployé : avant 2026-05-12, le default `false` était utilisé silencieusement (bug découvert ensuite — voir [cooperative-mode-bug.md](cooperative-mode-bug.md)).
3. **Race condition** `platform_profile` non mesurée.
