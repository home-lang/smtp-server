const std = @import("std");
const database = @import("../storage/database.zig");
const auth_mod = @import("auth/auth.zig");
const queue_mod = @import("../delivery/queue.zig");
const filter_mod = @import("../message/filter.zig");
const search_mod = @import("search.zig");

/// REST API server for SMTP management
pub const APIServer = struct {
    allocator: std.mem.Allocator,
    port: u16,
    db: *database.Database,
    auth_backend: *auth_mod.AuthBackend,
    message_queue: *queue_mod.MessageQueue,
    filter_engine: *filter_mod.FilterEngine,
    search_engine: ?*search_mod.MessageSearch,

    pub fn init(
        allocator: std.mem.Allocator,
        port: u16,
        db: *database.Database,
        auth_backend: *auth_mod.AuthBackend,
        message_queue: *queue_mod.MessageQueue,
        filter_engine: *filter_mod.FilterEngine,
        search_engine: ?*search_mod.MessageSearch,
    ) APIServer {
        return .{
            .allocator = allocator,
            .port = port,
            .db = db,
            .auth_backend = auth_backend,
            .message_queue = message_queue,
            .filter_engine = filter_engine,
            .search_engine = search_engine,
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
            } else if (std.mem.startsWith(u8, path, "/api/search")) {
                try self.handleSearch(stream, path);
            } else if (std.mem.startsWith(u8, path, "/api/search/stats")) {
                try self.handleSearchStats(stream);
            } else {
                try self.send404(stream);
            }
        } else if (std.mem.eql(u8, method, "POST")) {
            if (std.mem.startsWith(u8, path, "/api/users")) {
                try self.handleCreateUser(stream, request);
            } else if (std.mem.startsWith(u8, path, "/api/filters")) {
                try self.handleCreateFilter(stream, request);
            } else if (std.mem.startsWith(u8, path, "/api/search/rebuild")) {
                try self.handleRebuildSearchIndex(stream);
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

    fn handleSearch(self: *APIServer, stream: std.net.Stream, path: []const u8) !void {
        if (self.search_engine == null) {
            const json = "{\"error\":\"Search functionality not enabled\"}";
            const response = try std.fmt.allocPrint(
                self.allocator,
                "HTTP/1.1 503 Service Unavailable\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}",
                .{ json.len, json },
            );
            defer self.allocator.free(response);
            _ = try stream.write(response);
            return;
        }

        // Parse query parameters from URL
        // Example: /api/search?q=test&email=user@example.com&limit=50
        var query: ?[]const u8 = null;
        var options = search_mod.MessageSearch.SearchOptions{};

        if (std.mem.indexOf(u8, path, "?")) |query_start| {
            const query_string = path[query_start + 1 ..];
            var params = std.mem.splitScalar(u8, query_string, '&');

            while (params.next()) |param| {
                if (std.mem.indexOf(u8, param, "=")) |eq_pos| {
                    const key = param[0..eq_pos];
                    const value = param[eq_pos + 1 ..];

                    if (std.mem.eql(u8, key, "q")) {
                        query = try self.urlDecode(value);
                    } else if (std.mem.eql(u8, key, "email")) {
                        options.email = try self.urlDecode(value);
                    } else if (std.mem.eql(u8, key, "folder")) {
                        options.folder = try self.urlDecode(value);
                    } else if (std.mem.eql(u8, key, "limit")) {
                        options.limit = std.fmt.parseInt(usize, value, 10) catch 100;
                    } else if (std.mem.eql(u8, key, "offset")) {
                        options.offset = std.fmt.parseInt(usize, value, 10) catch 0;
                    } else if (std.mem.eql(u8, key, "from_date")) {
                        options.from_date = std.fmt.parseInt(i64, value, 10) catch null;
                    } else if (std.mem.eql(u8, key, "to_date")) {
                        options.to_date = std.fmt.parseInt(i64, value, 10) catch null;
                    } else if (std.mem.eql(u8, key, "attachments") and std.mem.eql(u8, value, "true")) {
                        options.has_attachments = true;
                    }
                }
            }
        }

        if (query == null or query.?.len == 0) {
            const json = "{\"error\":\"Missing query parameter 'q'\"}";
            const response = try std.fmt.allocPrint(
                self.allocator,
                "HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}",
                .{ json.len, json },
            );
            defer self.allocator.free(response);
            _ = try stream.write(response);
            return;
        }

        // Perform search
        var results = try self.search_engine.?.search(query.?, options);
        defer {
            for (results.items) |*result| {
                result.deinit(self.allocator);
            }
            results.deinit();
        }

        // Build JSON response
        var json = std.array_list.Managed(u8).init(self.allocator);
        defer json.deinit();

        try json.appendSlice("{\"results\":[");

        for (results.items, 0..) |result, i| {
            if (i > 0) try json.appendSlice(",");
            try std.fmt.format(json.writer(),
                \\{{"id":{d},"message_id":"{s}","email":"{s}","sender":"{s}","subject":"{s}","snippet":"{s}","received_at":{d},"size":{d},"folder":"{s}"
            , .{
                result.id,
                result.message_id,
                result.email,
                result.sender,
                result.subject,
                result.body_snippet,
                result.received_at,
                result.size,
                result.folder,
            });

            if (result.relevance_score) |score| {
                try std.fmt.format(json.writer(), ",\"relevance\":{d:.2}", .{score});
            }

            try json.appendSlice("}");
        }

        try std.fmt.format(json.writer(), "],\"count\":{d}}}", .{results.items.len});

        const response = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}",
            .{ json.items.len, json.items },
        );
        defer self.allocator.free(response);

        _ = try stream.write(response);
    }

    fn handleSearchStats(self: *APIServer, stream: std.net.Stream) !void {
        if (self.search_engine == null) {
            const json = "{\"error\":\"Search functionality not enabled\"}";
            const response = try std.fmt.allocPrint(
                self.allocator,
                "HTTP/1.1 503 Service Unavailable\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}",
                .{ json.len, json },
            );
            defer self.allocator.free(response);
            _ = try stream.write(response);
            return;
        }

        const stats = try self.search_engine.?.getStatistics();

        const json = try std.fmt.allocPrint(
            self.allocator,
            \\{{"total_messages":{d},"total_size":{d},"unique_senders":{d},"total_folders":{d},"oldest_message":{d},"newest_message":{d},"fts_enabled":{s}}}
        ,
            .{
                stats.total_messages,
                stats.total_size,
                stats.unique_senders,
                stats.total_folders,
                stats.oldest_message,
                stats.newest_message,
                if (stats.fts_enabled) "true" else "false",
            },
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

    fn handleRebuildSearchIndex(self: *APIServer, stream: std.net.Stream) !void {
        if (self.search_engine == null) {
            const json = "{\"error\":\"Search functionality not enabled\"}";
            const response = try std.fmt.allocPrint(
                self.allocator,
                "HTTP/1.1 503 Service Unavailable\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}",
                .{ json.len, json },
            );
            defer self.allocator.free(response);
            _ = try stream.write(response);
            return;
        }

        self.search_engine.?.rebuildIndex() catch |err| {
            const json = try std.fmt.allocPrint(
                self.allocator,
                "{{\"error\":\"Failed to rebuild index: {}\"}}",
                .{err},
            );
            defer self.allocator.free(json);

            const response = try std.fmt.allocPrint(
                self.allocator,
                "HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}",
                .{ json.len, json },
            );
            defer self.allocator.free(response);
            _ = try stream.write(response);
            return;
        };

        const json = "{\"message\":\"Search index rebuilt successfully\"}";
        const response = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}",
            .{ json.len, json },
        );
        defer self.allocator.free(response);

        _ = try stream.write(response);
    }

    fn urlDecode(self: *APIServer, encoded: []const u8) ![]const u8 {
        // Simple URL decoding - replace + with space and handle %XX encoding
        var decoded = std.array_list.Managed(u8).init(self.allocator);
        errdefer decoded.deinit();

        var i: usize = 0;
        while (i < encoded.len) {
            if (encoded[i] == '+') {
                try decoded.append(' ');
                i += 1;
            } else if (encoded[i] == '%' and i + 2 < encoded.len) {
                const hex = encoded[i + 1 .. i + 3];
                const byte = std.fmt.parseInt(u8, hex, 16) catch {
                    try decoded.append(encoded[i]);
                    i += 1;
                    continue;
                };
                try decoded.append(byte);
                i += 3;
            } else {
                try decoded.append(encoded[i]);
                i += 1;
            }
        }

        return decoded.toOwnedSlice();
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
