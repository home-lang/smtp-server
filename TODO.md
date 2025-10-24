# TODO List for SMTP Server

## Recent Updates 📝

### v0.5.0 (2025-10-23) - Database-backed Authentication
- ✅ Implemented SQLite database backend for user management
- ✅ Added Argon2id password hashing (more secure than bcrypt)
- ✅ Created user management CLI tool (user-cli) with 7 commands
- ✅ Updated SMTP AUTH PLAIN to verify credentials against database
- ✅ Proper error handling and security logging for auth failures
- ✅ Constant-time password comparison to prevent timing attacks
- ✅ Environment variable support for database path (SMTP_DB_PATH)
- ✅ Comprehensive testing of authentication flow

### v0.4.0 (2025-10-23) - TLS Library Refactoring
- ✅ Extracted TLS implementation to standalone zig-tls library
- ✅ Removed vendor/tls directory (clean dependency management)
- ✅ Updated build system to use external dependency
- ✅ Created comprehensive TLS documentation
- ✅ Implemented heap-allocated I/O buffers for session lifetime
- ✅ Fixed certificate loading with absolute path support
- ⚠️ TLS handshake has cipher issue (reverse proxy recommended for production)

### v0.3.0 - TLS Infrastructure
- Certificate management and validation
- STARTTLS protocol support
- ConnectionWrapper abstraction
- Production deployment via reverse proxy

### v0.2.0 - Security & Performance
- Connection timeout enforcement
- Per-IP rate limiting with sliding windows
- Maximum recipients per message
- Graceful shutdown with signal handlers

## Completed ✓

### Core Infrastructure (v0.1.0 - v0.3.0)
- [x] Set up Zig project structure with build.zig
- [x] Implement core SMTP protocol handler (RFC 5321)
- [x] Create TCP server with connection handling
- [x] Add basic TLS/SSL support framework (STARTTLS)
- [x] Implement authentication mechanisms (PLAIN, LOGIN)
- [x] Add email message parsing and validation
- [x] Create configuration system for server settings
- [x] Implement rate limiting and security features
- [x] Basic input sanitization
- [x] Email address validation
- [x] Maildir-style message storage
- [x] Create README with setup and usage instructions
- [x] Add comprehensive logging system
  - [x] Structured logging with log levels (DEBUG, INFO, WARN, ERROR, CRITICAL)
  - [x] File-based logging with timestamps
  - [x] Colored console output
  - [x] SMTP-specific logging methods
  - [x] Thread-safe logging with mutex
- [x] Add proper error handling throughout
  - [x] Custom SMTP error types
  - [x] Error information system with codes and messages
  - [x] Proper error propagation
- [x] Implement graceful shutdown
  - [x] Signal handlers for SIGINT and SIGTERM
  - [x] Wait for active connections to complete
  - [x] Atomic shutdown flag
  - [x] Connection tracking
- [x] Implement connection limits per IP
  - [x] Max connections enforcement
  - [x] Active connection counter
  - [x] Proper rejection with SMTP error
- [x] Add command-line argument parsing
  - [x] Help and version flags
  - [x] Config file path option
  - [x] Log level override
  - [x] Port and host override
  - [x] Max connections override
  - [x] TLS and auth toggles
- [x] Environment variable configuration support
  - [x] SMTP_HOST, SMTP_PORT
  - [x] SMTP_HOSTNAME
  - [x] SMTP_MAX_CONNECTIONS
  - [x] SMTP_MAX_MESSAGE_SIZE
  - [x] SMTP_MAX_RECIPIENTS
  - [x] SMTP_ENABLE_TLS, SMTP_ENABLE_AUTH
  - [x] SMTP_TLS_CERT, SMTP_TLS_KEY
- [x] Per-IP rate limiting with time windows
  - [x] Sliding window implementation
  - [x] Thread-safe with mutex
  - [x] Automatic cleanup of old entries
  - [x] Rate limit statistics
  - [x] Integration with DATA command
- [x] Maximum recipients per message limit
  - [x] Configurable limit
  - [x] Security event logging

### TLS Infrastructure (v0.4.0 - Latest)
- [x] Extract TLS to standalone zig-tls library
  - [x] Created ~/Code/zig-tls with 19 source files (388KB)
  - [x] Removed vendor/tls directory
  - [x] Updated build.zig to use dependency
  - [x] Clean package structure with build.zig.zon
  - [x] MIT License and documentation
- [x] TLS Certificate Management
  - [x] Certificate loading and validation
  - [x] PEM format support
  - [x] Absolute path handling
  - [x] CertKeyPair caching
  - [x] Proper cleanup in deinit
- [x] STARTTLS Protocol Implementation
  - [x] STARTTLS command handler
  - [x] State reset after TLS upgrade
  - [x] ConnectionWrapper abstraction
  - [x] Heap-allocated I/O buffers for session lifetime
  - [x] Session-scoped TLS resource management
