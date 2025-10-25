const std = @import("std");

/// Server statistics with thread-safe atomic counters
pub const ServerStats = struct {
    uptime_seconds: i64,
    total_connections: std.atomic.Value(u64),
    active_connections: std.atomic.Value(u32),
    messages_received: std.atomic.Value(u64),
    messages_rejected: std.atomic.Value(u64),
    auth_successes: std.atomic.Value(u64),
    auth_failures: std.atomic.Value(u64),
    rate_limit_hits: std.atomic.Value(u64),
    dnsbl_blocks: std.atomic.Value(u64),
    greylist_blocks: std.atomic.Value(u64),

    pub fn init() ServerStats {
        return .{
            .uptime_seconds = 0,
            .total_connections = std.atomic.Value(u64).init(0),
            .active_connections = std.atomic.Value(u32).init(0),
            .messages_received = std.atomic.Value(u64).init(0),
            .messages_rejected = std.atomic.Value(u64).init(0),
            .auth_successes = std.atomic.Value(u64).init(0),
            .auth_failures = std.atomic.Value(u64).init(0),
            .rate_limit_hits = std.atomic.Value(u64).init(0),
            .dnsbl_blocks = std.atomic.Value(u64).init(0),
            .greylist_blocks = std.atomic.Value(u64).init(0),
        };
    }

    pub fn incrementTotalConnections(self: *ServerStats) void {
        _ = self.total_connections.fetchAdd(1, .monotonic);
    }

    pub fn incrementActiveConnections(self: *ServerStats) void {
        _ = self.active_connections.fetchAdd(1, .monotonic);
    }

    pub fn decrementActiveConnections(self: *ServerStats) void {
        _ = self.active_connections.fetchSub(1, .monotonic);
    }

    pub fn incrementMessagesReceived(self: *ServerStats) void {
        _ = self.messages_received.fetchAdd(1, .monotonic);
    }

    pub fn incrementMessagesRejected(self: *ServerStats) void {
        _ = self.messages_rejected.fetchAdd(1, .monotonic);
    }

    pub fn incrementAuthSuccesses(self: *ServerStats) void {
        _ = self.auth_successes.fetchAdd(1, .monotonic);
    }

    pub fn incrementAuthFailures(self: *ServerStats) void {
        _ = self.auth_failures.fetchAdd(1, .monotonic);
    }

    pub fn incrementRateLimitHits(self: *ServerStats) void {
        _ = self.rate_limit_hits.fetchAdd(1, .monotonic);
    }

    pub fn incrementDnsblBlocks(self: *ServerStats) void {
        _ = self.dnsbl_blocks.fetchAdd(1, .monotonic);
    }

    pub fn incrementGreylistBlocks(self: *ServerStats) void {
        _ = self.greylist_blocks.fetchAdd(1, .monotonic);
    }

    pub fn toJson(self: *const ServerStats, allocator: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(
            allocator,
            \\{{"uptime_seconds":{d},"total_connections":{d},"active_connections":{d},"messages_received":{d},"messages_rejected":{d},"auth_successes":{d},"auth_failures":{d},"rate_limit_hits":{d},"dnsbl_blocks":{d},"greylist_blocks":{d}}}
        ,
            .{
                self.uptime_seconds,
                self.total_connections.load(.monotonic),
                self.active_connections.load(.monotonic),
                self.messages_received.load(.monotonic),
                self.messages_rejected.load(.monotonic),
                self.auth_successes.load(.monotonic),
                self.auth_failures.load(.monotonic),
                self.rate_limit_hits.load(.monotonic),
                self.dnsbl_blocks.load(.monotonic),
                self.greylist_blocks.load(.monotonic),
            },
        );
    }
};

/// Health status
pub const HealthStatus = enum {
    healthy,
    degraded,
    unhealthy,

    pub fn toString(self: HealthStatus) []const u8 {
        return switch (self) {
            .healthy => "healthy",
            .degraded => "degraded",
            .unhealthy => "unhealthy",
        };
    }
};

/// Dependency status
pub const DependencyStatus = struct {
    name: []const u8,
    healthy: bool,
    response_time_ms: ?f64,
    error_message: ?[]const u8,
};

