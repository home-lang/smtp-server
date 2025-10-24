# Quick Release Guide

Three ways to release - choose your preferred method!

## 🎯 Option 1: Interactive Script (Easiest!)

**Best for:** First-time releases, manual releases, guided experience

```bash
./scripts/release.sh
```

Or with Make:
```bash
make release
```

**What you get:**
- ✅ Pre-release checklist (reminds you about CHANGELOG, tests)
- 🎨 Beautiful colored interface
- 📊 Visual version preview with descriptions
- 🔍 Built-in dry-run option
- ✋ Confirmation before making changes
- 🎯 Clear next steps after release
- 📝 Option to edit CHANGELOG on the spot

**Example flow:**
1. Run `./scripts/release.sh`
2. Answer checklist questions
3. Select version type (patch/minor/major)
4. Preview the changes
5. Confirm
6. Done! 🎉

**Screenshot:**
```
╔═══════════════════════════════════════════════════════╗
║         SMTP Server Release Manager                  ║
╚═══════════════════════════════════════════════════════╝

[INFO] Current version: v0.0.0

  1) Patch  v0.0.0 → v0.0.1
     └─ Bug fixes, security patches, minor updates

  2) Minor  v0.0.0 → v0.1.0
     └─ New features, backwards compatible changes

  3) Major  v0.0.0 → v1.0.0
     └─ Breaking changes, major refactors

  4) Dry Run - Preview changes without applying
```

---

## 🦎 Option 2: Native Zig Build (Most Idiomatic)

**Best for:** CI/CD, automation, cross-platform, Zig purists

```bash
# Direct release
zig build bump-patch    # Bug fixes
zig build bump-minor    # New features
zig build bump-major    # Breaking changes

# Interactive (but without the fancy UI)
zig build bump

# Dry-run (preview only)
zig build bump-patch-dry
zig build bump-minor-dry
zig build bump-major-dry
```

**Why this is great:**
- ✅ Pure Zig - no external dependencies
- ✅ Cross-platform (Windows, Linux, macOS, BSD)
- ✅ Type-safe build configuration
- ✅ Integrated with `zig build` workflow
- ✅ Shows up in `zig build --help`
- ✅ Perfect for CI/CD

**Example:**
```bash
# Preview what would happen
zig build bump-patch-dry

# Output:
# [DRY RUN] Would bump version from 0.0.0 to 0.0.1
# [DRY RUN] Would create git commit
# [DRY RUN] Would create git tag: v0.0.1
# [DRY RUN] Would push to remote

# Actually do it
zig build bump-patch
```

---

## 📦 Option 3: Makefile Shortcuts (Traditional)

**Best for:** Make users, existing workflows, muscle memory

```bash
make release-patch    # Bug fixes
make release-minor    # New features
make release-major    # Breaking changes
```

**Quick reference:**
```bash
make release         # Interactive release script
make release-patch   # Same as: zig build bump-patch
make release-minor   # Same as: zig build bump-minor
make release-major   # Same as: zig build bump-major
```

---

## Comparison Table

| Feature | Interactive Script | Zig Build | Makefile |
|---------|-------------------|-----------|----------|
| Guided experience | ✅ Yes | ❌ No | ❌ No |
| Pre-release checks | ✅ Yes | ❌ No | ❌ No |
| Visual preview | ✅ Yes | ⚠️ Basic | ⚠️ Basic |
| Cross-platform | ⚠️ Bash required | ✅ Yes | ⚠️ Make required |
| CI/CD friendly | ⚠️ Needs interaction | ✅ Yes | ✅ Yes |
| Dry-run | ✅ Built-in | ✅ Separate command | ❌ No |
| Zig-native | ❌ No | ✅ Yes | ❌ No |
| Easy to use | ✅✅✅ | ✅✅ | ✅✅ |

---

## Recommended Workflow

### For Manual Releases (Recommended)

```bash
# 1. Update CHANGELOG.md
vim CHANGELOG.md

# 2. Commit changes
git add CHANGELOG.md
git commit -m "docs: update changelog for v0.0.1"

# 3. Run interactive release
./scripts/release.sh

# 4. Follow the prompts
# 5. Monitor GitHub Actions
```

### For Automated Releases (CI/CD)

