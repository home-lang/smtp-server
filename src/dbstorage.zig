const std = @import("std");
const database = @import("database.zig");

/// Database storage backend for email messages
/// Stores entire email messages in SQLite database
/// Provides fast indexing and querying capabilities
pub const DatabaseStorage = struct {
    allocator: std.mem.Allocator,
    db: *database.Database,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, db: *database.Database) !DatabaseStorage {
        var storage = DatabaseStorage{
            .allocator = allocator,
            .db = db,
            .mutex = .{},
        };

        // Initialize schema if not exists
        try storage.initSchema();

        return storage;
    }

    pub fn deinit(self: *DatabaseStorage) void {
        _ = self;
    }

    /// Initialize database schema for message storage
    fn initSchema(self: *DatabaseStorage) !void {
        const schema =
            \\CREATE TABLE IF NOT EXISTS messages (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    message_id TEXT UNIQUE NOT NULL,
            \\    email TEXT NOT NULL,
            \\    sender TEXT NOT NULL,
            \\    recipients TEXT NOT NULL,
            \\    subject TEXT,
            \\    body TEXT NOT NULL,
            \\    headers TEXT,
            \\    size INTEGER NOT NULL,
            \\    received_at INTEGER NOT NULL,
            \\    flags INTEGER DEFAULT 0,
            \\    folder TEXT DEFAULT 'INBOX'
            \\);
            \\
            \\CREATE INDEX IF NOT EXISTS idx_messages_email ON messages(email);
            \\CREATE INDEX IF NOT EXISTS idx_messages_message_id ON messages(message_id);
            \\CREATE INDEX IF NOT EXISTS idx_messages_received_at ON messages(received_at);
            \\CREATE INDEX IF NOT EXISTS idx_messages_folder ON messages(folder);
            \\CREATE INDEX IF NOT EXISTS idx_messages_flags ON messages(flags);
            \\
            \\CREATE TABLE IF NOT EXISTS attachments (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    message_id INTEGER NOT NULL,
            \\    filename TEXT NOT NULL,
            \\    content_type TEXT,
            \\    size INTEGER NOT NULL,
            \\    data BLOB NOT NULL,
            \\    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
            \\);
            \\
            \\CREATE INDEX IF NOT EXISTS idx_attachments_message_id ON attachments(message_id);
        ;

        try self.db.exec(schema);
    }

    /// Store a message in the database
    pub fn storeMessage(
        self: *DatabaseStorage,
        email: []const u8,
        message_id: []const u8,
        sender: []const u8,
        recipients: []const []const u8,
        subject: ?[]const u8,
        headers: []const u8,
        body: []const u8,
    ) !i64 {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Join recipients into comma-separated string
        var recipients_str = std.ArrayList(u8).init(self.allocator);
        defer recipients_str.deinit(self.allocator);

        for (recipients, 0..) |recipient, i| {
            try recipients_str.appendSlice(self.allocator, recipient);
            if (i < recipients.len - 1) {
                try recipients_str.append(self.allocator, ',');
            }
        }

        const size = body.len;
        const received_at = std.time.timestamp();

        const query =
            \\INSERT INTO messages (message_id, email, sender, recipients, subject, body, headers, size, received_at)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ;

        var stmt = try self.db.prepare(query);
        defer stmt.finalize();

        try stmt.bind(1, message_id);
        try stmt.bind(2, email);
        try stmt.bind(3, sender);
        try stmt.bind(4, recipients_str.items);
        try stmt.bind(5, subject orelse "");
        try stmt.bind(6, body);
        try stmt.bind(7, headers);
        try stmt.bind(8, @as(i64, @intCast(size)));
        try stmt.bind(9, received_at);

        try stmt.step();

        return self.db.lastInsertRowId();
    }

    /// Retrieve a message by ID
    pub fn retrieveMessage(
        self: *DatabaseStorage,
        email: []const u8,
        message_id: []const u8,
    ) !?StoredMessage {
        self.mutex.lock();
        defer self.mutex.unlock();

        const query =
            \\SELECT id, sender, recipients, subject, body, headers, size, received_at, flags, folder
            \\FROM messages
            \\WHERE email = ? AND message_id = ?
        ;

        var stmt = try self.db.prepare(query);
        defer stmt.finalize();

        try stmt.bind(1, email);
        try stmt.bind(2, message_id);

        if (try stmt.step()) {
            var message = StoredMessage{
                .id = try stmt.columnInt64(0),
                .message_id = try self.allocator.dupe(u8, message_id),
                .email = try self.allocator.dupe(u8, email),
                .sender = try self.allocator.dupe(u8, try stmt.columnText(1)),
                .recipients = try self.parseRecipients(try stmt.columnText(2)),
                .subject = blk: {
                    const subj = try stmt.columnText(3);
                    if (subj.len == 0) break :blk null;
                    break :blk try self.allocator.dupe(u8, subj);
                },
                .body = try self.allocator.dupe(u8, try stmt.columnText(4)),
                .headers = try self.allocator.dupe(u8, try stmt.columnText(5)),
                .size = @intCast(try stmt.columnInt64(6)),
                .received_at = try stmt.columnInt64(7),
                .flags = @intCast(try stmt.columnInt64(8)),
                .folder = try self.allocator.dupe(u8, try stmt.columnText(9)),
            };

            return message;
        }

        return null;
    }

    /// List messages for an email address
    pub fn listMessages(
        self: *DatabaseStorage,
        email: []const u8,
        folder: ?[]const u8,
        limit: usize,
        offset: usize,
    ) ![]StoredMessage {
        self.mutex.lock();
        defer self.mutex.unlock();

        const query = if (folder) |_|
            \\SELECT id, message_id, sender, recipients, subject, size, received_at, flags, folder
            \\FROM messages
            \\WHERE email = ? AND folder = ?
            \\ORDER BY received_at DESC
            \\LIMIT ? OFFSET ?
        else
            \\SELECT id, message_id, sender, recipients, subject, size, received_at, flags, folder
            \\FROM messages
            \\WHERE email = ?
            \\ORDER BY received_at DESC
            \\LIMIT ? OFFSET ?
        ;

        var stmt = try self.db.prepare(query);
        defer stmt.finalize();

        try stmt.bind(1, email);
        if (folder) |f| {
            try stmt.bind(2, f);
            try stmt.bind(3, @as(i64, @intCast(limit)));
            try stmt.bind(4, @as(i64, @intCast(offset)));
        } else {
            try stmt.bind(2, @as(i64, @intCast(limit)));
            try stmt.bind(3, @as(i64, @intCast(offset)));
        }

        var messages = std.ArrayList(StoredMessage).init(self.allocator);

        while (try stmt.step()) {
            const message = StoredMessage{
                .id = try stmt.columnInt64(0),
                .message_id = try self.allocator.dupe(u8, try stmt.columnText(1)),
                .email = try self.allocator.dupe(u8, email),
                .sender = try self.allocator.dupe(u8, try stmt.columnText(2)),
                .recipients = try self.parseRecipients(try stmt.columnText(3)),
                .subject = blk: {
                    const subj = try stmt.columnText(4);
                    if (subj.len == 0) break :blk null;
                    break :blk try self.allocator.dupe(u8, subj);
                },
                .body = "",
                .headers = "",
                .size = @intCast(try stmt.columnInt64(5)),
                .received_at = try stmt.columnInt64(6),
                .flags = @intCast(try stmt.columnInt64(7)),
                .folder = try self.allocator.dupe(u8, try stmt.columnText(8)),
            };

            try messages.append(self.allocator, message);
        }

        return try messages.toOwnedSlice(self.allocator);
    }

    /// Delete a message
    pub fn deleteMessage(
        self: *DatabaseStorage,
        email: []const u8,
        message_id: []const u8,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const query =
            \\DELETE FROM messages WHERE email = ? AND message_id = ?
        ;

        var stmt = try self.db.prepare(query);
        defer stmt.finalize();

        try stmt.bind(1, email);
        try stmt.bind(2, message_id);

        try stmt.step();
    }

    /// Move message to folder
    pub fn moveMessage(
        self: *DatabaseStorage,
        email: []const u8,
        message_id: []const u8,
        folder: []const u8,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const query =
            \\UPDATE messages SET folder = ? WHERE email = ? AND message_id = ?
        ;

        var stmt = try self.db.prepare(query);
        defer stmt.finalize();

        try stmt.bind(1, folder);
        try stmt.bind(2, email);
        try stmt.bind(3, message_id);

        try stmt.step();
    }

    /// Set message flags
    pub fn setFlags(
        self: *DatabaseStorage,
        email: []const u8,
        message_id: []const u8,
        flags: MessageFlags,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const query =
            \\UPDATE messages SET flags = ? WHERE email = ? AND message_id = ?
        ;

        var stmt = try self.db.prepare(query);
        defer stmt.finalize();

        try stmt.bind(1, @as(i64, @intCast(flags.toInt())));
        try stmt.bind(2, email);
        try stmt.bind(3, message_id);

        try stmt.step();
    }

    /// Get message count for an email
    pub fn getMessageCount(
        self: *DatabaseStorage,
        email: []const u8,
        folder: ?[]const u8,
    ) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        const query = if (folder) |_|
            \\SELECT COUNT(*) FROM messages WHERE email = ? AND folder = ?
        else
            \\SELECT COUNT(*) FROM messages WHERE email = ?
        ;

        var stmt = try self.db.prepare(query);
        defer stmt.finalize();

        try stmt.bind(1, email);
        if (folder) |f| {
            try stmt.bind(2, f);
        }

        if (try stmt.step()) {
            return @intCast(try stmt.columnInt64(0));
        }

        return 0;
    }

    /// Search messages
    pub fn searchMessages(
        self: *DatabaseStorage,
        email: []const u8,
        query_text: []const u8,
        limit: usize,
    ) ![]StoredMessage {
        self.mutex.lock();
        defer self.mutex.unlock();

        const query =
            \\SELECT id, message_id, sender, recipients, subject, size, received_at, flags, folder
            \\FROM messages
            \\WHERE email = ? AND (subject LIKE ? OR body LIKE ? OR sender LIKE ?)
            \\ORDER BY received_at DESC
            \\LIMIT ?
        ;

        var stmt = try self.db.prepare(query);
        defer stmt.finalize();

        const search_pattern = try std.fmt.allocPrint(self.allocator, "%{s}%", .{query_text});
        defer self.allocator.free(search_pattern);

        try stmt.bind(1, email);
        try stmt.bind(2, search_pattern);
        try stmt.bind(3, search_pattern);
        try stmt.bind(4, search_pattern);
        try stmt.bind(5, @as(i64, @intCast(limit)));

        var messages = std.ArrayList(StoredMessage).init(self.allocator);

        while (try stmt.step()) {
            const message = StoredMessage{
                .id = try stmt.columnInt64(0),
                .message_id = try self.allocator.dupe(u8, try stmt.columnText(1)),
                .email = try self.allocator.dupe(u8, email),
                .sender = try self.allocator.dupe(u8, try stmt.columnText(2)),
                .recipients = try self.parseRecipients(try stmt.columnText(3)),
                .subject = blk: {
                    const subj = try stmt.columnText(4);
                    if (subj.len == 0) break :blk null;
                    break :blk try self.allocator.dupe(u8, subj);
                },
                .body = "",
                .headers = "",
                .size = @intCast(try stmt.columnInt64(5)),
                .received_at = try stmt.columnInt64(6),
                .flags = @intCast(try stmt.columnInt64(7)),
                .folder = try self.allocator.dupe(u8, try stmt.columnText(8)),
            };

            try messages.append(self.allocator, message);
        }

        return try messages.toOwnedSlice(self.allocator);
    }

    /// Helper to parse recipients string
    fn parseRecipients(self: *DatabaseStorage, recipients_str: []const u8) ![][]const u8 {
        var recipients = std.ArrayList([]const u8).init(self.allocator);

        var iter = std.mem.splitScalar(u8, recipients_str, ',');
        while (iter.next()) |recipient| {
            try recipients.append(self.allocator, try self.allocator.dupe(u8, recipient));
        }

        return try recipients.toOwnedSlice(self.allocator);
    }
};

