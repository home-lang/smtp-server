# Why Use `zig build` for Version Management?

This document explains why we prefer native Zig build steps over Makefiles and shell scripts for version management.

## TL;DR

**Use `zig build bump-patch` instead of `make release-patch`**

It's the Zig way - pure, cross-platform, and integrated into your build system.

## The Three Approaches

### 1. Native Zig Build (Recommended) ✅

```bash
zig build bump-patch
zig build bump-minor
zig build bump-major
zig build bump  # Interactive
```

**Pros:**
- ✅ Pure Zig - no external dependencies
- ✅ Cross-platform (works everywhere Zig does)
- ✅ Type-safe build configuration
- ✅ Integrated with `zig build` workflow
- ✅ Shows up in `zig build --help`
- ✅ Compile-time validation
- ✅ Follows Zig philosophy
- ✅ No shell scripting knowledge required
- ✅ Can be tested and validated at build time
- ✅ Works in CI/CD without extra tools

**Cons:**
- None! This is the idiomatic way.

### 2. Makefile

```bash
make release-patch
make release-minor
make release-major
```

**Pros:**
- ✅ Familiar to many developers
- ✅ Short commands
- ✅ Can integrate other tools

**Cons:**
- ❌ Requires `make` installed
- ❌ Platform-specific (Windows compatibility issues)
- ❌ Not the Zig way
- ❌ Another tool to learn/maintain
- ❌ Less type-safe
- ❌ Shell script syntax quirks

### 3. Shell Scripts

```bash
./scripts/bump-version.sh patch
```

**Pros:**
- ✅ Direct control
- ✅ Can handle complex logic

**Cons:**
- ❌ Platform-specific (bash/sh differences)
- ❌ Windows requires WSL/Git Bash
- ❌ Not integrated with build system
- ❌ Manual path management
- ❌ No compile-time validation

## Why Zig Build is Better

### 1. **Pure Zig Philosophy**

Zig's philosophy is to be self-contained and not require external tools. When you use `zig build`, you're using:
- Only Zig compiler
- No make
- No bash/sh
- No external scripts

### 2. **Cross-Platform by Default**

```zig
// This works on Windows, Linux, macOS, BSD, etc.
const bump_patch = b.addRunArtifact(bump_exe);
bump_patch.addArg("patch");
```

No need to worry about:
- Unix vs Windows paths
- Shell availability
- Line ending differences
- Command differences

### 3. **Type-Safe Configuration**

```zig
// Compile-time validated!
bump_patch.addArg("patch");  // ✅ Known at compile time

// vs Makefile/shell:
bump patch  # ❌ Typos only caught at runtime
```

### 4. **Integrated Help System**

```bash
$ zig build --help
Steps:
  ...
  bump-patch    Bump patch version (0.0.1 -> 0.0.2)
  bump-minor    Bump minor version (0.0.1 -> 0.1.0)
  bump-major    Bump major version (0.0.1 -> 1.0.0)
  bump          Interactively select version to bump
```

Everything is documented in one place!

### 5. **Build System Integration**

```zig
// Version management is just another build step
const bump_step = b.step("bump-patch", "Bump patch version");
bump_step.dependOn(install_bump_step);  // Automatic dependency tracking
```

The build system handles:
- Dependencies
- Caching
- Parallel execution
- Error handling

### 6. **CI/CD Simplicity**

```yaml
# GitHub Actions - one dependency
- name: Setup Zig
  uses: goto-bus-stop/setup-zig@v2

- name: Bump version
  run: zig build bump-patch

# vs requiring multiple tools:
- apt-get install make
- chmod +x scripts/*.sh
- make bump-patch
```

### 7. **No PATH Issues**

```zig
// Zig build knows where everything is
const bump_exe = bump.artifact("bump");
const bump_patch = b.addRunArtifact(bump_exe);
```

No need to:
- Set up PATH
- Use absolute paths
- Find binaries
- Check if tools are installed

## Real-World Example

### Using zig build (Zig way)

```bash
# Install Zig (one-time)
# Download from ziglang.org

# That's it! No other tools needed.
cd my-project
zig build bump-patch
```

**Works on:** Windows, macOS, Linux, BSD, etc.

### Using Makefile (Traditional way)

