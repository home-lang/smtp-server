# Code Coverage Guide

**Version:** v0.28.0
**Date:** 2025-10-24

## Overview

This document describes how to measure, track, and enforce code coverage for the SMTP server project.

## Coverage Metrics

### Types of Coverage

1. **Line Coverage**: Percentage of code lines executed during tests
2. **Branch Coverage**: Percentage of conditional branches taken
3. **Function Coverage**: Percentage of functions called during tests

### Coverage Targets

| Metric | Minimum | Target | Notes |
|--------|---------|--------|-------|
| Line Coverage | 80% | 90%+ | Critical paths must be 100% |
| Branch Coverage | 70% | 85%+ | All error paths covered |
| Function Coverage | 90% | 95%+ | Public API must be 100% |

---

## Measuring Coverage with Zig

### Built-in Coverage Support

Zig provides built-in code coverage through LLVM instrumentation:

```bash
# Build with coverage instrumentation
zig build test -Dtest-coverage

# Run tests (generates coverage data)
zig build test

# Generate coverage report
zig coverage report
```

---

## Using LLVM Coverage Tools

### Generate Coverage Data

```bash
# Build with coverage instrumentation
zig test src/main.zig \
  -fprofile-instr-generate \
  -fcoverage-mapping \
  -O ReleaseSafe

# Run tests (creates default.profraw)
./test_binary

# Convert to indexed format
llvm-profdata merge -sparse default.profraw -o coverage.profdata

# Generate text report
llvm-cov report ./test_binary \
  -instr-profile=coverage.profdata \
  -show-functions

# Generate detailed report
llvm-cov show ./test_binary \
  -instr-profile=coverage.profdata \
  -format=html \
  -output-dir=coverage_html
```

### Example Commands

```bash
# Quick coverage check
zig test src/**/*.zig \
  -fprofile-instr-generate \
  -fcoverage-mapping && \
llvm-profdata merge -sparse default.profraw -o coverage.profdata && \
llvm-cov report ./zig-cache/o/*/test \
  -instr-profile=coverage.profdata

# Generate HTML report
llvm-cov show ./zig-cache/o/*/test \
  -instr-profile=coverage.profdata \
  -format=html \
  -output-dir=coverage_html \
  -show-line-counts \
  -show-region-counts
```

---

## Coverage Framework

### Using the Built-in Framework

```bash
# Run coverage analysis
zig test tests/coverage.zig

# Generate JSON report
zig run tests/coverage.zig -- --format json > coverage.json

# Generate HTML report
zig run tests/coverage.zig -- --format html --output coverage.html

# Generate LCOV format (for Codecov, Coveralls)
zig run tests/coverage.zig -- --format lcov > coverage.info
```

### Configuration

Create `.coverage.conf`:

```ini
[thresholds]
min_line_coverage = 80.0
min_branch_coverage = 70.0
min_function_coverage = 90.0

[exclude]
patterns = tests/*,build/*,zig-cache/*

[output]
format = html
file = coverage_report.html
```

---

## CI/CD Integration

### GitHub Actions

```yaml
name: Coverage

on:
  push:
    branches: [ main ]
  pull_request:

jobs:
  coverage:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.15.1

      - name: Install LLVM tools
        run: |
          sudo apt-get update
          sudo apt-get install -y llvm

      - name: Build with coverage
        run: |
          zig build test \
            -Dtest-coverage \
            -fprofile-instr-generate \
            -fcoverage-mapping

      - name: Run tests
        run: zig build test

      - name: Generate coverage data
        run: |
          llvm-profdata merge -sparse default.profraw -o coverage.profdata

      - name: Generate coverage report
        run: |
          llvm-cov report ./zig-cache/o/*/test \
            -instr-profile=coverage.profdata \
            > coverage_report.txt

      - name: Check coverage thresholds
        run: |
          COVERAGE=$(llvm-cov report ./zig-cache/o/*/test \
            -instr-profile=coverage.profdata | \
            grep TOTAL | awk '{print $NF}' | sed 's/%//')

          if (( $(echo "$COVERAGE < 80" | bc -l) )); then
            echo "Coverage $COVERAGE% is below minimum 80%"
            exit 1
          fi

          echo "Coverage: $COVERAGE%"

      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage.profdata
          fail_ci_if_error: true
```

---

## Codecov Integration

### Setup

```bash
# Install Codecov uploader
curl -Os https://uploader.codecov.io/latest/linux/codecov
chmod +x codecov

# Generate LCOV format
llvm-cov export ./test_binary \
  -instr-profile=coverage.profdata \
  -format=lcov > coverage.info

# Upload to Codecov
./codecov -f coverage.info -t $CODECOV_TOKEN
```

### codecov.yml Configuration

```yaml
coverage:
  status:
    project:
      default:
        target: 80%
        threshold: 1%
    patch:
      default:
        target: 80%

ignore:
  - "tests/**/*"
  - "build.zig"
  - "**/*.test.zig"

comment:
  layout: "reach, diff, flags, files"
  behavior: default
  require_changes: false
```

---

## Coveralls Integration

### Setup

```bash
# Generate LCOV format
llvm-cov export ./test_binary \
  -instr-profile=coverage.profdata \
  -format=lcov > coverage.info

# Install coveralls
npm install -g coveralls

# Upload to Coveralls
cat coverage.info | coveralls
```

### GitHub Actions Integration

```yaml
- name: Upload to Coveralls
  uses: coverallsapp/github-action@v2
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    path-to-lcov: ./coverage.info
```

---

## Coverage Reports

### Text Report

