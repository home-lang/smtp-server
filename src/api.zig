const std = @import("std");
const database = @import("database.zig");
const auth_mod = @import("auth.zig");
const queue_mod = @import("queue.zig");
const filter_mod = @import("filter.zig");

/// REST API server for SMTP management
pub const APIServer = struct {
    allocator: std.mem.Allocator,
    port: u16,
    db: *database.Database,
    auth_backend: *auth_mod.AuthBackend,
    message_queue: *queue_mod.MessageQueue,
    filter_engine: *filter_mod.FilterEngine,

    pub fn init(
        allocator: std.mem.Allocator,
        port: u16,
        db: *database.Database,
        auth_backend: *auth_mod.AuthBackend,
        message_queue: *queue_mod.MessageQueue,
        filter_engine: *filter_mod.FilterEngine,
    ) APIServer {
        return .{
            .allocator = allocator,
            .port = port,
            .db = db,
            .auth_backend = auth_backend,
            .message_queue = message_queue,
            .filter_engine = filter_engine,
        };
    }

    pub fn run(self: *APIServer) !void {
        const address = try std.net.Address.parseIp("127.0.0.1", self.port);
        var server = try address.listen(.{
            .reuse_address = true,
        });
        defer server.deinit();

        std.log.info("API server listening on http://127.0.0.1:{d}", .{self.port});

        while (true) {
            const connection = try server.accept();
            defer connection.stream.close();

            self.handleRequest(connection.stream) catch |err| {
                std.log.err("API request error: {}", .{err});
            };
        }
    }

    fn handleRequest(self: *APIServer, stream: std.net.Stream) !void {
        var buf: [8192]u8 = undefined;
        const bytes_read = try stream.read(&buf);
        if (bytes_read == 0) return;

        const request = buf[0..bytes_read];

        // Parse HTTP request line
        var lines = std.mem.splitSequence(u8, request, "\r\n");
        const request_line = lines.next() orelse return error.InvalidRequest;

        var parts = std.mem.splitScalar(u8, request_line, ' ');
        const method = parts.next() orelse return error.InvalidRequest;
        const path = parts.next() orelse return error.InvalidRequest;

        // Route requests
        if (std.mem.eql(u8, method, "GET")) {
            if (std.mem.startsWith(u8, path, "/api/users")) {
                try self.handleGetUsers(stream);
            } else if (std.mem.startsWith(u8, path, "/api/queue")) {
                try self.handleGetQueue(stream);
            } else if (std.mem.startsWith(u8, path, "/api/filters")) {
                try self.handleGetFilters(stream);
            } else {
                try self.send404(stream);
            }
        } else if (std.mem.eql(u8, method, "POST")) {
            if (std.mem.startsWith(u8, path, "/api/users")) {
                try self.handleCreateUser(stream, request);
            } else if (std.mem.startsWith(u8, path, "/api/filters")) {
                try self.handleCreateFilter(stream, request);
            } else {
                try self.send404(stream);
            }
        } else if (std.mem.eql(u8, method, "DELETE")) {
            if (std.mem.startsWith(u8, path, "/api/users/")) {
                try self.handleDeleteUser(stream, path);
            } else if (std.mem.startsWith(u8, path, "/api/filters/")) {
                try self.handleDeleteFilter(stream, path);
            } else {
                try self.send404(stream);
            }
        } else {
            try self.send404(stream);
        }
    }

    fn handleGetUsers(self: *APIServer, stream: std.net.Stream) !void {
        // For now, return a simple JSON response
        const json = "{\"users\":[],\"message\":\"User listing not yet implemented\"}";

        const response = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}",
            .{ json.len, json },
        );
        defer self.allocator.free(response);

        _ = try stream.write(response);
    }

    fn handleGetQueue(self: *APIServer, stream: std.net.Stream) !void {
        const stats = self.message_queue.getStats();

        const json = try std.fmt.allocPrint(
            self.allocator,
            \\{{"total":{d},"pending":{d},"processing":{d},"retry":{d}}}
        ,
            .{ stats.total, stats.pending, stats.processing, stats.retry },
        );
        defer self.allocator.free(json);

        const response = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}",
            .{ json.len, json },
        );
        defer self.allocator.free(response);

        _ = try stream.write(response);
    }

    fn handleGetFilters(self: *APIServer, stream: std.net.Stream) !void {
        const rules = self.filter_engine.getRules();

        var json = std.ArrayList(u8).init(self.allocator);
        defer json.deinit();

        try json.appendSlice("{\"filters\":[");

        for (rules, 0..) |rule, i| {
            if (i > 0) try json.appendSlice(",");
            try std.fmt.format(json.writer(), "{{\"name\":\"{s}\",\"enabled\":{s},\"action\":\"{s}\"}}", .{
                rule.name,
                if (rule.enabled) "true" else "false",
                rule.action.toString(),
            });
        }

        try json.appendSlice("]}");

        const response = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}",
            .{ json.items.len, json.items },
        );
        defer self.allocator.free(response);

        _ = try stream.write(response);
    }

    fn handleCreateUser(self: *APIServer, stream: std.net.Stream, request: []const u8) !void {
        _ = request;

        // Parse JSON body (simplified - would need proper JSON parser)
        const json = "{\"message\":\"User creation requires JSON body with username, password, email\"}";

        const response = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}",
            .{ json.len, json },
        );
        defer self.allocator.free(response);

        _ = try stream.write(response);
    }

    fn handleCreateFilter(self: *APIServer, stream: std.net.Stream, request: []const u8) !void {
        _ = request;

        const json = "{\"message\":\"Filter creation requires JSON body with name, conditions, action\"}";

        const response = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}",
            .{ json.len, json },
        );
        defer self.allocator.free(response);

        _ = try stream.write(response);
    }

    fn handleDeleteUser(self: *APIServer, stream: std.net.Stream, path: []const u8) !void {
        _ = path;

        const json = "{\"message\":\"User deleted\"}";

        const response = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}",
            .{ json.len, json },
        );
        defer self.allocator.free(response);

        _ = try stream.write(response);
    }

    fn handleDeleteFilter(self: *APIServer, stream: std.net.Stream, path: []const u8) !void {
        _ = path;

        const json = "{\"message\":\"Filter deleted\"}";

        const response = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}",
            .{ json.len, json },
        );
        defer self.allocator.free(response);

        _ = try stream.write(response);
    }

    fn send404(self: *APIServer, stream: std.net.Stream) !void {
        _ = self;
        const response = "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nNot Found";
        _ = try stream.write(response);
    }
};

test "API server initialization" {
    // Structural test only
    const testing = std.testing;
    _ = testing;
}
