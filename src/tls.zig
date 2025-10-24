const std = @import("std");
const net = std.net;
const logger = @import("logger.zig");
const tls = @import("tls");

/// TLS configuration for the SMTP server
pub const TlsConfig = struct {
    enabled: bool,
    cert_path: ?[]const u8,
    key_path: ?[]const u8,
};

/// TLS context for managing certificates and keys
pub const TlsContext = struct {
    allocator: std.mem.Allocator,
    config: TlsConfig,
    cert_data: ?[]u8,
    key_data: ?[]u8,
    logger: *logger.Logger,

    pub fn init(allocator: std.mem.Allocator, cfg: TlsConfig, log: *logger.Logger) !TlsContext {
        var ctx = TlsContext{
            .allocator = allocator,
            .config = cfg,
            .cert_data = null,
            .key_data = null,
            .logger = log,
        };

        if (cfg.enabled) {
            try ctx.loadCertificates();
        }

        return ctx;
    }

    pub fn deinit(self: *TlsContext) void {
        if (self.cert_data) |data| {
            self.allocator.free(data);
        }
        if (self.key_data) |data| {
            self.allocator.free(data);
        }
    }

    fn loadCertificates(self: *TlsContext) !void {
        if (self.config.cert_path) |cert_path| {
            self.logger.info("Loading TLS certificate from: {s}", .{cert_path});

            const cert_file = std.fs.cwd().openFile(cert_path, .{}) catch |err| {
                self.logger.err("Failed to open certificate file: {s} - {}", .{ cert_path, err });
                return error.CertificateLoadFailed;
            };
            defer cert_file.close();

            const cert_data = try cert_file.readToEndAlloc(self.allocator, 1024 * 1024); // Max 1MB
            self.cert_data = cert_data;

            self.logger.info("Certificate loaded successfully ({d} bytes)", .{cert_data.len});
        }

        if (self.config.key_path) |key_path| {
            self.logger.info("Loading TLS private key from: {s}", .{key_path});

            const key_file = std.fs.cwd().openFile(key_path, .{}) catch |err| {
                self.logger.err("Failed to open key file: {s} - {}", .{ key_path, err });
                return error.KeyLoadFailed;
            };
            defer key_file.close();

            const key_data = try key_file.readToEndAlloc(self.allocator, 1024 * 1024); // Max 1MB
            self.key_data = key_data;

            self.logger.info("Private key loaded successfully ({d} bytes)", .{key_data.len});
        }

        if (self.cert_data == null or self.key_data == null) {
            self.logger.err("TLS enabled but certificate or key not provided", .{});
            return error.IncompleteTlsConfiguration;
        }
    }

    /// Check if certificate and key are valid PEM format
    pub fn validateCertificates(self: *TlsContext) !void {
        if (self.cert_data) |cert| {
            if (!std.mem.startsWith(u8, cert, "-----BEGIN CERTIFICATE-----")) {
                self.logger.err("Certificate does not appear to be in PEM format", .{});
                return error.InvalidCertificateFormat;
            }
        }

        if (self.key_data) |key| {
            if (!std.mem.startsWith(u8, key, "-----BEGIN") or
                !std.mem.containsAtLeast(u8, key, 1, "PRIVATE KEY-----"))
            {
                self.logger.err("Private key does not appear to be in PEM format", .{});
                return error.InvalidKeyFormat;
            }
        }

        self.logger.info("TLS certificates validated (format check only)", .{});
    }
};

/// TLS connection wrapper
pub const TlsConnection = struct {
    conn: tls.Connection,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *TlsConnection) void {
        self.conn.close() catch {};
    }

    pub fn read(self: *TlsConnection, buffer: []u8) !usize {
        return self.conn.read(buffer);
    }

    pub fn write(self: *TlsConnection, data: []const u8) !usize {
        return self.conn.write(data);
    }
};

/// Upgrade a plain TCP connection to TLS using tls.zig library
pub fn upgradeToTls(
    allocator: std.mem.Allocator,
    stream: net.Stream,
    ctx: *TlsContext,
    log: *logger.Logger,
) !TlsConnection {
    if (!ctx.config.enabled) {
        return error.TlsNotEnabled;
    }

    const cert_path = ctx.config.cert_path orelse return error.TlsNotConfigured;
    const key_path = ctx.config.key_path orelse return error.TlsNotConfigured;

    log.info("Starting TLS handshake...", .{});

    // Load certificate and key
    var auth = tls.config.CertKeyPair.fromFilePathAbsolute(
        allocator,
        cert_path,
        key_path,
    ) catch |err| {
        log.err("Failed to load certificate/key: {}", .{err});
        return error.InvalidCertificate;
    };
    defer auth.deinit(allocator);

    // Perform TLS handshake
    const tls_conn = tls.serverFromStream(stream, .{
        .auth = &auth,
    }) catch |err| {
        log.err("TLS handshake failed: {}", .{err});
        return error.TlsHandshakeFailed;
    };

    log.info("TLS handshake successful", .{});

    return TlsConnection{
        .conn = tls_conn,
        .allocator = allocator,
    };
}

/// Generate a self-signed certificate for testing (helper function)
/// This is for development only - use proper CA-signed certificates in production
pub fn generateSelfSignedCert(allocator: std.mem.Allocator, hostname: []const u8) !void {
    _ = allocator;
    _ = hostname;

    // This would require OpenSSL or similar
    // For development, users should generate certificates manually:
    // openssl req -x509 -newkey rsa:4096 -nodes -keyout key.pem -out cert.pem -days 365

    return error.NotImplemented;
}
