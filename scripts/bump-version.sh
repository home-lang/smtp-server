#!/usr/bin/env bash

# Version bumping script for the SMTP server project
# Uses zig-bump to manage version numbers in build.zig.zon

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ZIG_BUMP_DIR="$HOME/Code/zig-bump"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if zig-bump exists
if [ ! -d "$ZIG_BUMP_DIR" ]; then
    print_error "zig-bump not found at $ZIG_BUMP_DIR"
    print_info "Attempting to clone zig-bump..."

    cd "$(dirname "$ZIG_BUMP_DIR")"
    git clone https://github.com/stacksjs/zig-bump.git
    cd zig-bump

    print_info "Building zig-bump..."
    zig build -Doptimize=ReleaseFast
else
    print_info "Found zig-bump at $ZIG_BUMP_DIR"
fi

# Ensure bump binary is available
BUMP_BIN="$ZIG_BUMP_DIR/zig-out/bin/bump"
if [ ! -f "$BUMP_BIN" ]; then
    print_info "Building zig-bump..."
    cd "$ZIG_BUMP_DIR"
    zig build -Doptimize=ReleaseFast
fi

# Change to project root
cd "$PROJECT_ROOT"

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    print_error "Not in a git repository!"
    exit 1
fi

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    print_warn "You have uncommitted changes. Commit or stash them before bumping version."
    git status --short
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Run bump command with provided arguments
print_info "Running zig-bump..."
echo

if [ $# -eq 0 ]; then
    # Interactive mode
    "$BUMP_BIN"
else
    # Command line mode
    "$BUMP_BIN" "$@"
fi

echo
print_info "Version bump completed!"
print_info "The version tag will trigger the release workflow on GitHub."
