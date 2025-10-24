const std = @import("std");
const smtp = @import("smtp.zig");
const config = @import("config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load configuration
    const cfg = try config.loadConfig(allocator);
    defer cfg.deinit(allocator);

    std.debug.print("Starting SMTP Server on {s}:{d}\n", .{ cfg.host, cfg.port });
    std.debug.print("Max connections: {d}\n", .{cfg.max_connections});
    std.debug.print("TLS enabled: {}\n", .{cfg.enable_tls});

    // Create and start SMTP server
    var server = try smtp.Server.init(allocator, cfg);
    defer server.deinit();

    try server.start();
}
