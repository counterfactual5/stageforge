.PHONY: install test clean

PREFIX ?=/usr/local

install:
	@echo "Installing stageforge to $(PREFIX)/bin..."
	@cp bin/stageforge $(PREFIX)/bin/stageforge
	@chmod +x $(PREFIX)/bin/stageforge
	@mkdir -p $(PREFIX)/share/stageforge
	@cp -r core runners prompts config templates $(PREFIX)/share/stageforge/
	@echo "Done! Run 'stageforge --help' to get started."

uninstall:
	@rm -f $(PREFIX)/bin/stageforge
	@rm -rf $(PREFIX)/share/stageforge
	@echo "Uninstalled."

test:
	@echo "Running shellcheck..."
	@if command -v shellcheck >/dev/null 2>&1; then \
	    shellcheck bin/stageforge core/*.sh runners/*.sh tests/*.sh; \
	else \
	    echo "shellcheck not installed — lint SKIPPED (not a pass)"; \
	fi
	@bash -n bin/stageforge && echo "bin/stageforge: syntax OK"
	@bash -n core/compat.sh && echo "core/compat.sh: syntax OK"
	@bash -n core/lock.sh && echo "core/lock.sh: syntax OK"
	@bash -n core/signal.sh && echo "core/signal.sh: syntax OK"
	@bash -n core/validate.sh && echo "core/validate.sh: syntax OK"
	@bash -n runners/claude-code.sh && echo "runners/claude-code.sh: syntax OK"
	@bash -n runners/codex-cli.sh && echo "runners/codex-cli.sh: syntax OK"
	@bash -n runners/gemini-cli.sh && echo "runners/gemini-cli.sh: syntax OK"
	@bash -n runners/mock.sh && echo "runners/mock.sh: syntax OK"
	@bash -n tests/test_reconcile.sh && echo "tests/test_reconcile.sh: syntax OK"
	@bash -n tests/test_lock.sh && echo "tests/test_lock.sh: syntax OK"
	@bash -n tests/test_config.sh && echo "tests/test_config.sh: syntax OK"
	@bash -n tests/test_rollback.sh && echo "tests/test_rollback.sh: syntax OK"
	@echo "Running unit tests..."
	@bash tests/test_reconcile.sh
	@bash tests/test_lock.sh
	@bash tests/test_config.sh
	@bash tests/test_rollback.sh

clean:
	@rm -rf stages/ .stage_* docs/PLAN.md docs/TEST_REPORT.md docs/README.md
	@echo "Cleaned stage artifacts."
