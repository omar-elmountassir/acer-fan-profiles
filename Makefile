.PHONY: test lint install uninstall smoke

# Run all unit tests + lint
test: lint
	@echo "=== test_compute_profile.sh ==="
	@bash tests/test_compute_profile.sh
	@echo ""
	@echo "=== test_fan_curve.sh ==="
	@bash tests/test_fan_curve.sh

# Static analysis
lint:
	@bash tests/shellcheck.sh

# Hardware smoke test (manual checklist, interactive)
smoke:
	@bash tests/smoke-test.sh

# Install daemon + CLI to /usr/local/bin (requires sudo)
install:
	@bash install.sh

uninstall:
	@bash uninstall.sh

# Convenience: run tests then install if all green
install-tested: test install