/// Stored message structure
pub const StoredMessage = struct {
    id: i64,
    message_id: []const u8,
    email: []const u8,
    sender: []const u8,
    recipients: [][]const u8,
    subject: ?[]const u8,
    body: []const u8,
    headers: []const u8,
    size: usize,
    received_at: i64,
    flags: u32,
    folder: []const u8,

    pub fn deinit(self: *StoredMessage, allocator: std.mem.Allocator) void {
        allocator.free(self.message_id);
        allocator.free(self.email);
        allocator.free(self.sender);
        for (self.recipients) |recipient| {
            allocator.free(recipient);
        }
        allocator.free(self.recipients);
        if (self.subject) |subj| {
            allocator.free(subj);
        }
        allocator.free(self.body);
        allocator.free(self.headers);
        allocator.free(self.folder);
    }
};

/// Message flags (IMAP-style)
pub const MessageFlags = struct {
    seen: bool = false,
    answered: bool = false,
    flagged: bool = false,
    deleted: bool = false,
    draft: bool = false,

    pub fn toInt(self: MessageFlags) u32 {
        var flags: u32 = 0;
        if (self.seen) flags |= 0x01;
        if (self.answered) flags |= 0x02;
        if (self.flagged) flags |= 0x04;
        if (self.deleted) flags |= 0x08;
        if (self.draft) flags |= 0x10;
        return flags;
    }

    pub fn fromInt(flags: u32) MessageFlags {
        return .{
            .seen = (flags & 0x01) != 0,
            .answered = (flags & 0x02) != 0,
            .flagged = (flags & 0x04) != 0,
            .deleted = (flags & 0x08) != 0,
            .draft = (flags & 0x10) != 0,
        };
    }
};

