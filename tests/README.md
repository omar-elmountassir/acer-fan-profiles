# AFP tests

Test harness for the Acer Fan Profiles daemon and CLI.

## Layout

| File | Type | What it does |
|---|---|---|
| `shellcheck.sh` | static | Run shellcheck on daemon + CLI + install/uninstall scripts |
| `test_compute_profile.sh` | unit | Source the daemon (with `AFP_NO_MAIN=1`), mock sensor inputs via env vars, exercise `evaluate_rules` and `apply_hysteresis` against known cases (idle AC, battery, thermal_elevated coop/legacy, thermal_critical, hysteresis bands) |
| `test_fan_curve.sh` | unit | Test the linear interpolation in `calculate_curve_fan_speed` at curve points and between |
| `smoke-test.sh` | manual | Checklist run against the live hardware after install (visual confirmation in `afp status`) |

## How to run

From the repo root:

```bash
make test        # runs shellcheck + all *.sh unit tests
make lint        # shellcheck only
./tests/smoke-test.sh  # manual hardware checklist (interactive)
```

## Philosophy

- Pure-bash, no external test framework (no bats, no shunit2) — keeps the repo light and avoids dependency drift.
- Unit tests source the daemon with `AFP_NO_MAIN=1` to get access to all functions without starting the daemon loop.
- Mocks are env-var overrides, not function redefinitions — keeps the test surface explicit.
- Smoke test is manual because thermal behavior is fundamentally hardware-dependent — but it has a deterministic checklist so it is repeatable.

## Adding new tests

Each test file is a standalone bash script that:

1. Sources the daemon with `AFP_NO_MAIN=1`
2. Defines small helper functions for assertion (`assert_eq`, `assert_contains`)
3. Runs N test cases, each prints `PASS: <name>` or `FAIL: <name>: expected X got Y`
4. Exits 0 if all pass, 1 if any fail

The `Makefile` aggregates exit codes.
