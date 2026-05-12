---
date: 2026-05-12
status: resolved
type: investigation
resolved-in: v2.1.0
---

# Cooperative Mode Bug — RCA & Fix (v2.1.0)

**Date** : 2026-05-12
**System** : Acer Predator PTX17-71 / Pop!_OS 24.04 / kernel 6.18.7
**Status** : RESOLVED in v2.1.0 (commit `0f65af4`)
**Symptom observable** : fans à ~6000 RPM, CPU à 93°C, alors que la load CPU mesurée était à 3%.

---

## Executive Summary

Trois bugs **combinés** dans le code AFP empêchaient `cooperative_mode: true` (présent dans la config user depuis 2026-04-17) d'avoir le moindre effet :

1. `load_config()` ne parsait pas la clé `cooperative_mode` → variable globale `COOPERATIVE_MODE` restait à son default `false` silencieusement
2. Dans `evaluate_rules()`, la branche `thermal_elevated` retournait `performance` **hardcoded**, sans regarder `cooperative_mode`
3. Dans `main_loop`, le branchement coop ne re-déclenchait pas l'écriture des fans si `final_profile == current_profile` → même quand le rule était correct, l'écriture Linuwu était sautée

Résultat empirique : à ≥78°C (seuil `temp_elevated_trigger`), AFP forçait `performance` dans le platform_profile, ce qui sur un i9-13900HX laptop dépasse instantanément 78°C même au repos → boucle d'hystérésis pathologique → fans à fond en permanence.

---

## Mesures avant/après

| Métrique | Avant (loop) | Après (v2.1.0) | Delta |
|---|---|---|---|
| CPU package | 91-94 °C | 71-72 °C | **-21 °C** |
| Fan 1 | 5827 RPM | 1773 RPM | **-70 %** |
| Fan 2 | 6286 RPM | 1719 RPM | **-73 %** |
| Profile | `performance` (loop perf↔turbo) | `balanced` (curve actif) | mode auto restauré |
| Rule | thermal loop | ac_idle (curve floor 10%) | normal |
| CPU load | 3% | 3% | inchangé |

---

## Investigation

### Symptôme initial

Le Principal a signalé que les ventilateurs tournaient fort. Premier diagnostic via `sensors` + `ps` :
- CPU à 93°C, fans à 5827/6286 RPM
- Mais : load CPU = 3%, fréquences entre 1.2-2.8 GHz (loin du turbo 5.4 GHz)
- → ce n'est pas la charge logicielle. Quelque chose maintient le CPU thermiquement chaud sans raison de charge.

### Premier indice : combat AFP ↔ profile

`afp status` montre :
```
Profile: performance  Mode: auto
Rule: thermal_critical (CPU at 93C - emergency max cooling)
Last: low-power → performance 33s ago
```

`journalctl -u acer-fan-profiles` :
```
00:36:23 Profile changed: performance -> turbo (thermal_critical at 92C)
00:36:27 External profile change detected: turbo -> performance
00:36:31 External profile change detected: turbo -> low-power
00:36:31 Profile changed: low-power -> performance (thermal_elevated: 71C)
```

Lecture : AFP se bat avec lui-même. Quand temp ≥78°C il met `performance`, ce qui chauffe → temp monte → AFP escalade à `turbo`, ce qui descend la temp à 71°C → AFP redescend à... `performance` à nouveau parce que sa propre règle `thermal_elevated` est ≥78°C trigger / <71°C release et la temp oscille dans cette zone.

### Identification de la racine 1 : `cooperative_mode` jamais parsé

Test : `sudo afp set balanced` (lock manuel). Résultat immédiat : CPU passe à 67°C, fans à 3000 RPM. **Donc le mode auto d'AFP est bien la source du problème**.

Lecture du code daemon : la fonction `load_config()` (lignes ~322-355) avait un `case "$key" in` pour toutes les clés YAML... **sauf `cooperative_mode`**. La variable `COOPERATIVE_MODE` était déclarée à `false` en haut du script (ligne 41) et utilisée dans `main_loop` (ligne 1467, 1506), mais jamais hydratée depuis la config user.