test "database storage initialization" {
    const testing = std.testing;

    var db = try database.Database.init(testing.allocator, ":memory:");
    defer db.deinit();
    try db.initSchema();

    var storage = try DatabaseStorage.init(testing.allocator, &db);
    defer storage.deinit();

    // Schema should be created
    try testing.expect(true);
}

test "store and retrieve message" {
    const testing = std.testing;

    var db = try database.Database.init(testing.allocator, ":memory:");
    defer db.deinit();
    try db.initSchema();

    var storage = try DatabaseStorage.init(testing.allocator, &db);
    defer storage.deinit();

    const recipients = [_][]const u8{"recipient@example.com"};
    const msg_id = try storage.storeMessage(
        "user@example.com",
        "msg-12345",
        "sender@example.com",
        &recipients,
        "Test Subject",
        "From: sender@example.com\r\n",
        "Test message body",
    );

    try testing.expect(msg_id > 0);

    // Retrieve the message
    const message = try storage.retrieveMessage("user@example.com", "msg-12345");
    try testing.expect(message != null);

    if (message) |msg| {
        var msg_copy = msg;
        defer msg_copy.deinit(testing.allocator);

        try testing.expectEqualStrings("sender@example.com", msg.sender);
        try testing.expectEqualStrings("Test Subject", msg.subject.?);
        try testing.expectEqualStrings("Test message body", msg.body);
    }
}

