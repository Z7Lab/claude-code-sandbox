.PHONY: build rebuild clean check-update update help

build:
	docker build -t claude-code-sandbox .
	@echo ""
	@echo "✅ Docker image built successfully!"
	@echo ""
	@echo "ℹ️  What you just saw:"
	@echo "   Those RUN commands (apt-get, chmod 777) happen INSIDE the Docker image,"
	@echo "   not on your system. See SECURITY.md for details on container isolation."
	@echo ""
	@echo "Next steps:"
	@echo "  1. Go to any project:  cd ~/myproject"
	@echo "  2. Run Claude Code:    $(CURDIR)/run-claude-sandboxed.sh"
	@echo ""
	@echo "Or add to PATH to run from anywhere - see README.md"
	@echo ""

rebuild:
	docker build --no-cache -t claude-code-sandbox .

check-update:
	@echo "Checking Claude Code versions..."
	@echo ""
	@INSTALLED=$$(docker run --rm --entrypoint sh claude-code-sandbox -c "claude --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1" 2>/dev/null); \
	LATEST=$$(npm view @anthropic-ai/claude-code version 2>/dev/null); \
	if [ -z "$$INSTALLED" ]; then \
		echo "❌ Could not determine installed version"; \
		echo "   Docker image may not be built yet. Run: make build"; \
	elif [ -z "$$LATEST" ]; then \
		echo "❌ Could not fetch latest version from npm"; \
		echo "   Check your internet connection"; \
	else \
		echo "   Installed version: $$INSTALLED"; \
		echo "   Latest version:    $$LATEST"; \
		echo ""; \
		if [ "$$INSTALLED" = "$$LATEST" ]; then \
			echo "✅ You are running the latest version!"; \
		else \
			echo "📦 Update available!"; \
			echo ""; \
			echo "To update, run: make update"; \
		fi; \
	fi

update:
	@echo "Updating Claude Code to latest version..."
	@echo "This will rebuild the Docker image with --no-cache"
	@echo ""
	@read -p "Continue? [Y/n]: " -n 1 -r; \
	echo ""; \
	if [ -z "$$REPLY" ] || echo "$$REPLY" | grep -iq "^y"; then \
		docker build --no-cache -t claude-code-sandbox .; \
		echo ""; \
		echo "✅ Update complete!"; \
	else \
		echo "Update cancelled."; \
	fi

clean:
	docker rmi claude-code-sandbox 2>/dev/null || true
	docker system prune -f

help:
	@echo "Available commands:"
	@echo "  make build        - Build the Docker image (uses cache)"
	@echo "  make rebuild      - Rebuild with --no-cache (gets actual latest Claude Code)"
	@echo "  make check-update - Check if a newer Claude Code version is available"
	@echo "  make update       - Update to latest Claude Code version (rebuilds image)"
	@echo "  make clean        - Remove image and cleanup"