- [x] TLS Documentation
  - [x] TLS.md (reverse proxy setup guide)
  - [x] TLS_STATUS.md (implementation status)
  - [x] IMPLEMENTATION_SUMMARY.md (complete technical summary)
  - [x] REFACTORING.md (library extraction documentation)

## In Progress 🚧

### Testing Suite
- [x] Create comprehensive test suite
  - [x] Zig unit tests for core modules
  - [x] Test script for SMTP commands (20 tests)
  - [x] Rate limiting tests
  - [x] Max recipients tests
  - [x] Connection limit tests
  - [x] Message size limit tests
  - [x] Email validation tests

### TLS Handshake Debugging
- [ ] Debug TLS cipher/handshake errors
  - [x] Heap-allocated I/O buffers implemented
  - [x] Session-scoped resource management
  - [x] CertKeyPair loading from absolute paths
  - [ ] Investigate cipher panic during handshake
  - [ ] Test with different TLS clients
  - [ ] Add detailed TLS handshake logging
  - [ ] Consider alternative I/O approach for STARTTLS

## High Priority 🔴

### Security & Authentication
- [x] TLS/STARTTLS Framework (v0.3.0+)
  - [x] Certificate loading and validation
  - [x] STARTTLS command handler
  - [x] TLS module with PEM validation
  - [x] Comprehensive reverse proxy documentation
  - [x] Heap-allocated I/O for session lifetime
  - [x] Standalone zig-tls library (v0.4.0)
  - [ ] Native TLS handshake completion (98% done, cipher issue)
  - [ ] Production deployment with reverse proxy (RECOMMENDED)
- [x] Database-backed authentication
  - [x] SQLite integration
  - [x] User management CLI tool (user-cli)
  - [ ] PostgreSQL support
  - [ ] User management API (REST/GraphQL)
- [x] Implement password hashing with Argon2id
  - [x] Argon2id implementation (more secure than bcrypt)
  - [x] Base64 encoding for storage
  - [x] Constant-time comparison
  - [x] Integration with AUTH PLAIN
- [ ] Add SASL authentication mechanisms
  - [ ] CRAM-MD5
  - [ ] DIGEST-MD5
- [ ] Add DNSBL/RBL checking for spam prevention
- [ ] Implement greylisting

### Core Functionality
- [x] Environment variable configuration support
- [x] Per-IP rate limiting with time windows
- [x] Connection timeout enforcement
- [x] Maximum recipients per message limit

## Medium Priority 🟡

### Email Features
- [ ] DKIM signing support
  - [ ] Key generation utilities
  - [ ] Signature creation
  - [ ] DNS record helpers
- [ ] SPF validation for incoming mail
- [ ] DMARC policy checking
- [ ] Email header parsing and validation
- [ ] MIME multipart message support
- [ ] HTML email support
- [ ] Attachment handling
- [ ] Implement SIZE extension properly
- [ ] Implement CHUNKING extension (RFC 3030)
- [ ] Add SMTPUTF8 support (RFC 6531)

### Storage & Delivery
- [ ] Pluggable storage backends
  - [ ] Maildir (current)
  - [ ] mbox format
  - [ ] Database storage
  - [ ] S3/object storage
- [ ] Message queue for outbound delivery
- [ ] SMTP relay support (forward to other servers)
- [ ] Retry logic for failed deliveries
- [ ] Bounce message handling
- [ ] Delivery status notifications (DSN)

### Performance
- [ ] Connection pooling
- [ ] Memory pool for allocations
- [ ] Zero-copy buffer management
- [ ] Async I/O with io_uring (Linux)
- [ ] Performance benchmarking suite
- [ ] Load testing tools
- [ ] Metrics collection (Prometheus format)

### Monitoring & Observability
- [ ] Health check endpoint
- [ ] Statistics API
  - [ ] Messages received/sent
  - [ ] Connection counts
  - [ ] Error rates
  - [ ] Queue sizes
- [ ] Integration with monitoring systems
  - [ ] Prometheus exporter
  - [ ] StatsD support
  - [ ] OpenTelemetry traces

## Low Priority 🟢

### Administration
- [ ] Web-based admin interface
  - [ ] Server status dashboard
  - [ ] User management
  - [ ] Configuration editor
  - [ ] Log viewer
- [ ] REST API for management
  - [ ] User CRUD operations
  - [ ] Message inspection
  - [ ] Queue management
- [ ] CLI administration tool
  - [ ] Server control
  - [ ] Queue inspection
  - [ ] User management

