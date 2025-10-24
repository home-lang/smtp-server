# Code Organization

This document describes the organization of the SMTP server codebase after the v0.24.0 refactoring.

## Overview

The codebase has been reorganized from a flat 70-file structure into a logical directory hierarchy that groups related functionality together. This improves:

- **Discoverability**: Easier to find related code
- **Maintainability**: Clear boundaries between modules
- **Scalability**: Room to grow within each category
- **Onboarding**: New developers can understand the structure quickly

## Directory Structure

```
src/
├── main.zig                    # Server entry point
├── root.zig                    # Library exports
├── *_cli.zig                   # CLI tool entry points (3 files)
├── *_test.zig                  # Unit tests (3 files)
│
├── core/                       # Core SMTP infrastructure (7 files)
│   ├── protocol.zig           # Main SMTP protocol handler
│   ├── smtp.zig               # SMTP server implementation
│   ├── config.zig             # Configuration system
│   ├── args.zig               # Command-line argument parsing
│   ├── errors.zig             # Error types and handling
│   ├── logger.zig             # Logging system
│   └── tls.zig                # TLS wrapper for zig-tls
│
├── protocol/                   # SMTP Protocol Extensions (9 files)
│   ├── pipelining.zig         # PIPELINING (RFC 2920)
│   ├── chunking.zig           # CHUNKING (RFC 3030)
│   ├── binarymime.zig         # BINARYMIME (RFC 3030)
│   ├── deliverby.zig          # DELIVERBY (RFC 2852)
│   ├── dsn.zig                # Delivery Status Notifications (RFC 3461)
│   ├── etrn.zig               # ETRN (RFC 1985)
│   ├── atrn.zig               # ATRN (RFC 2645)
│   ├── utf8.zig               # SMTPUTF8 (RFC 6531)
│   └── message_submission.zig # Message Submission Agent (RFC 6409)
│
├── auth/                       # Authentication & Authorization (3 files)
│   ├── auth.zig               # Authentication framework
│   ├── password.zig           # Password hashing (Argon2id)
│   └── security.zig           # Rate limiting & security checks
│
├── antispam/                   # Anti-Spam & Security Checks (8 files)
│   ├── dnsbl.zig              # DNSBL/RBL checking
│   ├── greylist.zig           # Greylisting (triplet-based)
│   ├── spf.zig                # SPF validation (RFC 7208)
│   ├── dkim.zig               # DKIM validation (RFC 6376)
│   ├── dmarc.zig              # DMARC checking (RFC 7489)
│   ├── clamav.zig             # ClamAV virus scanning
│   ├── spamassassin.zig       # SpamAssassin integration
│   └── can_spam.zig           # CAN-SPAM compliance
│
├── message/                    # Message Processing (5 files)
│   ├── headers.zig            # Header parsing (RFC 5322)
│   ├── mime.zig               # MIME multipart parsing
│   ├── attachment.zig         # Attachment handling
│   ├── html.zig               # HTML email support
│   └── filter.zig             # Message filtering rules
│
├── storage/                    # Storage Backends (8 files)
│   ├── database.zig           # SQLite database
│   ├── postgres.zig           # PostgreSQL backend
│   ├── dbstorage.zig          # Database message storage
│   ├── mbox.zig               # mbox format (RFC 4155)
│   ├── timeseries_storage.zig # Time-series filesystem storage
│   ├── s3storage.zig          # S3 object storage
│   ├── encryption.zig         # Encrypted storage (AES-256-GCM)
│   └── backup.zig             # Backup and restore utilities
│
├── delivery/                   # Message Delivery (3 files)
│   ├── queue.zig              # Message queue management
│   ├── relay.zig              # SMTP relay client
│   └── bounce.zig             # Bounce message handling
│
├── features/                   # Advanced Features (6 files)
│   ├── mailinglist.zig        # Mailing list management
│   ├── autoresponder.zig      # Auto-responder/Out-of-Office
│   ├── quota.zig              # Storage quota management
│   ├── attachment_limits.zig  # Attachment size limits
│   ├── gdpr.zig               # GDPR compliance features
│   └── webhook.zig            # Webhook notifications
│
├── api/                        # APIs and Interfaces (3 files)
│   ├── api.zig                # REST API server
│   ├── search.zig             # Full-text search API (FTS5)
│   └── health.zig             # Health check endpoint
│
├── observability/              # Monitoring & Observability (2 files)
│   ├── statsd.zig             # StatsD metrics exporter
│   └── tracing.zig            # OpenTelemetry tracing (W3C)
│
├── infrastructure/             # Low-Level Infrastructure (6 files)
│   ├── pool.zig               # Generic resource pooling
│   ├── mempool.zig            # Memory pool allocators
│   ├── zerocopy.zig           # Zero-copy buffer management
│   ├── io_uring.zig           # Async I/O framework (Linux)
│   ├── unix_socket.zig        # Unix domain sockets
│   └── platform.zig           # Platform abstraction layer
│
└── testing/                    # Testing Utilities (2 files)
    ├── benchmark.zig          # Benchmarking suite
    └── loadtest.zig           # Load testing tools
```

