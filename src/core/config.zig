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

    // Timeout configuration with granularity
    timeout_seconds: u32,           // General connection timeout
    data_timeout_seconds: u32,      // Specific timeout for DATA command
    command_timeout_seconds: u32,   // Timeout between commands
    greeting_timeout_seconds: u32,  // Timeout for initial greeting

    rate_limit_per_ip: u32,
    rate_limit_per_user: u32,
    rate_limit_cleanup_interval: u64,
    max_recipients: usize,
    hostname: []const u8,
    webhook_url: ?[]const u8,
    webhook_enabled: bool,
    enable_dnsbl: bool,
    enable_greylist: bool,
    enable_tracing: bool,
    tracing_service_name: []const u8,

    pub fn deinit(self: Config, allocator: std.mem.Allocator) void {
        allocator.free(self.tracing_service_name);
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
        .timeout_seconds = 300, // 5 minutes - general connection timeout
        .data_timeout_seconds = 600, // 10 minutes for DATA phase
        .command_timeout_seconds = 300, // 5 minutes between commands
        .greeting_timeout_seconds = 30, // 30 seconds for initial greeting
        .rate_limit_per_ip = 100, // messages per hour
        .rate_limit_per_user = 200, // messages per hour per authenticated user
        .rate_limit_cleanup_interval = 3600, // cleanup every hour
        .max_recipients = 100,
        .hostname = try allocator.dupe(u8, "localhost"),
        .webhook_url = null,
        .webhook_enabled = false,
        .enable_dnsbl = false, // Disabled by default for performance
        .enable_greylist = false, // Disabled by default
        .enable_tracing = false, // Disabled by default
        .tracing_service_name = try allocator.dupe(u8, "smtp-server"),
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

    // SMTP_TIMEOUT_SECONDS (connection timeout)
    if (std.posix.getenv("SMTP_TIMEOUT_SECONDS")) |value| {
        cfg.timeout_seconds = std.fmt.parseInt(u32, value, 10) catch cfg.timeout_seconds;
    }

    // SMTP_DATA_TIMEOUT_SECONDS (DATA command timeout)
    if (std.posix.getenv("SMTP_DATA_TIMEOUT_SECONDS")) |value| {
        cfg.data_timeout_seconds = std.fmt.parseInt(u32, value, 10) catch cfg.data_timeout_seconds;
    }

    // SMTP_COMMAND_TIMEOUT_SECONDS (timeout between commands)
    if (std.posix.getenv("SMTP_COMMAND_TIMEOUT_SECONDS")) |value| {
        cfg.command_timeout_seconds = std.fmt.parseInt(u32, value, 10) catch cfg.command_timeout_seconds;
    }

    // SMTP_GREETING_TIMEOUT_SECONDS (timeout for initial greeting)
    if (std.posix.getenv("SMTP_GREETING_TIMEOUT_SECONDS")) |value| {
        cfg.greeting_timeout_seconds = std.fmt.parseInt(u32, value, 10) catch cfg.greeting_timeout_seconds;
    }

    // SMTP_ENABLE_TLS
    if (std.posix.getenv("SMTP_ENABLE_TLS")) |value| {
        cfg.enable_tls = std.ascii.eqlIgnoreCase(value, "true") or std.ascii.eqlIgnoreCase(value, "1");
    }

    // SMTP_ENABLE_AUTH
    if (std.posix.getenv("SMTP_ENABLE_AUTH")) |value| {
        cfg.enable_auth = std.ascii.eqlIgnoreCase(value, "true") or std.ascii.eqlIgnoreCase(value, "1");
    }

    // SMTP_ENABLE_DNSBL
    if (std.posix.getenv("SMTP_ENABLE_DNSBL")) |value| {
        cfg.enable_dnsbl = std.ascii.eqlIgnoreCase(value, "true") or std.ascii.eqlIgnoreCase(value, "1");
    }

    // SMTP_ENABLE_GREYLIST
    if (std.posix.getenv("SMTP_ENABLE_GREYLIST")) |value| {
        cfg.enable_greylist = std.ascii.eqlIgnoreCase(value, "true") or std.ascii.eqlIgnoreCase(value, "1");
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

    // SMTP_RATE_LIMIT_PER_IP
    if (std.posix.getenv("SMTP_RATE_LIMIT_PER_IP")) |value| {
        cfg.rate_limit_per_ip = std.fmt.parseInt(u32, value, 10) catch cfg.rate_limit_per_ip;
    }

    // SMTP_RATE_LIMIT_PER_USER
    if (std.posix.getenv("SMTP_RATE_LIMIT_PER_USER")) |value| {
        cfg.rate_limit_per_user = std.fmt.parseInt(u32, value, 10) catch cfg.rate_limit_per_user;
    }

    // SMTP_RATE_LIMIT_CLEANUP_INTERVAL
    if (std.posix.getenv("SMTP_RATE_LIMIT_CLEANUP_INTERVAL")) |value| {
        cfg.rate_limit_cleanup_interval = std.fmt.parseInt(u64, value, 10) catch cfg.rate_limit_cleanup_interval;
    }

    // SMTP_ENABLE_TRACING
    if (std.posix.getenv("SMTP_ENABLE_TRACING")) |value| {
        cfg.enable_tracing = std.ascii.eqlIgnoreCase(value, "true") or std.ascii.eqlIgnoreCase(value, "1");
    }

    // SMTP_TRACING_SERVICE_NAME
    if (std.posix.getenv("SMTP_TRACING_SERVICE_NAME")) |value| {
        allocator.free(cfg.tracing_service_name);
        cfg.tracing_service_name = try allocator.dupe(u8, value);
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