/// Health check result with dependency monitoring
pub const HealthCheck = struct {
    status: HealthStatus,
    uptime_seconds: i64,
    active_connections: u32,
    max_connections: usize,
    memory_usage_mb: ?f64,
    checks: std.StringHashMap(bool),
    dependencies: std.ArrayList(DependencyStatus),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) HealthCheck {
        return .{
            .status = .healthy,
            .uptime_seconds = 0,
            .active_connections = 0,
            .max_connections = 0,
            .memory_usage_mb = null,
            .checks = std.StringHashMap(bool).init(allocator),
            .dependencies = std.ArrayList(DependencyStatus).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HealthCheck) void {
        var it = self.checks.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.checks.deinit();

        for (self.dependencies.items) |dep| {
            if (dep.error_message) |err| {
                self.allocator.free(err);
            }
        }
        self.dependencies.deinit();
    }

    /// Add dependency status
    pub fn addDependency(self: *HealthCheck, name: []const u8, healthy: bool, response_time_ms: ?f64, error_message: ?[]const u8) !void {
        const error_copy = if (error_message) |err| try self.allocator.dupe(u8, err) else null;

        try self.dependencies.append(.{
            .name = name,
            .healthy = healthy,
            .response_time_ms = response_time_ms,
            .error_message = error_copy,
        });

        // Update overall health status based on dependencies
        if (!healthy) {
            if (self.status == .healthy) {
                self.status = .degraded;
            }
        }
    }

    pub fn toJson(self: *HealthCheck) ![]const u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        defer buf.deinit();

        try buf.appendSlice("{\"status\":\"");
        try buf.appendSlice(self.status.toString());
        try buf.appendSlice("\",\"uptime_seconds\":");
        try std.fmt.format(buf.writer(), "{d}", .{self.uptime_seconds});
        try buf.appendSlice(",\"active_connections\":");
        try std.fmt.format(buf.writer(), "{d}", .{self.active_connections});
        try buf.appendSlice(",\"max_connections\":");
        try std.fmt.format(buf.writer(), "{d}", .{self.max_connections});

        if (self.memory_usage_mb) |mem| {
            try buf.appendSlice(",\"memory_usage_mb\":");
            try std.fmt.format(buf.writer(), "{d:.2}", .{mem});
        }

        try buf.appendSlice(",\"checks\":{");
        var first = true;
        var it = self.checks.iterator();
        while (it.next()) |entry| {
            if (!first) try buf.appendSlice(",");
            first = false;
            try buf.appendSlice("\"");
            try buf.appendSlice(entry.key_ptr.*);
            try buf.appendSlice("\":");
            try buf.appendSlice(if (entry.value_ptr.*) "true" else "false");
        }
        try buf.appendSlice("}");

        // Add dependencies
        if (self.dependencies.items.len > 0) {
            try buf.appendSlice(",\"dependencies\":[");
            for (self.dependencies.items, 0..) |dep, i| {
                if (i > 0) try buf.appendSlice(",");
                try buf.appendSlice("{\"name\":\"");
                try buf.appendSlice(dep.name);
                try buf.appendSlice("\",\"healthy\":");
                try buf.appendSlice(if (dep.healthy) "true" else "false");

                if (dep.response_time_ms) |rt| {
                    try buf.appendSlice(",\"response_time_ms\":");
                    try std.fmt.format(buf.writer(), "{d:.2}", .{rt});
                }

                if (dep.error_message) |err| {
                    try buf.appendSlice(",\"error\":\"");
                    // Escape JSON special characters
                    for (err) |c| {
                        if (c == '"') {
                            try buf.appendSlice("\\\"");
                        } else if (c == '\\') {
                            try buf.appendSlice("\\\\");
                        } else if (c == '\n') {
                            try buf.appendSlice("\\n");
                        } else {
                            try buf.append(c);
                        }
                    }
                    try buf.appendSlice("\"");
                }

                try buf.appendSlice("}");
            }
            try buf.appendSlice("]");
        }

        try buf.appendSlice("}");

        return try buf.toOwnedSlice();
    }
};

