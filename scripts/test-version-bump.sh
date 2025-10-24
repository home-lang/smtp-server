#!/usr/bin/env bash

# Test script for version bumping integration
# This script verifies that zig-bump is properly integrated

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Testing zig-bump integration...${NC}"
echo

# Test 1: Check if build.zig.zon exists
echo -n "1. Checking build.zig.zon exists... "
if [ -f "$PROJECT_ROOT/build.zig.zon" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    exit 1
fi

# Test 2: Check if bump dependency is in build.zig.zon
echo -n "2. Checking bump dependency in build.zig.zon... "
if grep -q "\.bump = \." "$PROJECT_ROOT/build.zig.zon"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    exit 1
fi

# Test 3: Check if zig-bump exists
echo -n "3. Checking zig-bump installation... "
if [ -f "$HOME/Code/zig-bump/zig-out/bin/bump" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "Run 'make install' to install zig-bump"
    exit 1
fi

# Test 4: Check if version.yml workflow exists
echo -n "4. Checking version management workflow... "
if [ -f "$PROJECT_ROOT/.github/workflows/version.yml" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    exit 1
fi

# Test 5: Check if release.yml workflow exists
echo -n "5. Checking release workflow... "
if [ -f "$PROJECT_ROOT/.github/workflows/release.yml" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    exit 1
fi

# Test 6: Check if bump-version.sh script exists and is executable
echo -n "6. Checking bump-version.sh script... "
if [ -x "$PROJECT_ROOT/scripts/bump-version.sh" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    exit 1
fi

# Test 7: Check if Makefile has version targets
echo -n "7. Checking Makefile version targets... "
if [ -f "$PROJECT_ROOT/Makefile" ] && \
   grep -q "bump-patch" "$PROJECT_ROOT/Makefile" && \
   grep -q "bump-minor" "$PROJECT_ROOT/Makefile" && \
   grep -q "bump-major" "$PROJECT_ROOT/Makefile"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    exit 1
fi

# Test 8: Read current version
echo -n "8. Reading current version... "
CURRENT_VERSION=$(grep -o '\.version = "[^"]*"' "$PROJECT_ROOT/build.zig.zon" | cut -d'"' -f2)
if [ -n "$CURRENT_VERSION" ]; then
    echo -e "${GREEN}✓ (v$CURRENT_VERSION)${NC}"
else
    echo -e "${RED}✗${NC}"
    exit 1
fi

# Test 9: Test dry-run mode (doesn't modify anything)
echo -n "9. Testing bump dry-run mode... "
cd "$PROJECT_ROOT"
if $HOME/Code/zig-bump/zig-out/bin/bump patch --dry-run >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    exit 1
fi

# Test 10: Check documentation exists
echo -n "10. Checking release documentation... "
if [ -f "$PROJECT_ROOT/docs/RELEASE_PROCESS.md" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    exit 1
fi

echo
echo -e "${GREEN}All tests passed!${NC}"
echo
echo "Integration summary:"
echo "  - Current version: v$CURRENT_VERSION"
echo "  - zig-bump location: ~/Code/zig-bump"
echo "  - Workflows: version.yml, release.yml"
echo "  - Scripts: scripts/bump-version.sh"
echo "  - Makefile targets: bump-patch, bump-minor, bump-major, bump-interactive"
echo "  - Documentation: docs/RELEASE_PROCESS.md"
echo
echo "To create a release:"
echo "  make release-patch   # Bug fixes"
echo "  make release-minor   # New features"
echo "  make release-major   # Breaking changes"