test "message flags" {
    const testing = std.testing;

    const flags = MessageFlags{
        .seen = true,
        .flagged = true,
    };

    const flags_int = flags.toInt();
    try testing.expectEqual(@as(u32, 0x05), flags_int);

    const restored = MessageFlags.fromInt(flags_int);
    try testing.expect(restored.seen);
    try testing.expect(restored.flagged);
    try testing.expect(!restored.answered);
}

test "list messages" {
    const testing = std.testing;

    var db = try database.Database.init(testing.allocator, ":memory:");
    defer db.deinit();
    try db.initSchema();

    var storage = try DatabaseStorage.init(testing.allocator, &db);
    defer storage.deinit();

    // Store multiple messages
    const recipients = [_][]const u8{"recipient@example.com"};
    _ = try storage.storeMessage("user@example.com", "msg-1", "sender1@example.com", &recipients, "Subject 1", "", "Body 1");
    _ = try storage.storeMessage("user@example.com", "msg-2", "sender2@example.com", &recipients, "Subject 2", "", "Body 2");

    const messages = try storage.listMessages("user@example.com", null, 10, 0);
    defer {
        for (messages) |*msg| {
            msg.deinit(testing.allocator);
        }
        testing.allocator.free(messages);
    }

    try testing.expectEqual(@as(usize, 2), messages.len);
}

test "delete message" {
    const testing = std.testing;

    var db = try database.Database.init(testing.allocator, ":memory:");
    defer db.deinit();
    try db.initSchema();

    var storage = try DatabaseStorage.init(testing.allocator, &db);
    defer storage.deinit();

    const recipients = [_][]const u8{"recipient@example.com"};
    _ = try storage.storeMessage("user@example.com", "msg-delete", "sender@example.com", &recipients, "Delete Me", "", "Body");

    try storage.deleteMessage("user@example.com", "msg-delete");

    const message = try storage.retrieveMessage("user@example.com", "msg-delete");
    try testing.expect(message == null);
}

test "message count" {
    const testing = std.testing;

    var db = try database.Database.init(testing.allocator, ":memory:");
    defer db.deinit();
    try db.initSchema();

    var storage = try DatabaseStorage.init(testing.allocator, &db);
    defer storage.deinit();

    const recipients = [_][]const u8{"recipient@example.com"};
    _ = try storage.storeMessage("user@example.com", "msg-count-1", "sender@example.com", &recipients, "Subject", "", "Body");
    _ = try storage.storeMessage("user@example.com", "msg-count-2", "sender@example.com", &recipients, "Subject", "", "Body");

    const count = try storage.getMessageCount("user@example.com", null);
    try testing.expectEqual(@as(usize, 2), count);
}