```yaml
# .github/workflows/release.yml
- name: Setup Zig
  uses: goto-bus-stop/setup-zig@v2

- name: Bump patch version
  run: zig build bump-patch
```

### Quick One-Liner

If you just want to release NOW:

```bash
# Interactive (asks questions)
./scripts/release.sh

# Direct (no questions)
zig build bump-patch  # or bump-minor, bump-major
```

---

## When to Use Each Method

### Use Interactive Script (`./scripts/release.sh`) when:
- ✅ You're doing a manual release
- ✅ You want to be reminded about CHANGELOG and tests
- ✅ You want a nice visual experience
- ✅ You're not sure which version to bump
- ✅ You want confirmation before releasing

### Use Zig Build (`zig build bump-patch`) when:
- ✅ You're in CI/CD
- ✅ You know exactly which version to bump
- ✅ You want the fastest method
- ✅ You prefer command-line terseness
- ✅ You're on Windows or another platform
- ✅ You want the pure Zig way

### Use Makefile (`make release-patch`) when:
- ✅ You're used to Make
- ✅ You want short commands
- ✅ Your workflow already uses Make
- ✅ You have make installed

---

## Complete Example: Releasing a Bug Fix

### Using Interactive Script
```bash
# Fix a bug
git add src/bug-fix.zig
git commit -m "fix: resolve memory leak in connection handler"

# Update changelog
echo "### Fixed\n- Memory leak in connection handler" >> CHANGELOG.md
git add CHANGELOG.md
git commit -m "docs: update changelog"

# Release interactively
./scripts/release.sh
# Select option 1 (Patch)
# Confirm
# Done! 🎉
```

### Using Zig Build
```bash
# Fix a bug
git add src/bug-fix.zig
git commit -m "fix: resolve memory leak in connection handler"

# Update changelog
echo "### Fixed\n- Memory leak in connection handler" >> CHANGELOG.md
git add CHANGELOG.md
git commit -m "docs: update changelog"

# Preview the release
zig build bump-patch-dry

# Actually release
zig build bump-patch
```

### Using Makefile
```bash
# Fix a bug
git add src/bug-fix.zig
git commit -m "fix: resolve memory leak in connection handler"

# Update changelog
echo "### Fixed\n- Memory leak in connection handler" >> CHANGELOG.md
git add CHANGELOG.md
git commit -m "docs: update changelog"

# Release
make release-patch
```

All three methods do the same thing - choose what feels best!

---

## Tips & Tricks

### Tip 1: Always Dry-Run First
```bash
# Interactive script has dry-run built-in (option 4)
./scripts/release.sh

# Or use zig build
zig build bump-patch-dry
```

### Tip 2: Alias for Speed
Add to your `~/.bashrc` or `~/.zshrc`:
```bash
alias release='./scripts/release.sh'
alias bump-patch='zig build bump-patch'
alias bump-minor='zig build bump-minor'
alias bump-major='zig build bump-major'
```

Then just run:
```bash
release        # Interactive
bump-patch     # Direct
```

### Tip 3: Pre-Commit Hook
Create `.git/hooks/pre-commit`:
```bash
#!/bin/bash
# Remind about version bumping on main branch
if [ "$(git branch --show-current)" = "main" ]; then
    echo "Reminder: Did you bump the version?"
    echo "Run: ./scripts/release.sh"
fi
```

### Tip 4: Check What Changed
Before releasing, see what's new:
```bash
git log $(git describe --tags --abbrev=0)..HEAD --oneline
```

---

## Troubleshooting

### "Command not found: zig"
Install Zig from https://ziglang.org/download/

### "Permission denied: ./scripts/release.sh"
Make it executable:
```bash
chmod +x scripts/release.sh
```

### "No such file: bump"
Build it first:
```bash
zig build install-bump
```

### "Uncommitted changes"
Commit or stash your changes:
```bash
git stash
./scripts/release.sh
git stash pop
```

---

## Summary

**TL;DR:**

- **Easiest:** `./scripts/release.sh` - Interactive, guided, beautiful
- **Fastest:** `zig build bump-patch` - Direct, no questions
- **Traditional:** `make release-patch` - Short commands

All three do the same thing. Pick your favorite! 🎯

For more details, see [RELEASE_PROCESS.md](RELEASE_PROCESS.md).