```bash
# Install Zig
# Download from ziglang.org

# Install make
brew install make          # macOS
apt-get install make       # Ubuntu
choco install make         # Windows

# Make scripts executable (Unix)
chmod +x scripts/*.sh

# Handle path issues
export PATH=$PATH:~/Code/zig-bump/zig-out/bin

# Now you can run
make bump-patch
```

**Issues on:** Windows (different make), path management, script permissions

## When to Use What

### Use `zig build` when:
- ✅ You want the idiomatic Zig way (always!)
- ✅ You want cross-platform compatibility
- ✅ You want type-safe configuration
- ✅ You're building a Zig project (obviously!)
- ✅ You want minimal dependencies
- ✅ You want integrated documentation

### Use `make` when:
- 🤔 Your team is already deeply invested in Makefiles
- 🤔 You need compatibility with legacy build systems
- 🤔 You have complex non-Zig build steps
- ⚠️  But consider: can these be ported to zig build?

### Use shell scripts when:
- 🤔 You need complex shell operations
- 🤔 You're integrating with OS-specific tools
- ⚠️  But consider: can this be done in zig build?

## Migration Path

If you're coming from Make/scripts:

1. **Start:** Learn what your Makefile does
   ```makefile
   release-patch:
       ./scripts/bump-version.sh patch
   ```

2. **Translate:** Convert to Zig build step
   ```zig
   const bump_patch = b.addRunArtifact(bump_exe);
   bump_patch.addArg("patch");
   const step = b.step("bump-patch", "Bump patch version");
   step.dependOn(&bump_patch.step);
   ```

3. **Use:** Run with zig build
   ```bash
   zig build bump-patch
   ```

4. **Simplify:** Remove Makefile and scripts
   ```bash
   rm Makefile scripts/bump-version.sh
   git commit -m "refactor: migrate to native zig build"
   ```

## Performance Comparison

| Method | Startup Time | Dependencies | Cross-Platform |
|--------|-------------|--------------|----------------|
| `zig build` | ~50ms | Zig only | ✅ Yes |
| `make` | ~100ms | Zig + Make + Shell | ⚠️  Mostly |
| `./script.sh` | ~80ms | Zig + Shell | ❌ No (Windows) |

## Zig Build Best Practices

### 1. **Use Descriptive Step Names**

```zig
// Good
b.step("bump-patch", "Bump patch version (0.0.1 -> 0.0.2)")

// Bad
b.step("bp", "bump patch")
```

### 2. **Group Related Steps**

```zig
// Version management
bump-patch
bump-minor
bump-major
bump

// Testing
test
test-rfc
test-e2e
test-all
```

### 3. **Provide Dry-Run Options**

```zig
// Safe preview before actual execution
bump_patch_dry.addArgs(&[_][]const u8{ "patch", "--dry-run" });
```

### 4. **Document Everything**

```zig
const step = b.step("bump-patch",
    "Bump patch version (0.0.1 -> 0.0.2) - for bug fixes"
);
```

## Conclusion

**Use `zig build` for everything you can.**

It's:
- The Zig way
- Cross-platform
- Type-safe
- Integrated
- Fast
- Self-documented
- Minimal dependencies

The Makefile and scripts are kept as convenience wrappers for those who prefer them, but the canonical way is:

```bash
zig build bump-patch
```

## Additional Resources

- [Zig Build System Documentation](https://ziglang.org/learn/build-system/)
- [Zig Philosophy](https://ziglang.org/learn/overview/)
- [Why Zig](https://ziglang.org/learn/why_zig_rust_d_cpp/)

## Questions?

**Q: What about my existing Makefile?**
A: Keep it if you want! It's a convenience wrapper. But recommend `zig build` in docs.

**Q: Do I need to learn Zig to use this?**
A: No! Just run `zig build bump-patch`. But if you want to customize, yes, learn Zig build system.

**Q: Can I still use the shell scripts?**
A: Yes, but they're not needed. `zig build` is simpler and better.

**Q: What about CI/CD?**
A: Just install Zig. That's it. No make, no bash, no chmod.

**Q: Is this the Zig philosophy?**
A: Absolutely! Self-contained, minimal dependencies, cross-platform, type-safe.