```
Filename                      Regions    Missed Regions     Cover   Functions  Missed Functions  Executed       Lines      Missed Lines     Cover
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
src/core/config.zig                127                 5    96.06%          24                 0   100.00%         285                12    95.79%
src/core/protocol.zig              213                15    92.96%          42                 1    97.62%         456                23    94.96%
src/auth/security.zig              145                 8    94.48%          18                 0   100.00%         312                 5    98.40%
---------------------------------------------------------------------------------------------------------------------------------------------------------------------
TOTAL                              485                28    94.23%          84                 1    98.81%        1053                40    96.20%
```

### HTML Report

Interactive HTML report showing:
- Line-by-line coverage highlighting
- Uncovered regions in red
- Branch coverage details
- Function coverage breakdown

Open `coverage_html/index.html` in browser.

---

## Best Practices

### 1. Write Tests First

Use TDD to ensure high coverage:

```zig
test "config validation - invalid port" {
    const testing = std.testing;

    var config = Config{
        .port = 100000, // Invalid
    };

    const result = config.validate();
    try testing.expectError(error.InvalidPort, result);
}
```

### 2. Cover Error Paths

Ensure all error paths are tested:

```zig
test "database connection failure" {
    const testing = std.testing;

    // Simulate connection failure
    const db_path = "/invalid/path/db.sqlite";
    const result = Database.open(db_path);

    try testing.expectError(error.DatabaseConnectionFailed, result);
}
```

### 3. Test Edge Cases

Don't just test happy paths:

```zig
test "email validation - edge cases" {
    const testing = std.testing;

    // Empty email
    try testing.expect(!validateEmail(""));

    // Just @
    try testing.expect(!validateEmail("@"));

    // Missing domain
    try testing.expect(!validateEmail("user@"));

    // Missing user
    try testing.expect(!validateEmail("@domain.com"));

    // Very long email
    const long_email = "a" ** 300 ++ "@example.com";
    try testing.expect(!validateEmail(long_email));
}
```

### 4. Mock External Dependencies

Use mocks for external services:

```zig
const MockSMTPClient = struct {
    sent_messages: std.ArrayList([]const u8),
    should_fail: bool = false,

    pub fn sendMessage(self: *MockSMTPClient, msg: []const u8) !void {
        if (self.should_fail) return error.SendFailed;
        try self.sent_messages.append(msg);
    }
};

test "retry logic on send failure" {
    var mock = MockSMTPClient{ .should_fail = true };

    const result = sendWithRetry(&mock, "test message", 3);
    try testing.expectError(error.MaxRetriesExceeded, result);
}
```

### 5. Exclude Test Files

Don't count test files in coverage:

```bash
llvm-cov report ./test_binary \
  -instr-profile=coverage.profdata \
  -ignore-filename-regex='.*\.test\.zig$' \
  -ignore-filename-regex='tests/.*'
```

---

## Improving Coverage

### Identify Uncovered Code

```bash
# Show uncovered lines
llvm-cov show ./test_binary \
  -instr-profile=coverage.profdata \
  -show-line-counts-or-regions \
  -show-instantiations=false \
  | grep -E '^\s+0\|'

# List uncovered functions
llvm-cov report ./test_binary \
  -instr-profile=coverage.profdata \
  -show-functions \
  | grep '0.00%'
```

### Prioritize Critical Code

Focus on:
1. Public API functions
2. Error handling paths
3. Security-critical code
4. Data validation logic
5. Business logic

### Example Coverage Improvement

**Before:**
```
src/auth/security.zig:
  Lines: 156/200 (78.00%)
  Branches: 35/50 (70.00%)
```

**Add Tests:**
```zig
test "rate limiter - concurrent access" { ... }
test "rate limiter - cleanup expired entries" { ... }
test "rate limiter - different clients" { ... }
```

**After:**
```
src/auth/security.zig:
  Lines: 195/200 (97.50%)
  Branches: 48/50 (96.00%)
```

---

## Coverage in Pull Requests

### Enforce Coverage Standards

```yaml
# .github/workflows/pr-coverage.yml
- name: Check coverage delta
  run: |
    # Get base branch coverage
    git checkout ${{ github.base_ref }}
    zig build test -Dtest-coverage
    BASE_COV=$(llvm-cov report ... | grep TOTAL | awk '{print $NF}')

    # Get PR coverage
    git checkout ${{ github.head_ref }}
    zig build test -Dtest-coverage
    PR_COV=$(llvm-cov report ... | grep TOTAL | awk '{print $NF}')

    # Fail if coverage decreased
    if (( $(echo "$PR_COV < $BASE_COV" | bc -l) )); then
      echo "Coverage decreased: $BASE_COV -> $PR_COV"
      exit 1
    fi
```

### Coverage Comments

Use GitHub Actions to post coverage comments on PRs:

```yaml
- name: Comment coverage
  uses: actions/github-script@v6
  with:
    script: |
      github.rest.issues.createComment({
        issue_number: context.issue.number,
        owner: context.repo.owner,
        repo: context.repo.repo,
        body: `## Coverage Report\n\nLine Coverage: ${coverage}%\nBranch Coverage: ${branchCoverage}%`
      })
```

---

## See Also

- [TESTING.md](TESTING.md) - Testing strategy and guidelines
- [LOAD_TESTING.md](LOAD_TESTING.md) - Load testing framework
- [FUZZING.md](FUZZING.md) - Fuzzing for security testing
- [CI_CD.md](CI_CD.md) - CI/CD pipeline setup

---

**Last Updated:** 2025-10-24
**Version:** v0.28.0
