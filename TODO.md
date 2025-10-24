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

## In Progress 🚧

- [ ] Add comprehensive logging system
  - [ ] Structured logging with log levels
  - [ ] Log rotation support
  - [ ] Performance metrics logging
  - [ ] Security event logging

## High Priority 🔴

### Security & Authentication
- [ ] Implement real TLS/STARTTLS with OpenSSL/BearSSL
  - [ ] Certificate loading and validation
  - [ ] Secure connection upgrade
  - [ ] Perfect Forward Secrecy support
- [ ] Database-backed authentication
  - [ ] SQLite integration
  - [ ] PostgreSQL support
  - [ ] User management API
- [ ] Implement password hashing (bcrypt/argon2)
- [ ] Add SASL authentication mechanisms
  - [ ] CRAM-MD5
  - [ ] DIGEST-MD5
- [ ] Implement connection limits per IP
- [ ] Add DNSBL/RBL checking for spam prevention
- [ ] Implement greylisting

### Core Functionality
- [ ] Add proper error handling throughout
  - [ ] Custom error types
  - [ ] Error recovery strategies
  - [ ] Graceful degradation
- [ ] Implement graceful shutdown
  - [ ] Handle SIGTERM/SIGINT
  - [ ] Complete ongoing transactions
  - [ ] Close connections cleanly
- [ ] Add command-line argument parsing
  - [ ] Custom config file path
  - [ ] Override config values
  - [ ] Debug mode flag
- [ ] Environment variable configuration support

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
- [ ] Webhook notifications for incoming mail
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
- [ ] IPv6 support
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
- [ ] No connection timeout enforcement yet
- [ ] Rate limiter cleanup not scheduled
- [ ] No maximum recipients per message limit
- [ ] No DATA command timeout

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