/// Simple HTTP health check server
pub const HealthServer = struct {
    allocator: std.mem.Allocator,
    port: u16,
    stats_provider: *const fn () ServerStats,
    start_time: i64,
    active_connections: *const std.atomic.Value(u32),
    max_connections: usize,

    pub fn init(
        allocator: std.mem.Allocator,
        port: u16,
        stats_provider: *const fn () ServerStats,
        active_connections: *const std.atomic.Value(u32),
        max_connections: usize,
    ) HealthServer {
        return .{
            .allocator = allocator,
            .port = port,
            .stats_provider = stats_provider,
            .start_time = std.time.timestamp(),
            .active_connections = active_connections,
            .max_connections = max_connections,
        };
    }

    pub fn run(self: *HealthServer) !void {
        const address = try std.net.Address.parseIp("127.0.0.1", self.port);
        var server = try address.listen(.{
            .reuse_address = true,
        });
        defer server.deinit();

        std.log.info("Health check server listening on http://127.0.0.1:{d}", .{self.port});

        while (true) {
            const connection = try server.accept();
            defer connection.stream.close();

            self.handleRequest(connection.stream) catch |err| {
                std.log.err("Health check request error: {}", .{err});
            };
        }
    }

    fn handleRequest(self: *HealthServer, stream: std.net.Stream) !void {
        var buf: [4096]u8 = undefined;
        const bytes_read = try stream.read(&buf);
        if (bytes_read == 0) return;

        const request = buf[0..bytes_read];

        // Simple HTTP request parsing
        if (std.mem.startsWith(u8, request, "GET /health")) {
            try self.handleHealth(stream);
        } else if (std.mem.startsWith(u8, request, "GET /stats")) {
            try self.handleStats(stream);
        } else if (std.mem.startsWith(u8, request, "GET /metrics")) {
            try self.handleMetrics(stream);
        } else {
            try self.send404(stream);
        }
    }

    fn handleHealth(self: *HealthServer, stream: std.net.Stream) !void {
        var health = HealthCheck.init(self.allocator);
        defer health.deinit();

        const now = std.time.timestamp();
        health.uptime_seconds = now - self.start_time;
        health.active_connections = self.active_connections.load(.monotonic);
        health.max_connections = self.max_connections;

        // Determine health status
        const connection_ratio = @as(f64, @floatFromInt(health.active_connections)) / @as(f64, @floatFromInt(self.max_connections));
        if (connection_ratio > 0.9) {
            health.status = .degraded;
        } else if (connection_ratio >= 1.0) {
            health.status = .unhealthy;
        } else {
            health.status = .healthy;
        }

        // Add checks
        try health.checks.put(try self.allocator.dupe(u8, "smtp_server"), health.status == .healthy);
        try health.checks.put(try self.allocator.dupe(u8, "connections_available"), connection_ratio < 1.0);

        const json = try health.toJson();
        defer self.allocator.free(json);

        const response = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}",
            .{ json.len, json },
        );
        defer self.allocator.free(response);

        _ = try stream.write(response);
    }

    fn handleStats(self: *HealthServer, stream: std.net.Stream) !void {
        const stats = self.stats_provider();
        const json = try stats.toJson(self.allocator);
        defer self.allocator.free(json);

        const response = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n{s}",
            .{ json.len, json },
        );
        defer self.allocator.free(response);

        _ = try stream.write(response);
    }

    fn handleMetrics(self: *HealthServer, stream: std.net.Stream) !void {
        const stats = self.stats_provider();

        const metrics = try std.fmt.allocPrint(
            self.allocator,
            \\# HELP smtp_uptime_seconds Server uptime in seconds
            \\# TYPE smtp_uptime_seconds gauge
            \\smtp_uptime_seconds {d}
            \\# HELP smtp_connections_total Total number of connections
            \\# TYPE smtp_connections_total counter
            \\smtp_connections_total {d}
            \\# HELP smtp_connections_active Currently active connections
            \\# TYPE smtp_connections_active gauge
            \\smtp_connections_active {d}
            \\# HELP smtp_messages_received_total Total messages received
            \\# TYPE smtp_messages_received_total counter
            \\smtp_messages_received_total {d}
            \\# HELP smtp_messages_rejected_total Total messages rejected
            \\# TYPE smtp_messages_rejected_total counter
            \\smtp_messages_rejected_total {d}
            \\# HELP smtp_auth_successes_total Total successful authentications
            \\# TYPE smtp_auth_successes_total counter
            \\smtp_auth_successes_total {d}
            \\# HELP smtp_auth_failures_total Total failed authentications
            \\# TYPE smtp_auth_failures_total counter
            \\smtp_auth_failures_total {d}
            \\# HELP smtp_rate_limit_hits_total Total rate limit hits
            \\# TYPE smtp_rate_limit_hits_total counter
            \\smtp_rate_limit_hits_total {d}
            \\# HELP smtp_dnsbl_blocks_total Total DNSBL blocks
            \\# TYPE smtp_dnsbl_blocks_total counter
            \\smtp_dnsbl_blocks_total {d}
            \\# HELP smtp_greylist_blocks_total Total greylist blocks
            \\# TYPE smtp_greylist_blocks_total counter
            \\smtp_greylist_blocks_total {d}
            \\
        ,
            .{
                stats.uptime_seconds,
                stats.total_connections,
                stats.active_connections,
                stats.messages_received,
                stats.messages_rejected,
                stats.auth_successes,
                stats.auth_failures,
                stats.rate_limit_hits,
                stats.dnsbl_blocks,
                stats.greylist_blocks,
            },
        );
        defer self.allocator.free(metrics);

        const response = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 200 OK\r\nContent-Type: text/plain; version=0.0.4\r\nContent-Length: {d}\r\n\r\n{s}",
            .{ metrics.len, metrics },
        );
        defer self.allocator.free(response);

        _ = try stream.write(response);
    }

    fn send404(self: *HealthServer, stream: std.net.Stream) !void {
        _ = self;
        const response = "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nNot Found";
        _ = try stream.write(response);
    }
};

test "server stats to JSON" {
    const testing = std.testing;

    const stats = ServerStats{
        .uptime_seconds = 3600,
        .total_connections = 100,
        .active_connections = 5,
        .messages_received = 50,
        .messages_rejected = 2,
        .auth_successes = 48,
        .auth_failures = 2,
        .rate_limit_hits = 1,
        .dnsbl_blocks = 1,
        .greylist_blocks = 0,
    };

    const json = try stats.toJson(testing.allocator);
    defer testing.allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "\"uptime_seconds\":3600") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"total_connections\":100") != null);
}

test "health check to JSON" {
    const testing = std.testing;

    var health = HealthCheck.init(testing.allocator);
    defer health.deinit();

    health.status = .healthy;
    health.uptime_seconds = 100;
    health.active_connections = 5;
    health.max_connections = 100;

    try health.checks.put(try testing.allocator.dupe(u8, "test"), true);

    const json = try health.toJson();
    defer testing.allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "\"status\":\"healthy\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"uptime_seconds\":100") != null);
}
