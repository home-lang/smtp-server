# SMTP Server in Zig

A performant and secure SMTP server implementation written in Zig, designed for self-hosting email infrastructure.

## Features

### Core SMTP

- **RFC 5321 Compliant**: Full implementation of the core SMTP protocol
- **Concurrent Connection Handling**: Multi-threaded design for handling multiple simultaneous connections
- **ESMTP Extensions**:
  - SIZE - Message size declaration
  - 8BITMIME - 8-bit MIME transport
  - PIPELINING - Command pipelining
  - AUTH - Authentication mechanisms (PLAIN, LOGIN)
  - STARTTLS - TLS encryption framework (ready for certificates)

### Security & Rate Limiting

- **Per-IP Rate Limiting**: Sliding window rate limiter with configurable limits
  - Thread-safe implementation with mutex protection
  - Automatic cleanup of stale entries
  - Real-time rate limit statistics
- **Connection Limits**: Maximum concurrent connections enforcement
- **Max Recipients**: Configurable limit on recipients per message
- **Email Validation**: RFC-compliant email address validation
- **Input Sanitization**: Protection against injection attacks
- **Security Event Logging**: Dedicated logging for security-related events

### Configuration & Operations

- **Command-Line Interface**: Comprehensive CLI with help and version flags
  - `--port`, `--host` - Server binding configuration
  - `--log-level` - Adjust logging verbosity (debug|info|warn|error|critical)
  - `--max-connections` - Connection limit override
  - `--enable-tls/--disable-tls` - TLS toggle
  - `--enable-auth/--disable-auth` - Authentication toggle
- **Environment Variables**: Full configuration via environment variables
  - `SMTP_HOST`, `SMTP_PORT`, `SMTP_HOSTNAME`
  - `SMTP_MAX_CONNECTIONS`, `SMTP_MAX_RECIPIENTS`
  - `SMTP_MAX_MESSAGE_SIZE`
  - `SMTP_ENABLE_TLS`, `SMTP_ENABLE_AUTH`
  - `SMTP_TLS_CERT`, `SMTP_TLS_KEY`
- **Graceful Shutdown**: SIGINT/SIGTERM handlers with connection draining
- **Comprehensive Logging**: Multi-level structured logging
  - File-based logging with timestamps
  - Colored console output
  - Thread-safe operations
  - SMTP-specific logging methods

### Performance & Storage

- **Performance Optimized**: Built with Zig for minimal overhead
  - Zero-cost abstractions
  - Compile-time optimizations
  - <10MB memory footprint
- **Maildir Storage**: Standard maildir format for message storage
- **Connection Pooling**: Efficient resource management
- **Active Connection Tracking**: Real-time monitoring of active sessions

## Requirements

- Zig 0.15.1 or later
- POSIX-compliant system (Linux, macOS, BSD)

## Building

```bash
zig build
```

## Running

```bash
# Run with defaults (0.0.0.0:2525)
zig build run

# Or run the compiled binary
./zig-out/bin/smtp-server

# Show help
./zig-out/bin/smtp-server --help

# Show version
./zig-out/bin/smtp-server --version

# Run on custom port with debug logging
./zig-out/bin/smtp-server --port 587 --log-level debug

# Run with custom configuration
./zig-out/bin/smtp-server --host 127.0.0.1 --port 2525 --max-connections 200

# Run with IPv6
./zig-out/bin/smtp-server --host "::1" --port 2525

# Bind to all IPv6 addresses
./zig-out/bin/smtp-server --host "::" --port 2525

# Using environment variables
export SMTP_PORT=2525
export SMTP_MAX_CONNECTIONS=500
export SMTP_HOSTNAME="mail.example.com"
./zig-out/bin/smtp-server

# IPv6 via environment
export SMTP_HOST="::"
./zig-out/bin/smtp-server

# Enable webhook notifications
export SMTP_WEBHOOK_URL="http://localhost:8080/webhook"
./zig-out/bin/smtp-server
```

The server starts on `0.0.0.0:2525` by default (non-privileged port for development).

**IPv6 Support**: The server fully supports IPv6. Use `::1` for localhost or `::` to bind to all IPv6 addresses.

**Webhook Notifications**: Set `SMTP_WEBHOOK_URL` to receive HTTP POST notifications with JSON payload containing sender, recipients, size, and timestamp when mail is received.

See [EXAMPLES.md](EXAMPLES.md) for more usage examples including Docker, systemd, and production deployments.

