# Makefile for SMTP Server Project

.PHONY: help build run test clean bump-patch bump-minor bump-major bump-interactive install

# Default target
help:
	@echo "SMTP Server - Available Commands"
	@echo ""
	@echo "Build & Run:"
	@echo "  make build          - Build the SMTP server"
	@echo "  make run            - Run the SMTP server"
	@echo "  make test           - Run all tests"
	@echo "  make clean          - Clean build artifacts"
	@echo ""
	@echo "Version Management:"
	@echo "  make release        - 🎯 Interactive release (recommended)"
	@echo "  make bump-patch     - Bump patch version (0.0.1 -> 0.0.2)"
	@echo "  make bump-minor     - Bump minor version (0.0.1 -> 0.1.0)"
	@echo "  make bump-major     - Bump major version (0.0.1 -> 1.0.0)"
	@echo "  make bump-interactive - Interactive version selection"
	@echo ""
	@echo "Release:"
	@echo "  make release-patch  - Bump patch and trigger release"
	@echo "  make release-minor  - Bump minor and trigger release"
	@echo "  make release-major  - Bump major and trigger release"
	@echo ""
	@echo "Installation:"
	@echo "  make install        - Install zig-bump tool"

# Build targets
build:
	zig build -Doptimize=ReleaseFast

build-debug:
	zig build

# Run targets
run:
	zig build run

# Test targets
test:
	zig build test

test-all:
	zig build test-all

test-rfc:
	zig build test-rfc

test-e2e:
	zig build test-e2e

# Clean target
clean:
	rm -rf zig-cache zig-out .zig-cache

# Version bumping targets
bump-patch:
	@./scripts/bump-version.sh patch

bump-minor:
	@./scripts/bump-version.sh minor

bump-major:
	@./scripts/bump-version.sh major

bump-interactive:
	@./scripts/bump-version.sh

# Interactive release (recommended)
release:
	@./scripts/release.sh

# Release targets (bump version and push tags to trigger release workflow)
release-patch: bump-patch
	@echo "Patch release triggered! Check GitHub Actions for release progress."

release-minor: bump-minor
	@echo "Minor release triggered! Check GitHub Actions for release progress."

release-major: bump-major
	@echo "Major release triggered! Check GitHub Actions for release progress."

# Install zig-bump
install:
	@echo "Installing zig-bump..."
	@if [ ! -d "$(HOME)/Code/zig-bump" ]; then \
		cd $(HOME)/Code && git clone https://github.com/stacksjs/zig-bump.git; \
	fi
	@cd $(HOME)/Code/zig-bump && zig build -Doptimize=ReleaseFast
	@echo "zig-bump installed successfully!"
	@echo "You can now use 'make bump-patch', 'make bump-minor', or 'make bump-major'"

# Development targets
dev: build run

fmt:
	zig fmt src/

fmt-check:
	zig fmt --check src/

# Docker targets
docker-build:
	docker build -t smtp-server:latest .

docker-run:
	docker run -p 2525:2525 -p 2465:2465 smtp-server:latest

# Cross-compilation
cross:
	zig build -Dall-targets=true -Doptimize=ReleaseFast
