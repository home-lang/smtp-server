const std = @import("std");
const net = std.net;
const config = @import("config.zig");
const auth = @import("auth.zig");
const protocol = @import("protocol.zig");

pub const Server = struct {
    allocator: std.mem.Allocator,
    config: config.Config,
    listener: ?net.Server,
    running: bool,

    pub fn init(allocator: std.mem.Allocator, cfg: config.Config) !Server {
        return Server{
            .allocator = allocator,
            .config = cfg,
            .listener = null,
            .running = false,
        };
    }

    pub fn deinit(self: *Server) void {
        if (self.listener) |*listener| {
            listener.deinit();
        }
    }

    pub fn start(self: *Server) !void {
        const address = try net.Address.parseIp(self.config.host, self.config.port);

        self.listener = try address.listen(.{
            .reuse_address = true,
            .reuse_port = true,
        });

        self.running = true;

        const stdout_file = std.io.getStdOut();
        const stdout = stdout_file.writer();
        try stdout.print("SMTP Server listening on {s}:{d}\n", .{ self.config.host, self.config.port });

        while (self.running) {
            const connection = try self.listener.?.accept();

            // Handle connection in a new thread for concurrent processing
            const thread = try std.Thread.spawn(.{}, handleConnection, .{ self, connection });
            thread.detach();
        }
    }

    fn handleConnection(self: *Server, connection: net.Server.Connection) void {
        defer connection.stream.close();

        var session = protocol.Session.init(self.allocator, connection, self.config) catch |err| {
            std.debug.print("Failed to initialize session: {}\n", .{err});
            return;
        };
        defer session.deinit();

        session.handle() catch |err| {
            std.debug.print("Session error: {}\n", .{err});
        };
    }
};