## Configuration

Configuration is managed in `src/config.zig`. Key settings include:

- **host**: Bind address (default: "0.0.0.0")
- **port**: Port number (default: 2525)
- **max_connections**: Maximum concurrent connections (default: 100)
- **enable_tls**: Enable STARTTLS support (default: false)
- **tls_cert_path**: Path to TLS certificate
- **tls_key_path**: Path to TLS private key
- **enable_auth**: Require authentication (default: true)
- **max_message_size**: Maximum message size in bytes (default: 10MB)
- **timeout_seconds**: Connection timeout (default: 300s)
- **rate_limit_per_ip**: Max messages per IP per hour (default: 100)
- **hostname**: Server hostname (default: "localhost")
- **webhook_url**: HTTP URL to POST on incoming mail (default: none)
- **webhook_enabled**: Enable webhook notifications (default: false)

## Testing

### Zig Unit Tests

```bash
# Run Zig unit tests
zig build test
```

The project includes comprehensive unit tests for:
- **Security Module**: Email validation, rate limiting, hostname validation
- **Error Module**: SMTP error code mapping and error handling
- **Config Module**: Configuration structure and validation

### Integration Test Suite

```bash
# Run the automated SMTP integration tests
./test-smtp.sh

# Test against custom host/port
SMTP_HOST=localhost SMTP_PORT=2525 ./test-smtp.sh
```

The integration test suite includes 20 comprehensive tests:
- Basic SMTP commands (HELO/EHLO, MAIL FROM, RCPT TO, DATA)
- Authentication testing
- Rate limiting verification
- Maximum recipients enforcement
- Message size limit validation
- Invalid command handling
- Sequence validation
- Case insensitivity

### Manual Testing with telnet

```bash
# Using telnet
telnet localhost 2525

# Example session:
EHLO client.example.com
MAIL FROM:<sender@example.com>
RCPT TO:<recipient@example.com>
DATA
Subject: Test Message
From: sender@example.com
To: recipient@example.com

This is a test message.
.
QUIT
```

### Testing with swaks

```bash
# Using swaks (Swiss Army Knife for SMTP)
swaks --to recipient@example.com \
      --from sender@example.com \
      --server localhost:2525 \
      --body "Test message"

# Test with authentication
swaks --to recipient@example.com \
      --from sender@example.com \
      --server localhost:2525 \
      --auth PLAIN \
      --auth-user test \
      --auth-password test

# Test rate limiting (send multiple messages)
for i in {1..105}; do
    swaks --to test@example.com \
          --from sender@example.com \
          --server localhost:2525 \
          --body "Message $i" \
          --hide-all
done
```

See [EXAMPLES.md](EXAMPLES.md) for more testing examples and integration guides.

## Project Structure

```
.
├── build.zig           # Build configuration
├── test-smtp.sh        # Automated test suite
├── EXAMPLES.md         # Comprehensive usage examples
├── TLS.md              # TLS/STARTTLS setup guide
├── TODO.md             # Development roadmap
├── src/
│   ├── main.zig        # Entry point with CLI and signal handling
│   ├── smtp.zig        # SMTP server with connection management
│   ├── protocol.zig    # SMTP protocol handler (RFC 5321)
│   ├── config.zig      # Configuration with env var support
│   ├── args.zig        # Command-line argument parser
│   ├── auth.zig        # Authentication mechanisms
│   ├── security.zig    # Rate limiting, validation, security
│   ├── logger.zig      # Multi-level structured logging
│   ├── errors.zig      # Custom error types and handling
│   ├── webhook.zig     # Webhook notifications
│   └── tls.zig         # TLS certificate management
└── mail/
    └── new/            # Incoming messages (maildir format)
```

## Security Considerations

### For Production Use

1. **TLS/SSL**: Deploy behind a reverse proxy (nginx, HAProxy) for TLS termination:
   ```bash
   # See TLS.md for complete setup guide
   # Example with nginx on port 465 (SMTPS)
   # Server runs on port 2525, nginx handles TLS
   ```

   The server includes TLS configuration support but requires a reverse proxy for the cryptographic handshake. See [TLS.md](TLS.md) for detailed setup instructions including:
   - nginx configuration with Let's Encrypt
   - HAProxy setup
   - Certificate management
   - Self-signed certificates for development

