const std = @import("std");
const smtp = @import("smtp.zig");
const config = @import("config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout_file = std.io.getStdOut();
    const stdout = stdout_file.writer();

    // Load configuration
    const cfg = try config.loadConfig(allocator);
    defer cfg.deinit(allocator);

    try stdout.print("Starting SMTP Server on {s}:{d}\n", .{ cfg.host, cfg.port });
    try stdout.print("Max connections: {d}\n", .{cfg.max_connections});
    try stdout.print("TLS enabled: {}\n", .{cfg.enable_tls});

    // Create and start SMTP server
    var server = try smtp.Server.init(allocator, cfg);
    defer server.deinit();

    try server.start();
}
