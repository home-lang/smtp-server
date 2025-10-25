const std = @import("std");
const database = @import("../storage/database.zig");
const password_mod = @import("password.zig");

pub const Credentials = struct {
    username: []const u8,
    password: []const u8,
};

pub const AuthBackend = struct {
    db: *database.Database,
    password_hasher: password_mod.PasswordHasher,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, db: *database.Database) AuthBackend {
        return .{
            .db = db,
            .password_hasher = password_mod.PasswordHasher.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn verifyCredentials(self: *AuthBackend, username: []const u8, password: []const u8) !bool {
        // Get user from database
        var user = self.db.getUserByUsername(username) catch |err| {
            if (err == database.DatabaseError.NotFound) {
                // User not found - return false but don't leak this information
                return false;
            }
            return err;
        };
        defer user.deinit(self.allocator);

        // Check if user is enabled
        if (!user.enabled) {
            return false;
        }

        // Verify password
        return try self.password_hasher.verifyPassword(password, user.password_hash);
    }

    pub fn createUser(self: *AuthBackend, username: []const u8, password: []const u8, email: []const u8) !i64 {
        // Hash the password
        const password_hash = try self.password_hasher.hashPassword(password);
        defer self.allocator.free(password_hash);

        // Create user in database
        return try self.db.createUser(username, password_hash, email);
    }

    pub fn changePassword(self: *AuthBackend, username: []const u8, new_password: []const u8) !void {
        // Hash the new password
        const password_hash = try self.password_hasher.hashPassword(new_password);
        defer self.allocator.free(password_hash);

        // Update in database
        try self.db.updateUserPassword(username, password_hash);
    }

    /// Verify HTTP Basic Auth header and return username if valid
    /// Format: "Basic <base64(username:password)>"
    pub fn verifyBasicAuth(self: *AuthBackend, auth_header: []const u8) !?[]const u8 {
        // Check for "Basic " prefix
        if (!std.mem.startsWith(u8, auth_header, "Basic ")) {
            return null;
        }

        // Extract base64 part
        const encoded = std.mem.trimLeft(u8, auth_header[6..], " ");

        // Decode credentials
        const creds = try decodeBasicAuthCredentials(self.allocator, encoded);
        defer {
            self.allocator.free(creds.username);
            self.allocator.free(creds.password);
        }

        // Verify credentials
        const valid = try self.verifyCredentials(creds.username, creds.password);
        if (!valid) {
            return null;
        }

        // Return username
        return try self.allocator.dupe(u8, creds.username);
    }
};

/// Decode SASL PLAIN base64 authentication (SMTP/IMAP/POP3)
/// Format: base64(\0username\0password)
pub fn decodeBase64Auth(allocator: std.mem.Allocator, encoded: []const u8) !Credentials {
    // Decode base64 authentication string
    const decoder = std.base64.standard.Decoder;
    const decoded_len = try decoder.calcSizeForSlice(encoded);

    const decoded = try allocator.alloc(u8, decoded_len);
    defer allocator.free(decoded);

    try decoder.decode(decoded, encoded);

    // Parse credentials in format: \0username\0password
    var parts = std.mem.splitSequence(u8, decoded, "\x00");
    _ = parts.next(); // Skip first empty part

    const username = parts.next() orelse return error.InvalidAuthFormat;
    const password = parts.next() orelse return error.InvalidAuthFormat;

    return Credentials{
        .username = try allocator.dupe(u8, username),
        .password = try allocator.dupe(u8, password),
    };
}

/// Decode HTTP Basic Auth credentials
/// Format: base64(username:password)
pub fn decodeBasicAuthCredentials(allocator: std.mem.Allocator, encoded: []const u8) !Credentials {
    // Decode base64 string
    const decoder = std.base64.standard.Decoder;
    const decoded_len = try decoder.calcSizeForSlice(encoded);

    const decoded = try allocator.alloc(u8, decoded_len);
    defer allocator.free(decoded);

    try decoder.decode(decoded, encoded);

    // Parse credentials in format: username:password
    const colon_pos = std.mem.indexOf(u8, decoded, ":") orelse return error.InvalidAuthFormat;
    const username = decoded[0..colon_pos];
    const password = decoded[colon_pos + 1 ..];

    return Credentials{
        .username = try allocator.dupe(u8, username),
        .password = try allocator.dupe(u8, password),
    };
}
