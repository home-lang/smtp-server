const std = @import("std");
const net = std.net;
const logger = @import("logger.zig");
const tls = @import("tls");
const cert_validator = @import("cert_validator.zig");

/// TLS configuration for the SMTP server
pub const TlsConfig = struct {
    enabled: bool,
    cert_path: ?[]const u8,
    key_path: ?[]const u8,
    validate_certificates: bool = true,
    allow_self_signed: bool = false,
};

/// TLS context for managing certificates and keys
pub const TlsContext = struct {
    allocator: std.mem.Allocator,
    config: TlsConfig,
    cert_data: ?[]u8,
    key_data: ?[]u8,
    // Store the parsed CertKeyPair to reuse across handshakes
    cert_key_pair: ?tls.config.CertKeyPair,
    logger: *logger.Logger,

    pub fn init(allocator: std.mem.Allocator, cfg: TlsConfig, log: *logger.Logger) !TlsContext {
        var ctx = TlsContext{
            .allocator = allocator,
            .config = cfg,
            .cert_data = null,
            .key_data = null,
            .cert_key_pair = null,
            .logger = log,
        };

        if (cfg.enabled) {
            try ctx.loadCertificates();
            try ctx.loadCertKeyPair();
        }

        return ctx;
    }

    pub fn deinit(self: *TlsContext) void {
        if (self.cert_key_pair) |*ckp| {
            var mut_ckp = ckp.*;
            mut_ckp.deinit(self.allocator);
        }
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

    /// Validate certificates using the certificate validator
    pub fn validateCertificates(self: *TlsContext) !void {
        if (!self.config.validate_certificates) {
            self.logger.warn("Certificate validation disabled", .{});
            return;
        }

        if (self.cert_data) |cert| {
            // Basic PEM format check
            if (!std.mem.startsWith(u8, cert, "-----BEGIN CERTIFICATE-----")) {
                self.logger.err("Certificate does not appear to be in PEM format", .{});
                return error.InvalidCertificateFormat;
            }

            // Comprehensive validation using CertificateValidator
            var validator = cert_validator.CertificateValidator.init(self.allocator);
            validator.allow_self_signed = self.config.allow_self_signed;

            var result = validator.validateCertificate(cert) catch |err| {
                self.logger.err("Certificate validation failed: {}", .{err});
                return err;
            };
            defer result.deinit(self.allocator);

            // Log validation results
            if (!result.valid) {
                self.logger.err("Certificate validation failed:", .{});
                for (result.errors.items) |error_msg| {
                    self.logger.err("  - {s}", .{error_msg});
                }
                return error.InvalidCertificate;
            }

            // Log warnings
            if (result.warnings.items.len > 0) {
                self.logger.warn("Certificate validation warnings:", .{});
                for (result.warnings.items) |warning| {
                    self.logger.warn("  - {s}", .{warning});
                }
            }

            // Log certificate info
            if (result.subject_cn) |cn| {
                self.logger.info("Certificate subject: {s}", .{cn});
            }
            if (result.issuer_cn) |issuer| {
                self.logger.info("Certificate issuer: {s}", .{issuer});
            }
            if (result.self_signed) {
                self.logger.warn("Certificate is self-signed", .{});
            }
            if (result.expired) {
                self.logger.err("Certificate is expired", .{});
                return error.CertificateExpired;
            }
            if (result.not_yet_valid) {
                self.logger.err("Certificate is not yet valid", .{});
                return error.CertificateNotYetValid;
            }
            if (result.days_until_expiry) |days| {
                self.logger.info("Certificate expires in {d} days", .{days});
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

        self.logger.info("TLS certificates validated successfully", .{});
    }

    /// Load and parse the CertKeyPair for reuse across handshakes
    fn loadCertKeyPair(self: *TlsContext) !void {
        if (!self.config.enabled) return;

        const cert_path = self.config.cert_path orelse return error.TlsNotConfigured;
        const key_path = self.config.key_path orelse return error.TlsNotConfigured;

        self.logger.info("Loading TLS CertKeyPair...", .{});

        // Convert to absolute paths if needed
        var cert_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        var key_path_buf: [std.fs.max_path_bytes]u8 = undefined;

        const abs_cert_path = if (std.fs.path.isAbsolute(cert_path))
            cert_path
        else
            try std.fs.cwd().realpath(cert_path, &cert_path_buf);

        const abs_key_path = if (std.fs.path.isAbsolute(key_path))
            key_path
        else
            try std.fs.cwd().realpath(key_path, &key_path_buf);

        const cert_key = tls.config.CertKeyPair.fromFilePathAbsolute(
            self.allocator,
            abs_cert_path,
            abs_key_path,
        ) catch |err| {
            self.logger.err("Failed to load CertKeyPair: {}", .{err});
            return error.CertKeyPairLoadFailed;
        };

        self.cert_key_pair = cert_key;
        self.logger.info("CertKeyPair loaded successfully", .{});
    }
};

/// TLS connection wrapper
/// Note: Buffers are owned by caller (Session), not by TlsConnection
pub const TlsConnection = struct {
    conn: tls.Connection,

    pub fn deinit(self: *TlsConnection) void {
        self.conn.close() catch {};
        // Note: Buffers are freed by Session, not here
    }

    pub fn read(self: *TlsConnection, buffer: []u8) !usize {
        return self.conn.read(buffer);
    }

    pub fn write(self: *TlsConnection, data: []const u8) !usize {
        return self.conn.write(data);
    }
};

/// Upgrade a plain TCP connection to TLS using tls.zig library
/// Caller must provide pre-allocated buffers that will persist for the connection's lifetime
pub fn upgradeToTls(
    allocator: std.mem.Allocator,
    stream: net.Stream,
    ctx: *TlsContext,
    log: *logger.Logger,
    input_buf: []u8,
    output_buf: []u8,
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

    // Use caller-provided buffers that persist at session scope
    // These buffers MUST remain valid for the lifetime of the TLS connection

    // Create buffered reader/writer with the provided buffers
    var stream_reader = stream.reader(input_buf);
    var stream_writer = stream.writer(output_buf);

    // Get interface pointers (these point into stack-local reader/writer structs)
    const reader_iface = if (@hasField(@TypeOf(stream_reader), "interface"))
        &stream_reader.interface
    else
        stream_reader.interface();
    const writer_iface = &stream_writer.interface;

    // Perform TLS handshake
    // The handshake happens synchronously here, reading/writing through the interfaces
    const tls_conn = tls.server(reader_iface, writer_iface, .{
        .auth = &auth,
    }) catch |err| {
        log.err("TLS handshake failed: {}", .{err});
        return error.TlsHandshakeFailed;
    };

    log.info("TLS handshake successful", .{});

    return TlsConnection{
        .conn = tls_conn,
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
