const std = @import("std");

/// Queue message status
pub const MessageStatus = enum {
    pending,
    processing,
    delivered,
    failed,
    retry,

    pub fn toString(self: MessageStatus) []const u8 {
        return switch (self) {
            .pending => "pending",
            .processing => "processing",
            .delivered => "delivered",
            .failed => "failed",
            .retry => "retry",
        };
    }
};

/// Queued message
pub const QueuedMessage = struct {
    id: []const u8,
    from: []const u8,
    to: []const u8,
    data: []const u8,
    status: MessageStatus,
    attempts: u32,
    max_attempts: u32,
    next_retry: i64, // Unix timestamp
    created_at: i64,
    updated_at: i64,
    error_message: ?[]const u8,

    pub fn deinit(self: *QueuedMessage, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.from);
        allocator.free(self.to);
        allocator.free(self.data);
        if (self.error_message) |err| {
            allocator.free(err);
        }
    }
};

/// Message queue for outbound delivery
pub const MessageQueue = struct {
    allocator: std.mem.Allocator,
    messages: std.ArrayList(*QueuedMessage),
    mutex: std.Thread.Mutex,
    next_id: u64,

    pub fn init(allocator: std.mem.Allocator) MessageQueue {
        return .{
            .allocator = allocator,
            .messages = std.ArrayList(*QueuedMessage).init(allocator),
            .mutex = .{},
            .next_id = 1,
        };
    }

    pub fn deinit(self: *MessageQueue) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.messages.items) |msg| {
            msg.deinit(self.allocator);
            self.allocator.destroy(msg);
        }
        self.messages.deinit();
    }

    /// Enqueue a new message for delivery
    pub fn enqueue(
        self: *MessageQueue,
        from: []const u8,
        to: []const u8,
        data: []const u8,
    ) ![]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const id = try std.fmt.allocPrint(self.allocator, "{d}", .{self.next_id});
        self.next_id += 1;

        const msg = try self.allocator.create(QueuedMessage);
        errdefer self.allocator.destroy(msg);

        const now = std.time.timestamp();

        msg.* = .{
            .id = id,
            .from = try self.allocator.dupe(u8, from),
            .to = try self.allocator.dupe(u8, to),
            .data = try self.allocator.dupe(u8, data),
            .status = .pending,
            .attempts = 0,
            .max_attempts = 5,
            .next_retry = now,
            .created_at = now,
            .updated_at = now,
            .error_message = null,
        };

        try self.messages.append(msg);
        return id;
    }

    /// Get next message ready for delivery
    pub fn getNextPending(self: *MessageQueue) ?*QueuedMessage {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.timestamp();

        for (self.messages.items) |msg| {
            if ((msg.status == .pending or msg.status == .retry) and msg.next_retry <= now) {
                msg.status = .processing;
                msg.attempts += 1;
                msg.updated_at = now;
                return msg;
            }
        }

        return null;
    }

    /// Mark message as delivered
    pub fn markDelivered(self: *MessageQueue, id: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.messages.items, 0..) |msg, i| {
            if (std.mem.eql(u8, msg.id, id)) {
                msg.status = .delivered;
                msg.updated_at = std.time.timestamp();

                // Remove from queue after successful delivery
                _ = self.messages.swapRemove(i);
                msg.deinit(self.allocator);
                self.allocator.destroy(msg);
                return;
            }
        }

        return error.MessageNotFound;
    }

    /// Mark message as failed for retry
    pub fn markForRetry(self: *MessageQueue, id: []const u8, error_msg: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.messages.items, 0..) |msg, i| {
            if (std.mem.eql(u8, msg.id, id)) {
                const now = std.time.timestamp();

                if (msg.attempts >= msg.max_attempts) {
                    // Permanent failure
                    msg.status = .failed;
                    msg.updated_at = now;
                    if (msg.error_message) |old| self.allocator.free(old);
                    msg.error_message = try self.allocator.dupe(u8, error_msg);

                    // Remove from active queue
                    _ = self.messages.swapRemove(i);
                    msg.deinit(self.allocator);
                    self.allocator.destroy(msg);
                } else {
                    // Schedule retry with exponential backoff
                    const backoff_seconds: i64 = @as(i64, @intCast(std.math.pow(u32, 2, msg.attempts))) * 60; // 2^n minutes
                    msg.status = .retry;
                    msg.next_retry = now + backoff_seconds;
                    msg.updated_at = now;
                    if (msg.error_message) |old| self.allocator.free(old);
                    msg.error_message = try self.allocator.dupe(u8, error_msg);
                }

                return;
            }
        }

        return error.MessageNotFound;
    }

    /// Get queue statistics
    pub fn getStats(self: *MessageQueue) QueueStats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var stats = QueueStats{
            .total = self.messages.items.len,
            .pending = 0,
            .processing = 0,
            .retry = 0,
        };

        for (self.messages.items) |msg| {
            switch (msg.status) {
                .pending => stats.pending += 1,
                .processing => stats.processing += 1,
                .retry => stats.retry += 1,
                else => {},
            }
        }

        return stats;
    }

    /// Get all messages (for debugging/admin)
    pub fn listMessages(self: *MessageQueue, allocator: std.mem.Allocator) ![]QueuedMessage {
        self.mutex.lock();
        defer self.mutex.unlock();

        var list = try allocator.alloc(QueuedMessage, self.messages.items.len);
        for (self.messages.items, 0..) |msg, i| {
            list[i] = .{
                .id = try allocator.dupe(u8, msg.id),
                .from = try allocator.dupe(u8, msg.from),
                .to = try allocator.dupe(u8, msg.to),
                .data = try allocator.dupe(u8, msg.data),
                .status = msg.status,
                .attempts = msg.attempts,
                .max_attempts = msg.max_attempts,
                .next_retry = msg.next_retry,
                .created_at = msg.created_at,
                .updated_at = msg.updated_at,
                .error_message = if (msg.error_message) |err| try allocator.dupe(u8, err) else null,
            };
        }

        return list;
    }
};

pub const QueueStats = struct {
    total: usize,
    pending: usize,
    processing: usize,
    retry: usize,
};

test "message queue basic operations" {
    const testing = std.testing;
    var queue = MessageQueue.init(testing.allocator);
    defer queue.deinit();

    // Enqueue message
    const id = try queue.enqueue("sender@example.com", "recipient@example.com", "Test message");
    try testing.expect(id.len > 0);

    // Get next pending
    const msg = queue.getNextPending().?;
    try testing.expectEqualStrings("sender@example.com", msg.from);
    try testing.expect(msg.status == .processing);

    // Mark as delivered
    try queue.markDelivered(id);

    // Queue should be empty now
    try testing.expectEqual(@as(usize, 0), queue.messages.items.len);
}

test "message queue retry logic" {
    const testing = std.testing;
    var queue = MessageQueue.init(testing.allocator);
    defer queue.deinit();

    const id = try queue.enqueue("sender@example.com", "recipient@example.com", "Test message");

    _ = queue.getNextPending().?;
    try queue.markForRetry(id, "Connection failed");

    const stats = queue.getStats();
    try testing.expectEqual(@as(usize, 1), stats.retry);
}
