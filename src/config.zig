const std = @import("std");
const args = @import("args.zig");

pub const Config = struct {
    host: []const u8,
    port: u16,
    max_connections: usize,
    enable_tls: bool,
    tls_cert_path: ?[]const u8,
    tls_key_path: ?[]const u8,
    enable_auth: bool,
    max_message_size: usize,
    timeout_seconds: u32,
    rate_limit_per_ip: u32,
    max_recipients: usize,
    hostname: []const u8,
    webhook_url: ?[]const u8,
    webhook_enabled: bool,

    pub fn deinit(self: Config, allocator: std.mem.Allocator) void {
        allocator.free(self.host);
        allocator.free(self.hostname);
        if (self.tls_cert_path) |path| allocator.free(path);
        if (self.tls_key_path) |path| allocator.free(path);
        if (self.webhook_url) |url| allocator.free(url);
    }
};

pub fn loadConfig(allocator: std.mem.Allocator, cli_args: args.Args) !Config {
    var cfg = try loadDefaults(allocator);

    // Override with environment variables
    try applyEnvironmentVariables(allocator, &cfg);

    // Override with command-line arguments (highest priority)
    try applyCommandLineArgs(allocator, &cfg, cli_args);

    return cfg;
}

fn loadDefaults(allocator: std.mem.Allocator) !Config {
    return Config{
        .host = try allocator.dupe(u8, "0.0.0.0"),
        .port = 2525, // Using non-privileged port for development
        .max_connections = 100,
        .enable_tls = false,
        .tls_cert_path = null,
        .tls_key_path = null,
        .enable_auth = true,
        .max_message_size = 10 * 1024 * 1024, // 10MB
        .timeout_seconds = 300, // 5 minutes
        .rate_limit_per_ip = 100, // messages per hour
        .max_recipients = 100,
        .hostname = try allocator.dupe(u8, "localhost"),
        .webhook_url = null,
        .webhook_enabled = false,
    };
}

fn applyEnvironmentVariables(allocator: std.mem.Allocator, cfg: *Config) !void {
    // SMTP_HOST
    if (std.posix.getenv("SMTP_HOST")) |value| {
        allocator.free(cfg.host);
        cfg.host = try allocator.dupe(u8, value);
    }

    // SMTP_PORT
    if (std.posix.getenv("SMTP_PORT")) |value| {
        cfg.port = std.fmt.parseInt(u16, value, 10) catch cfg.port;
    }

    // SMTP_HOSTNAME
    if (std.posix.getenv("SMTP_HOSTNAME")) |value| {
        allocator.free(cfg.hostname);
        cfg.hostname = try allocator.dupe(u8, value);
    }

    // SMTP_MAX_CONNECTIONS
    if (std.posix.getenv("SMTP_MAX_CONNECTIONS")) |value| {
        cfg.max_connections = std.fmt.parseInt(usize, value, 10) catch cfg.max_connections;
    }

    // SMTP_MAX_MESSAGE_SIZE
    if (std.posix.getenv("SMTP_MAX_MESSAGE_SIZE")) |value| {
        cfg.max_message_size = std.fmt.parseInt(usize, value, 10) catch cfg.max_message_size;
    }

    // SMTP_MAX_RECIPIENTS
    if (std.posix.getenv("SMTP_MAX_RECIPIENTS")) |value| {
        cfg.max_recipients = std.fmt.parseInt(usize, value, 10) catch cfg.max_recipients;
    }

    // SMTP_ENABLE_TLS
    if (std.posix.getenv("SMTP_ENABLE_TLS")) |value| {
        cfg.enable_tls = std.ascii.eqlIgnoreCase(value, "true") or std.ascii.eqlIgnoreCase(value, "1");
    }

    // SMTP_ENABLE_AUTH
    if (std.posix.getenv("SMTP_ENABLE_AUTH")) |value| {
        cfg.enable_auth = std.ascii.eqlIgnoreCase(value, "true") or std.ascii.eqlIgnoreCase(value, "1");
    }

    // SMTP_TLS_CERT
    if (std.posix.getenv("SMTP_TLS_CERT")) |value| {
        if (cfg.tls_cert_path) |old| allocator.free(old);
        cfg.tls_cert_path = try allocator.dupe(u8, value);
    }

    // SMTP_TLS_KEY
    if (std.posix.getenv("SMTP_TLS_KEY")) |value| {
        if (cfg.tls_key_path) |old| allocator.free(old);
        cfg.tls_key_path = try allocator.dupe(u8, value);
    }

    // SMTP_WEBHOOK_URL
    if (std.posix.getenv("SMTP_WEBHOOK_URL")) |value| {
        if (cfg.webhook_url) |old| allocator.free(old);
        cfg.webhook_url = try allocator.dupe(u8, value);
        cfg.webhook_enabled = true;
    }

    // SMTP_WEBHOOK_ENABLED
    if (std.posix.getenv("SMTP_WEBHOOK_ENABLED")) |value| {
        cfg.webhook_enabled = std.ascii.eqlIgnoreCase(value, "true") or std.ascii.eqlIgnoreCase(value, "1");
    }
}

fn applyCommandLineArgs(allocator: std.mem.Allocator, cfg: *Config, cli_args: args.Args) !void {
    if (cli_args.host) |value| {
        allocator.free(cfg.host);
        cfg.host = try allocator.dupe(u8, value);
    }

    if (cli_args.port) |value| {
        cfg.port = value;
    }

    if (cli_args.max_connections) |value| {
        cfg.max_connections = value;
    }

    if (cli_args.enable_tls) |value| {
        cfg.enable_tls = value;
    }

    if (cli_args.enable_auth) |value| {
        cfg.enable_auth = value;
    }
}
