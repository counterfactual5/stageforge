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
	@shellcheck bin/stageforge core/*.sh runners/*.sh 2>/dev/null || echo "shellcheck not installed, skipping"
	@bash -n bin/stageforge && echo "bin/stageforge: syntax OK"
	@bash -n core/pipeline.sh && echo "core/pipeline.sh: syntax OK"
	@bash -n core/signal.sh && echo "core/signal.sh: syntax OK"
	@bash -n core/validate.sh && echo "core/validate.sh: syntax OK"
	@bash -n runners/claude-code.sh && echo "runners/claude-code.sh: syntax OK"
	@bash -n runners/codex-cli.sh && echo "runners/codex-cli.sh: syntax OK"

clean:
	@rm -rf stages/ .stage_* docs/PLAN.md docs/TEST_REPORT.md docs/README.md
	@echo "Cleaned stage artifacts."