→ Le `cooperative_mode: true` dans `~/.config/acer-fan-profiles/config.yaml` était silencieusement ignoré depuis avr-17 (date du commit user qui l'avait ajouté).

### Identification de la racine 2 : `thermal_elevated → performance` hardcoded

Lecture de `evaluate_rules()`, la branche `thermal_elevated` (lignes ~742-746) :

```bash
if $thermal_elevated; then
    write_thermal_state ...
    echo "performance|thermal_elevated|CPU at ${cpu_temp}C - elevated thermal response"
    return
fi
```

Asymétrie suspecte : pour `thermal_critical` et `thermal_escalate`, le profile est calculé dynamiquement (`local max_profile="performance"; [[ "$LINUWU_AVAILABLE" == "true" ]] && max_profile="turbo"`). Pour `thermal_elevated`, c'est **hardcoded `performance`**. Même si `cooperative_mode` était correctement parsé, cette branche l'ignorerait.

### Identification de la racine 3 : `main_loop` ne ré-applique pas si profile inchangé

Lecture du `main_loop` (lignes ~1503-1505) :

```bash
if [[ "$final_profile" != "$current_profile" ]] || [[ "$FIRST_ITERATION" == "true" ]]; then
    if [[ "$COOPERATIVE_MODE" == "true" && "$LINUWU_AVAILABLE" == "true" ]]; then
        ...
```

Problème : en cooperative mode + thermal_elevated, on veut préserver `current_profile` MAIS booster les fans à 75%. Avec le code original, `final_profile == current_profile` → la condition est fausse → le bloc d'application est sauté → les fans ne sont jamais boostés. Le rule fire dans `evaluate_rules` mais reste lettre morte.

---

## Fix (v2.1.0)

3 diffs daemon + 1 diff CLI + 1 entrée CHANGELOG :

### 1A — Parser `cooperative_mode` dans `load_config()`

```diff
             gpu_util_active)    GPU_UTIL_ACTIVE="$value" ;;
+            cooperative_mode)   COOPERATIVE_MODE="$value" ;;
             # Legacy single-threshold config (backward compatibility)
```

Plus validation booléenne dans `validate_config` (refuse les valeurs non-true/false).
Plus inclusion dans le log d'init (`cooperative=true/false`).

### 1B — Honorer `COOPERATIVE_MODE` dans `evaluate_rules()`

```diff
     if $thermal_elevated; then
         write_thermal_state ...
-        echo "performance|thermal_elevated|CPU at ${cpu_temp}C - elevated thermal response"
+        if [[ "$COOPERATIVE_MODE" == "true" ]]; then
+            echo "${current_profile:-balanced}|thermal_elevated_coop|CPU at ${cpu_temp}C - cooperative fan boost"
+        else
+            echo "performance|thermal_elevated|CPU at ${cpu_temp}C - elevated thermal response"
+        fi
         return
     fi
```

### 1C — `main_loop` ré-applique en `thermal_elevated_coop`

```diff
-    if [[ "$final_profile" != "$current_profile" ]] || [[ "$FIRST_ITERATION" == "true" ]]; then
+    if [[ "$final_profile" != "$current_profile" ]] || [[ "$FIRST_ITERATION" == "true" ]] || [[ "$rule" == "thermal_elevated_coop" ]]; then
```

Plus override des fan_cpu/fan_gpu pour `thermal_elevated_coop` :

```bash
if [[ "$rule" == "thermal_elevated_coop" ]]; then
    fan_cpu=$FAN_SPEED_PERFORMANCE
    fan_gpu=$FAN_SPEED_PERFORMANCE
fi
```

### 2 — Affichage curve granulaire dans `afp status` (cmd_status)

Quand `state.curve_mode == true` et `state.curve_target != null` :

```
Profile:    balanced (curve active)
Curve:      35% target → 28% applied (ramping down, ±5%/3s)
Recent:     curve:55 → 50 → 45 → 40 → 35
```

La fan curve granulaire (v2.0.0) **fonctionnait déjà** dans le code mais était invisible parce que :
- Le bug `thermal_elevated → performance` empêchait AFP de retomber en `ac_idle` (seul état où la curve s'active)
- `afp status` n'affichait rien sur le curve mode même quand il était actif

---

## Lessons (au-delà du code)

1. **Symptôme ≠ root cause** : "fans hurlent" diagnostiqué comme "load CPU" en première intention. Bonne pratique : mesurer load **et** observer le state du daemon avant de conclure.

2. **Asymétrie suspecte = signal** : quand le code traite deux cas similaires de façons différentes (`thermal_critical` calculé, `thermal_elevated` hardcoded), c'est probablement un oubli, pas un design intentionnel. Lire les voisins du code suspect aide.

3. **Config silencieusement ignorée** : la pire variante de bug. Le user pensait que `cooperative_mode: true` était actif depuis 4 mois. Validation booléenne (ajoutée en 1A) refuse maintenant les valeurs non-true/false → garantit qu'on saurait si on tape mal la clé.

4. **3 bugs combinés** : aucun des 3 seul n'aurait produit le symptôme. Tester chaque branche en isolation (cf. Phase 2 tests AFP) aurait attrapé chacun individuellement, mais surtout aurait empêché la régression.

5. **Doc dispersée** ralentit le diag. L'investigation a dû lire 4 emplacements de doc (README repo, EC-OVERRIDE-BEHAVIOR, vault knowledge-base, nova plans). C'est ce qui motive la consolidation Phase 3 du plan global 2026-05-12.

---

## Related

- [threshold-dancing.md](threshold-dancing.md) — RCA du fix v1.1.0 hysteresis bands (cas voisin : oscillation thermique)
- [system76-governor.md](system76-governor.md) — confirme la cohabitation AFP + system76-power (Phase 6 du plan 2026-05-12 traite l'archivage mcp-memory-service)
- `docs/ec-override-behavior.md` — EC fan override pendant thermal protection
- Plan global 2026-05-12 — `~/.claude/plans/nifty-baking-backus.md`
- Commit `0f65af4` — v2.1.0 release
- Tests : `tests/test_compute_profile.sh` (cas T7-T12 couvrent cooperative_mode + hysteresis)