### Advanced Features
- [x] Webhook notifications for incoming mail (HTTP POST with JSON payload)
- [ ] Message filtering/routing rules
- [ ] Auto-responder support
- [ ] Mailing list functionality
- [ ] Vacation/out-of-office responses
- [ ] Virus scanning integration (ClamAV)
- [ ] Spam filter integration (SpamAssassin)
- [ ] Content filtering
- [ ] Attachment size limits per user
- [ ] Quota management

### Protocol Extensions
- [ ] SMTP PIPELINING optimization
- [ ] BINARYMIME support (RFC 3030)
- [ ] DELIVERBY extension (RFC 2852)
- [ ] DSN extension (RFC 3461)
- [ ] ETRN support (RFC 1985)
- [ ] ATRN support (RFC 2645)

### Developer Experience
- [ ] Comprehensive test suite
  - [ ] Unit tests for all modules
  - [ ] Integration tests
  - [ ] End-to-end tests
  - [ ] Fuzzing tests
- [ ] CI/CD pipeline
  - [ ] GitHub Actions workflow
  - [ ] Automated testing
  - [ ] Release automation
- [ ] Docker container
  - [ ] Multi-stage build
  - [ ] Alpine-based image
  - [ ] Docker Compose setup
- [ ] Kubernetes deployment manifests
- [ ] Ansible playbook for deployment
- [ ] Documentation
  - [ ] API documentation
  - [ ] Architecture diagrams
  - [ ] Deployment guides
  - [ ] Troubleshooting guide
  - [ ] Performance tuning guide

### Multi-Platform Support
- [ ] Windows support
- [ ] BSD support (FreeBSD, OpenBSD)
- [ ] ARM architecture support
- [x] IPv6 support (full dual-stack support)
- [ ] Unix socket support

### Compliance & Standards
- [ ] Full RFC 5321 compliance testing
- [ ] RFC 5322 message format compliance
- [ ] RFC 6409 message submission support
- [ ] CAN-SPAM compliance features
- [ ] GDPR compliance features
  - [ ] Data export
  - [ ] Data deletion
  - [ ] Audit logging

## Future Ideas 💡

- [ ] Machine learning spam detection
- [ ] Encrypted email storage at rest
- [ ] Multi-tenancy support
- [ ] Cluster mode for high availability
- [ ] Message search functionality (full-text)
- [ ] Email archiving
- [ ] Backup and restore utilities
- [ ] Migration tools from other servers
- [ ] Plugin system for extensibility
- [ ] GraphQL API
- [ ] WebSocket real-time notifications
- [ ] IMAP server integration
- [ ] POP3 server support
- [ ] CalDAV/CardDAV support
- [ ] ActiveSync support
- [ ] Webmail client
- [ ] Mobile app for administration

## Known Issues 🐛

### Critical
- [ ] TLS handshake cipher panic during STARTTLS
  - Server sends "220 Ready to start TLS"
  - Handshake initiates but fails with cipher decrypt error
  - Root cause: Possible I/O buffer lifecycle or tls.zig library issue
  - **Workaround**: Use reverse proxy (nginx/HAProxy) for production TLS

### High Priority
- [ ] Need to verify thread safety of all shared resources
- [x] ~~Authentication accepts any credentials (development mode)~~ (Fixed: now uses database with Argon2id)
- [ ] Rate limiter cleanup not scheduled

### Medium Priority
- [x] ~~No connection timeout enforcement yet~~ (Fixed in 0.2.0)
- [x] ~~No maximum recipients per message limit~~ (Fixed in 0.1.0)
- [ ] No DATA command timeout (partial - general timeout implemented)
- [ ] HTTPS webhooks not supported (HTTP only)

## Research Needed 🔬

- [ ] Best practices for email server security
- [ ] Modern SMTP server architectures
- [ ] Email deliverability optimization
- [ ] Efficient queue management strategies
- [ ] Zero-downtime deployment strategies
- [ ] Email reputation management

---

## Project Information

**Last Updated**: 2025-10-24 04:47 UTC
**Current Version**: v0.5.0
**Zig Version**: 0.15.1
**License**: MIT

**Key Dependencies**:
- zig-tls: ~/Code/zig-tls (Pure Zig TLS 1.3 implementation)
- SQLite3: System library (user authentication database)

**Maintainers**: Add your name here when contributing

**Related Documentation**:
- README.md - Getting started guide
- TLS.md - Reverse proxy setup for production TLS
- TLS_STATUS.md - TLS implementation status
- IMPLEMENTATION_SUMMARY.md - Complete TLS technical summary
- REFACTORING.md - zig-tls library extraction details

**Priority Legend**:
- 🔴 High Priority: Critical for production use
- 🟡 Medium Priority: Important but not blocking
- 🟢 Low Priority: Nice to have features
- 💡 Future Ideas: Long-term vision items
- 🐛 Known Issues: Bugs to fix
- 🔬 Research Needed: Investigation required