## File Count Summary

- **Total Files**: 70
- **Entry Points** (src root): 7 (main, root, 3 CLIs, 3 tests)
- **Core**: 7 files
- **Protocol Extensions**: 9 files
- **Authentication**: 3 files
- **Anti-Spam**: 8 files
- **Message Processing**: 5 files
- **Storage**: 8 files
- **Delivery**: 3 files
- **Features**: 6 files
- **API**: 3 files
- **Observability**: 2 files
- **Infrastructure**: 6 files
- **Testing**: 2 files

## Import Conventions

### Root-Level Files
Files in the `src` root (main.zig, CLIs, tests) import from subdirectories using relative paths:
```zig
const config = @import("core/config.zig");
const database = @import("storage/database.zig");
```

### Files Within the Same Directory
Files in the same directory import each other without directory prefixes:
```zig
// In src/core/smtp.zig
const logger = @import("logger.zig");
const protocol = @import("protocol.zig");
```

### Cross-Directory Imports
Files in subdirectories import from other subdirectories using relative paths with `../`:
```zig
// In src/protocol/chunking.zig
const errors = @import("../core/errors.zig");
const logger = @import("../core/logger.zig");
```

## Design Principles

### 1. **Separation of Concerns**
Each directory has a single, well-defined responsibility:
- `core`: Essential SMTP server functionality
- `protocol`: SMTP protocol extensions
- `storage`: Data persistence strategies
- `message`: Email message processing

### 2. **Dependency Flow**
Dependencies generally flow inward and downward:
- Higher-level features depend on core infrastructure
- Protocol extensions depend on core SMTP implementation
- Specific implementations depend on abstract interfaces

### 3. **Entry Points at Root**
Files that serve as entry points (main.zig, CLI tools, test files) remain in the src root because:
- They are root modules in Zig's build system
- They cannot use `../` imports due to module path restrictions
- They provide clear entry points for the build system

## Migration Guide

If you're updating code that references the old flat structure:

### Old Import Style (Pre-v0.24.0)
```zig
const config = @import("config.zig");
const database = @import("database.zig");
const spf = @import("spf.zig");
```

### New Import Style (v0.24.0+)

**From src root files:**
```zig
const config = @import("core/config.zig");
const database = @import("storage/database.zig");
const spf = @import("antispam/spf.zig");
```

**From subdirectory files:**
```zig
const config = @import("../core/config.zig");
const database = @import("../storage/database.zig");
const spf = @import("../antispam/spf.zig");
```

**From files in the same directory:**
```zig
const config = @import("config.zig");  // If both in core/
const database = @import("database.zig");  // If both in storage/
```

## Finding Files

To quickly locate a file:

1. **Core functionality**: Look in `core/`
2. **SMTP extensions**: Look in `protocol/`
3. **Security/Anti-spam**: Look in `auth/` or `antispam/`
4. **Data storage**: Look in `storage/`
5. **Email processing**: Look in `message/`
6. **Queuing/delivery**: Look in `delivery/`
7. **Advanced features**: Look in `features/`
8. **REST API**: Look in `api/`
9. **Metrics/tracing**: Look in `observability/`
10. **Low-level utils**: Look in `infrastructure/`

## Scripts

The `scripts/` directory contains helper scripts for managing imports:

- `update-imports.sh`: Update all @import() statements to new paths
- `fix-relative-imports.sh`: Fix imports within the same directory
- `fix-cross-directory-imports.sh`: Fix cross-directory imports with ../

These scripts were used during the v0.24.0 reorganization and are preserved for reference.

## Version History

- **v0.24.0 (2025-10-24)**: Major code reorganization into logical directory structure
- **v0.23.0 and earlier**: Flat file structure with all files in src root

## Benefits

### Before (Flat Structure)
- 70 files in a single directory
- Difficult to navigate
- No clear module boundaries
- Hard to understand relationships

### After (Organized Structure)
- ✅ Logical grouping by functionality
- ✅ Clear module boundaries
- ✅ Easy to find related code
- ✅ Scalable for future growth
- ✅ Better IDE support
- ✅ Clearer dependencies

## Contributing

When adding new files:
1. Identify the appropriate directory based on the file's primary purpose
2. Use the correct import style for the file's location
3. Update this document if you create a new top-level directory
4. Maintain alphabetical order within directories when practical

## Questions?

- Where does logging code go? → `core/logger.zig`
- Where do I add a new SMTP extension? → Create a new file in `protocol/`
- Where do I add a new storage backend? → Create a new file in `storage/`
- Where do I add spam filtering? → Create a new file in `antispam/`
- Where do I add monitoring? → Create a new file in `observability/`

---

**Last Updated**: 2025-10-24
**Version**: v0.24.0
