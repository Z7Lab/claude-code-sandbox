.PHONY: build rebuild clean check-update update help

# Resolve the image tag from images.conf (same logic as run-claude-sandboxed.sh)
IMAGES_CONF := $(wildcard images.conf)
ifeq ($(IMAGES_CONF),)
  IMAGES_CONF := $(wildcard images.conf.example)
endif

ifneq ($(IMAGES_CONF),)
  IMAGE_NAME ?= $(shell grep -E '^default=' $(IMAGES_CONF) | head -1 | cut -d= -f2 | xargs)
  BASE_IMAGE ?= $(shell grep -E '^$(IMAGE_NAME)=' $(IMAGES_CONF) | head -1 | cut -d= -f2 | xargs)
endif

IMAGE_NAME ?= bookworm
IMAGE_TAG  := claude-code-sandbox:$(IMAGE_NAME)

build:
	docker build --build-arg "BASE_IMAGE=$(BASE_IMAGE)" -t $(IMAGE_TAG) .
	@echo ""
	@echo "✅ Docker image built successfully! ($(IMAGE_TAG))"
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
	docker build --no-cache --build-arg "BASE_IMAGE=$(BASE_IMAGE)" -t $(IMAGE_TAG) .

check-update:
	@echo "Checking Claude Code versions..."
	@echo ""
	@INSTALLED=$$(docker run --rm --entrypoint "" -e HOME=/home/claude $(IMAGE_TAG) claude --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); \
	RELEASES_URL=$$(curl -sI -o /dev/null -w "%{redirect_url}" https://claude.ai/install.sh 2>/dev/null | sed 's|/bootstrap\.sh$$||'); \
	LATEST=$$(curl -s --max-time 5 "$$RELEASES_URL/latest" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); \
	if [ -z "$$INSTALLED" ]; then \
		echo "❌ Could not determine installed version"; \
		echo "   Docker image may not be built yet. Run: make build"; \
	elif [ -z "$$LATEST" ]; then \
		echo "❌ Could not fetch latest version"; \
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
	@echo "This will rebuild the Docker image with --no-cache ($(IMAGE_TAG))"
	@echo ""
	@read -p "Continue? [Y/n]: " -n 1 -r; \
	echo ""; \
	if [ -z "$$REPLY" ] || echo "$$REPLY" | grep -iq "^y"; then \
		docker build --no-cache --build-arg "BASE_IMAGE=$(BASE_IMAGE)" -t $(IMAGE_TAG) .; \
		echo ""; \
		echo "✅ Update complete!"; \
	else \
		echo "Update cancelled."; \
	fi

clean:
	docker rmi $(IMAGE_TAG) 2>/dev/null || true
	docker system prune -f

help:
	@echo "Available commands:"
	@echo "  make build        - Build the Docker image (uses cache)"
	@echo "  make rebuild      - Rebuild with --no-cache (gets actual latest Claude Code)"
	@echo "  make check-update - Check if a newer Claude Code version is available"
	@echo "  make update       - Update to latest Claude Code version (rebuilds image)"
	@echo "  make clean        - Remove image and cleanup"
	@echo ""
	@echo "Current image: $(IMAGE_TAG) (base: $(BASE_IMAGE))"
	@echo "To build a different image: make build IMAGE_NAME=python3.13"
