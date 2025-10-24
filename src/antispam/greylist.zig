const std = @import("std");

/// Greylisting implementation for spam prevention
/// Temporarily rejects mail from unknown sender/recipient/IP triplets
/// Legitimate mail servers will retry, spam bots typically won't
pub const Greylist = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap(GreylistEntry),
    mutex: std.Thread.Mutex,

    // Greylisting parameters
    initial_delay: i64 = 300, // 5 minutes - initial block period
    retry_window: i64 = 14400, // 4 hours - window for retries
    auto_whitelist_after: i64 = 36 * 86400, // 36 days - permanent whitelist

    const GreylistEntry = struct {
        first_seen: i64,
        last_seen: i64,
        allowed: bool,
        retry_count: u32,
    };

    pub fn init(allocator: std.mem.Allocator) Greylist {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap(GreylistEntry).init(allocator),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Greylist) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var it = self.entries.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.entries.deinit();
    }

    /// Check if a mail triplet (IP, sender, recipient) should be allowed
    /// Returns true if allowed, false if should be temporarily rejected
    pub fn checkTriplet(
        self: *Greylist,
        ip_addr: []const u8,
        mail_from: []const u8,
        rcpt_to: []const u8,
    ) !bool {
        // Create triplet key
        const key = try std.fmt.allocPrint(
            self.allocator,
            "{s}|{s}|{s}",
            .{ ip_addr, mail_from, rcpt_to },
        );
        defer self.allocator.free(key);

        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.timestamp();

        if (self.entries.get(key)) |entry| {
            // Entry exists - check if it should be allowed
            const time_since_first = now - entry.first_seen;
            _ = now - entry.last_seen; // time_since_last not currently used

            if (entry.allowed) {
                // Already whitelisted - update last seen
                try self.updateEntry(key, entry, now);
                return true;
            }

            // Check if initial delay has passed
            if (time_since_first >= self.initial_delay) {
                // Delay has passed - allow and update
                var updated_entry = entry;
                updated_entry.allowed = true;
                updated_entry.retry_count += 1;
                updated_entry.last_seen = now;
                try self.updateEntry(key, updated_entry, now);
                return true;
            }

            // Still within initial delay - reject but update retry count
            var updated_entry = entry;
            updated_entry.retry_count += 1;
            updated_entry.last_seen = now;
            try self.updateEntry(key, updated_entry, now);
            return false;
        } else {
            // New triplet - add to greylist and reject
            const stored_key = try self.allocator.dupe(u8, key);
            try self.entries.put(stored_key, .{
                .first_seen = now,
                .last_seen = now,
                .allowed = false,
                .retry_count = 1,
            });
            return false;
        }
    }

    fn updateEntry(self: *Greylist, key: []const u8, entry: GreylistEntry, now: i64) !void {
        // Check if should be auto-whitelisted
        const time_since_first = now - entry.first_seen;
        var updated = entry;

        if (time_since_first >= self.auto_whitelist_after) {
            updated.allowed = true;
        }

        // Find the stored key
        var it = self.entries.iterator();
        while (it.next()) |kv| {
            if (std.mem.eql(u8, kv.key_ptr.*, key)) {
                kv.value_ptr.* = updated;
                return;
            }
        }
    }

    /// Clean up old entries to prevent memory growth
    pub fn cleanup(self: *Greylist) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.timestamp();
        const cutoff = now - self.auto_whitelist_after - self.retry_window;

        var to_remove = std.ArrayList([]const u8).init(self.allocator);
        defer to_remove.deinit();

        // Find entries to remove
        var it = self.entries.iterator();
        while (it.next()) |kv| {
            if (kv.value_ptr.last_seen < cutoff) {
                try to_remove.append(kv.key_ptr.*);
            }
        }

        // Remove old entries
        for (to_remove.items) |key| {
            if (self.entries.fetchRemove(key)) |removed| {
                self.allocator.free(removed.key);
            }
        }
    }

    /// Get statistics about the greylist
    pub fn getStats(self: *Greylist) GreylistStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var stats = GreylistStats{
            .total_entries = 0,
            .allowed_entries = 0,
            .blocked_entries = 0,
        };

        var it = self.entries.valueIterator();
        while (it.next()) |entry| {
            stats.total_entries += 1;
            if (entry.allowed) {
                stats.allowed_entries += 1;
            } else {
                stats.blocked_entries += 1;
            }
        }

        return stats;
    }
};

pub const GreylistStats = struct {
    total_entries: usize,
    allowed_entries: usize,
    blocked_entries: usize,
};

test "greylisting basic flow" {
    const testing = std.testing;
    var greylist = Greylist.init(testing.allocator);
    defer greylist.deinit();

    // First attempt should be rejected
    const first = try greylist.checkTriplet("192.168.1.1", "sender@example.com", "recipient@example.com");
    try testing.expect(!first);

    // Immediate retry should still be rejected
    const second = try greylist.checkTriplet("192.168.1.1", "sender@example.com", "recipient@example.com");
    try testing.expect(!second);

    // Simulate time passage (we can't actually wait, so this tests the logic)
    // In production, the server would retry after the delay
}