2. **Authentication**: The current implementation accepts all credentials. Implement proper credential verification in `src/auth.zig`:
   ```zig
   pub fn verifyCredentials(username: []const u8, password: []const u8) bool {
       // Add your authentication logic here
       // Check against database, LDAP, etc.
   }
   ```

3. **Rate Limiting**: Adjust rate limits based on your needs in `config.zig`

4. **Firewall**: Use firewall rules to restrict access:
   ```bash
   # Example using ufw
   sudo ufw allow from trusted.ip.address to any port 25
   ```

5. **Run as Non-Root**: After binding to port 25, drop privileges:
   ```bash
   # Use a process supervisor like systemd with User= directive
   ```

6. **Logging**: Monitor logs for suspicious activity

7. **SPF/DKIM/DMARC**: Implement email authentication when sending:
   - Set up SPF records
   - Configure DKIM signing
   - Publish DMARC policy

## Running on Port 25

To run on the standard SMTP port (25), you'll need elevated privileges:

```bash
# Option 1: Run as root (not recommended)
sudo zig build run

# Option 2: Grant capability (Linux)
sudo setcap 'cap_net_bind_service=+ep' zig-out/bin/smtp-server
./zig-out/bin/smtp-server

# Option 3: Use iptables redirect
sudo iptables -t nat -A PREROUTING -p tcp --dport 25 -j REDIRECT --to-port 2525
```

## Development

### Running All Tests

```bash
# Run Zig unit tests
zig build test

# Run integration tests (requires server running on port 2525)
./test-smtp.sh
```

### Code Style

This project follows Zig's standard formatting:

```bash
zig fmt src/
```

### Release Process

This project uses [zig-bump](https://github.com/stacksjs/zig-bump) for version management and automated releases.

#### Quick Release (Recommended)

The easiest way - an interactive script that guides you through the release:

```bash
./scripts/release.sh
# or
make release
```

This provides a beautiful interactive menu with:
- Pre-release checklist
- Version selection with visual preview
- Dry-run option
- Confirmation before release
- Automatic CHANGELOG.md reminder

#### Direct Commands

If you prefer direct commands:

```bash
# Native Zig build (cross-platform)
zig build bump-patch       # Bug fixes (0.0.1 -> 0.0.2)
zig build bump-minor       # New features (0.0.1 -> 0.1.0)
zig build bump-major       # Breaking changes (0.0.1 -> 1.0.0)
zig build bump             # Interactive selection
zig build bump-patch-dry   # Preview changes

# Or using Makefile shortcuts
make release-patch         # Same as zig build bump-patch
make release-minor         # Same as zig build bump-minor
make release-major         # Same as zig build bump-major
```

When you bump the version, it will:
1. Update `build.zig.zon`
2. Create a git commit and tag
3. Push to GitHub
4. Trigger the release workflow to build binaries and Docker images

See [docs/RELEASE_PROCESS.md](docs/RELEASE_PROCESS.md) for detailed release documentation.

## Roadmap

- [ ] Full TLS/STARTTLS implementation
- [ ] Database-backed authentication
- [ ] DKIM signing support
- [ ] SPF validation
- [ ] Greylisting
- [ ] Spam filtering integration
- [ ] Webhook notifications for incoming mail
- [ ] REST API for message retrieval
- [ ] Web-based admin interface
- [ ] IPv6 support
- [ ] SMTP relay configuration
- [ ] Bounce handling

## Performance

Built with Zig's performance-first philosophy:

- Zero-cost abstractions
- Compile-time optimizations
- Minimal runtime overhead
- Efficient memory management
- No garbage collection pauses

Typical performance on modern hardware:
- 1000+ concurrent connections
- Sub-millisecond response times
- <10MB memory footprint for base server

## Contributing

Contributions are welcome! Please ensure:

1. Code follows Zig formatting (`zig fmt`)
2. Tests pass (`zig build test`)
3. Security considerations are addressed
4. Documentation is updated

## License

MIT License - See LICENSE file for details

## Acknowledgments

- Built with [Zig](https://ziglang.org/)
- SMTP protocol: [RFC 5321](https://tools.ietf.org/html/rfc5321)
- ESMTP extensions: [RFC 1869](https://tools.ietf.org/html/rfc1869)

## Support

For issues, questions, or contributions, please open an issue on the repository.

## Disclaimer

This is a development server implementation. For production use, ensure proper security hardening, monitoring, and compliance with email regulations (CAN-SPAM, GDPR, etc.).
