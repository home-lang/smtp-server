# Known Issues and Solutions

This document tracks known issues with the SMTP server and provides solutions or workarounds.

## ✅ Resolved Issues

### HTTPS Webhooks Not Supported (Fixed in v0.20.0)

**Problem:** Webhook implementation only supported HTTP URLs, not HTTPS, preventing secure webhook notifications.

**Solution:** Implemented full TLS client support for HTTPS webhooks:
- Uses zig-tls library's `clientFromStream` for TLS connections
- Automatic protocol detection based on URL scheme (http:// vs https://)
- Optional certificate verification (insecure_skip_verify for development)
- Proper TLS handshake and encrypted communication
- Graceful fallback to HTTP for non-HTTPS URLs

**Usage:**
```bash
# SMTP server now supports both HTTP and HTTPS webhook URLs
SMTP_WEBHOOK_URL=https://secure-endpoint.example.com/webhook
```

**Files Changed:**
- `src/webhook.zig` - Added TLS client support for HTTPS

**Benefits:**
- Secure webhook notifications to HTTPS endpoints
- Protection of sensitive email metadata in transit
- Production-ready webhook integration

---

### Rate Limiter Cleanup Not Scheduled (Fixed in v0.18.0)

**Problem:** The RateLimiter had a `cleanup()` method but it was never called, causing memory to grow over time as old IP entries were never removed.

**Solution:** Added automatic cleanup scheduling with background thread:
- New `startAutomaticCleanup()` method launches a background worker thread
- Cleanup runs every hour by default
- Thread uses atomic flag for clean shutdown
- Entries are removed after 2x the window time of inactivity
- Call `rate_limiter.startAutomaticCleanup()` after initialization

**Usage:**
```zig
var rate_limiter = security.RateLimiter.init(allocator, 3600, 100);
defer rate_limiter.deinit(); // Automatically stops cleanup thread

// Start automatic cleanup
try rate_limiter.startAutomaticCleanup();
```

**Files Changed:**
- `src/security.zig` - Added automatic cleanup with background thread

---

## 🔴 Critical Issues

### TLS Handshake Cipher Panic During STARTTLS

**Status:** Known issue, workaround available

**Problem:**
- Server sends "220 Ready to start TLS"
- Handshake initiates but fails with cipher decrypt error
- Root cause: Possible I/O buffer lifecycle or zig-tls library issue

**Workaround (Recommended for Production):**
Use reverse proxy (nginx/HAProxy) for TLS termination:

**nginx Configuration:**
```nginx
stream {
    upstream smtp_backend {
        server 127.0.0.1:2525;  # SMTP server on non-standard port
    }

    server {
        listen 587 ssl;
        proxy_pass smtp_backend;

        ssl_certificate /etc/ssl/certs/mail.example.com.crt;
        ssl_certificate_key /etc/ssl/private/mail.example.com.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
    }
}
```

**HAProxy Configuration:**
```
frontend smtp_tls
    bind *:587 ssl crt /etc/ssl/mail.example.com.pem
    mode tcp
    default_backend smtp_servers

backend smtp_servers
    mode tcp
    server smtp1 127.0.0.1:2525
```

**Long-term Solution:**
- Debug zig-tls cipher implementation
- Test with different TLS clients
- Add detailed TLS handshake logging
- Consider alternative I/O approach for STARTTLS

---

## 🟡 High Priority Issues

### DATA Command Timeout

**Status:** Partial implementation

**Problem:**
- General connection timeout exists
- No specific timeout for DATA phase
- Slow clients can hold connections during message transfer

**Current Workaround:**
Use the existing connection timeout (`CONNECTION_TIMEOUT` environment variable).

**Recommended Solution:**

**Option 1: Poll-based timeout (Unix)**
```zig
const std = @import("std");
const posix = std.posix;

fn readWithTimeout(
    fd: posix.socket_t,
    buffer: []u8,
    timeout_ms: i32,
) !usize {
    var pollfds = [_]posix.pollfd{.{
        .fd = fd,
        .events = posix.POLL.IN,
        .revents = 0,
    }};

    const result = try posix.poll(&pollfds, timeout_ms);
    if (result == 0) return error.Timeout;
    if (pollfds[0].revents & posix.POLL.ERR != 0) return error.SocketError;

    return try posix.read(fd, buffer);
}
```

**Option 2: Total DATA phase timeout**
```zig
const start_time = std.time.milliTimestamp();
const data_timeout_ms = 600000; // 10 minutes

while (true) {
    const elapsed = std.time.milliTimestamp() - start_time;
    if (elapsed > data_timeout_ms) {
        try self.sendResponse(writer, 451, "DATA timeout", null);
        return error.DataTimeout;
    }

    // Continue reading...
}
```

**Configuration:**
```bash
# Environment variables
DATA_COMMAND_TIMEOUT=600  # 10 minutes for entire DATA phase
DATA_LINE_TIMEOUT=30      # 30 seconds between lines
```

**Files to Modify:**
- `src/protocol.zig` - Add timeout to handleData()
- `src/config.zig` - Add DATA timeout configuration

---

### Thread Safety Verification Needed

**Status:** Needs audit

**Problem:**
Need to verify thread safety of all shared resources, especially:
- Rate limiter (✅ uses mutex)
- Configuration (mostly read-only)
- Database connections (needs review)
- Logging (needs review)
- Statistics counters (needs atomic operations)

**Action Items:**
1. Audit all shared data structures
2. Add mutexes or atomic operations where needed
3. Document thread safety guarantees
4. Add thread safety tests

**Critical Areas:**
```zig
// Example: Statistics should use atomic operations
pub const Statistics = struct {
    messages_received: std.atomic.Value(u64),
    messages_sent: std.atomic.Value(u64),
    connections_total: std.atomic.Value(u64),

    pub fn incrementMessagesReceived(self: *Statistics) void {
        _ = self.messages_received.fetchAdd(1, .monotonic);
    }
};
```

---

## 🟠 Medium Priority Issues

---

## 💡 Enhancement Opportunities

### Connection Timeout Granularity

**Current:** Single connection timeout for entire session

**Enhancement:** Different timeouts for different phases:
```bash
GREETING_TIMEOUT=30        # 30s to send greeting
COMMAND_TIMEOUT=300        # 5m between commands
DATA_TIMEOUT=600           # 10m for DATA phase
IDLE_TIMEOUT=120           # 2m idle timeout
```

### Rate Limiter Per-User Instead of Per-IP

**Current:** Rate limiting by IP address

**Enhancement:** Rate limiting by authenticated user:
```zig
pub fn checkAndIncrementUser(
    self: *RateLimiter,
    user: []const u8,
) !bool {
    // Similar to checkAndIncrement but keyed by username
}
```

**Benefits:**
- Better control for authenticated submissions
- Prevents legitimate users from being blocked by shared IP
- Complements per-IP rate limiting

### Configurable Cleanup Interval

**Current:** Hardcoded 1-hour cleanup interval

**Enhancement:**
```zig
pub fn startAutomaticCleanup(
    self: *RateLimiter,
    interval_seconds: u64,
) !void {
    // Use configurable interval instead of hardcoded
}
```

```bash
RATE_LIMITER_CLEANUP_INTERVAL=3600  # 1 hour
```

---

## 📊 Performance Considerations

### Memory Usage in DATA Phase

**Observation:** Message data is accumulated in ArrayList

**Potential Issue:** Large messages (50MB) held entirely in memory

**Mitigation:**
1. ✅ Max message size enforcement (already implemented)
2. Consider streaming to disk for large messages:
```zig
if (message_data.items.len > threshold) {
    // Stream to temporary file
    const temp_file = try std.fs.cwd().createFile(temp_path, .{});
    defer temp_file.close();
    try temp_file.writeAll(message_data.items);
}
```

### Database Connection Pooling

**Current:** Single database connection per server

**Enhancement:** Connection pool for concurrent operations:
```zig
pub const ConnectionPool = struct {
    connections: []Database,
    available: std.ArrayList(usize),
    mutex: std.Thread.Mutex,

    pub fn acquire(self: *ConnectionPool) !*Database {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.available.popOrNull()) |idx| {
            return &self.connections[idx];
        }
        return error.NoAvailableConnections;
    }
};
```

---

## 🔧 Testing Recommendations

### Load Testing

Test scenarios to validate fixes:

1. **Rate Limiter Cleanup:**
```bash
# Generate traffic from many IPs
for i in {1..1000}; do
    curl -X POST http://localhost:25 \
        --header "X-Forwarded-For: 192.168.1.$i" &
done

# Monitor memory growth
watch -n 1 'ps aux | grep smtp-server'
```

2. **DATA Timeout:**
```python
import socket
import time

sock = socket.socket()
sock.connect(('localhost', 25))

# Send EHLO, MAIL, RCPT
sock.sendall(b'EHLO test\r\n')
sock.recv(1024)
sock.sendall(b'MAIL FROM:<test@example.com>\r\n')
sock.recv(1024)
sock.sendall(b'RCPT TO:<test@example.com>\r\n')
sock.recv(1024)

# Send DATA and wait
sock.sendall(b'DATA\r\n')
sock.recv(1024)

# Don't send anything - test timeout
time.sleep(620)  # Wait 10+ minutes
```

3. **Thread Safety:**
```bash
# Concurrent connections
for i in {1..100}; do
    (telnet localhost 25 << EOF
EHLO test$i
MAIL FROM:<user$i@example.com>
QUIT
EOF
    ) &
done
wait
```

---

## 📝 Documentation Updates Needed

1. **deployment.md** - Add TLS proxy configuration
2. **configuration.md** - Add DATA timeout options
3. **troubleshooting.md** - Add timeout debugging section
4. **performance.md** - Add rate limiter tuning guide

---

## 🎯 Priority Roadmap

### Immediate (v0.18.0)
- [x] Fix rate limiter cleanup scheduling
- [ ] Document TLS proxy workaround
- [ ] Add DATA command timeout

### Short-term (v0.19.0)
- [ ] Add HTTPS webhook support
- [ ] Thread safety audit and fixes
- [ ] Configurable timeout granularity

### Medium-term (v0.20.0)
- [ ] Fix TLS handshake issue (if feasible)
- [ ] Connection pooling
- [ ] Per-user rate limiting

### Long-term
- [ ] Streaming large message handling
- [ ] Advanced monitoring and alerting
- [ ] Performance optimizations

---

## 🤝 Contributing

If you encounter issues or have solutions:

1. Check this document first
2. Search GitHub issues
3. If new, open an issue with:
   - Problem description
   - Reproduction steps
   - Environment details
   - Proposed solution (if any)

---

**Last Updated:** 2025-10-24
**Version:** v0.18.0
