# TODO List for SMTP Server

## Completed ✓

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

## In Progress 🚧

- [x] Create comprehensive test suite
  - [x] Zig unit tests for core modules
  - [x] Test script for SMTP commands (20 tests)
  - [x] Rate limiting tests
  - [x] Max recipients tests
  - [x] Connection limit tests
  - [x] Message size limit tests
  - [x] Email validation tests

## High Priority 🔴

### Security & Authentication
- [x] TLS/STARTTLS Framework (v0.3.0)
  - [x] Certificate loading and validation
  - [x] STARTTLS command handler
  - [x] TLS module with PEM validation
  - [x] Comprehensive reverse proxy documentation
  - [ ] Native TLS handshake (requires external crypto library)
  - [ ] Perfect Forward Secrecy support (via reverse proxy)
- [ ] Database-backed authentication
  - [ ] SQLite integration
  - [ ] PostgreSQL support
  - [ ] User management API
- [ ] Implement password hashing (bcrypt/argon2)
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

- [ ] Need to verify thread safety of all shared resources
- [ ] TLS handshake not implemented (placeholder only)
- [ ] Authentication accepts any credentials (development mode)
- [x] ~~No connection timeout enforcement yet~~ (Fixed in 0.2.0)
- [ ] Rate limiter cleanup not scheduled
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

**Last Updated**: 2025-10-23

**Maintainers**: Add your name here when contributing

**Priority Legend**:
- 🔴 High Priority: Critical for production use
- 🟡 Medium Priority: Important but not blocking
- 🟢 Low Priority: Nice to have features
- 💡 Future Ideas: Long-term vision items
- 🐛 Known Issues: Bugs to fix
- 🔬 Research Needed: Investigation required
