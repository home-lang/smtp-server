const std = @import("std");

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
    hostname: []const u8,

    pub fn deinit(self: Config, allocator: std.mem.Allocator) void {
        allocator.free(self.host);
        allocator.free(self.hostname);
        if (self.tls_cert_path) |path| allocator.free(path);
        if (self.tls_key_path) |path| allocator.free(path);
    }
};

pub fn loadConfig(allocator: std.mem.Allocator) !Config {
    // For now, return default configuration
    // In production, you'd load this from a config file
    return Config{
        .host = try allocator.dupe(u8, "0.0.0.0"),
        .port = 2525, // Using non-privileged port for development
        .max_connections = 100,
        .enable_tls = false, // Set to true when you have certs
        .tls_cert_path = null,
        .tls_key_path = null,
        .enable_auth = true,
        .max_message_size = 10 * 1024 * 1024, // 10MB
        .timeout_seconds = 300, // 5 minutes
        .rate_limit_per_ip = 100, // messages per hour
        .hostname = try allocator.dupe(u8, "localhost"),
    };
}
