const std = @import("std");

pub const RateLimiter = struct {
    allocator: std.mem.Allocator,
    ip_counters: std.StringHashMap(RateCounter),
    window_seconds: u64,
    max_requests: u32,
    mutex: std.Thread.Mutex,

    const RateCounter = struct {
        count: u32,
        window_start: i64,
        last_request: i64,
    };

    pub fn init(allocator: std.mem.Allocator, window_seconds: u64, max_requests: u32) RateLimiter {
        return RateLimiter{
            .allocator = allocator,
            .ip_counters = std.StringHashMap(RateCounter).init(allocator),
            .window_seconds = window_seconds,
            .max_requests = max_requests,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *RateLimiter) void {
        var it = self.ip_counters.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.ip_counters.deinit();
    }

    pub fn checkAndIncrement(self: *RateLimiter, ip: []const u8) !bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.timestamp();

        if (self.ip_counters.get(ip)) |counter| {
            const elapsed = now - counter.window_start;

            if (elapsed >= self.window_seconds) {
                // Reset window
                try self.ip_counters.put(ip, RateCounter{
                    .count = 1,
                    .window_start = now,
                    .last_request = now,
                });
                return true;
            } else if (counter.count >= self.max_requests) {
                // Rate limit exceeded
                return false;
            } else {
                // Increment counter
                try self.ip_counters.put(ip, RateCounter{
                    .count = counter.count + 1,
                    .window_start = counter.window_start,
                    .last_request = now,
                });
                return true;
            }
        } else {
            // New IP
            const ip_copy = try self.allocator.dupe(u8, ip);
            try self.ip_counters.put(ip_copy, RateCounter{
                .count = 1,
                .window_start = now,
                .last_request = now,
            });
            return true;
        }
    }

    pub fn getRemainingRequests(self: *RateLimiter, ip: []const u8) u32 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.timestamp();

        if (self.ip_counters.get(ip)) |counter| {
            const elapsed = now - counter.window_start;

            if (elapsed >= self.window_seconds) {
                return self.max_requests;
            } else if (counter.count >= self.max_requests) {
                return 0;
            } else {
                return self.max_requests - counter.count;
            }
        }

        return self.max_requests;
    }

    pub fn cleanup(self: *RateLimiter) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.timestamp();
        var to_remove = std.ArrayList([]const u8){};
        defer to_remove.deinit(self.allocator);

        var it = self.ip_counters.iterator();
        while (it.next()) |entry| {
            const elapsed = now - entry.value_ptr.last_request;
            // Remove entries that haven't been accessed in 2x the window time
            if (elapsed >= self.window_seconds * 2) {
                to_remove.append(self.allocator, entry.key_ptr.*) catch continue;
            }
        }

        for (to_remove.items) |key| {
            _ = self.ip_counters.remove(key);
            self.allocator.free(key);
        }
    }

    pub fn getStats(self: *RateLimiter) struct { tracked_ips: usize, total_requests: u64 } {
        self.mutex.lock();
        defer self.mutex.unlock();

        var total: u64 = 0;
        var it = self.ip_counters.valueIterator();
        while (it.next()) |counter| {
            total += counter.count;
        }

        return .{
            .tracked_ips = self.ip_counters.count(),
            .total_requests = total,
        };
    }
};

pub fn validateEmailAddress(email: []const u8) bool {
    // Basic email validation
    if (email.len == 0 or email.len > 254) return false;

    const at_pos = std.mem.indexOf(u8, email, "@") orelse return false;

    if (at_pos == 0 or at_pos == email.len - 1) return false;

    const local_part = email[0..at_pos];
    const domain_part = email[at_pos + 1 ..];

    if (local_part.len == 0 or local_part.len > 64) return false;
    if (domain_part.len == 0 or domain_part.len > 255) return false;

    // Check for valid domain (must have at least one dot)
    if (std.mem.indexOf(u8, domain_part, ".") == null) return false;

    return true;
}

pub fn sanitizeInput(input: []const u8) bool {
    // Check for common injection patterns
    if (std.mem.indexOf(u8, input, "\x00") != null) return false; // Null bytes
    if (std.mem.indexOf(u8, input, "\r\n\r\n") != null) return false; // Header injection

    return true;
}

pub fn isValidHostname(hostname: []const u8) bool {
    if (hostname.len == 0 or hostname.len > 255) return false;

    // Check for valid characters
    for (hostname) |c| {
        const valid = (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or
            c == '.' or c == '-';

        if (!valid) return false;
    }

    return true;
}
