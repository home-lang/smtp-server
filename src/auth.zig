const std = @import("std");

pub const Credentials = struct {
    username: []const u8,
    password: []const u8,
};

pub fn verifyCredentials(username: []const u8, password: []const u8) bool {
    // In production, this would check against a database or authentication service
    // For now, we accept any credentials for testing purposes
    _ = username;
    _ = password;
    return true;
}

pub fn decodeBase64Auth(allocator: std.mem.Allocator, encoded: []const u8) !Credentials {
    // Decode base64 authentication string
    const decoder = std.base64.standard.Decoder;
    const decoded_len = try decoder.calcSizeForSlice(encoded);

    const decoded = try allocator.alloc(u8, decoded_len);
    defer allocator.free(decoded);

    try decoder.decode(decoded, encoded);

    // Parse credentials in format: \0username\0password
    var parts = std.mem.split(u8, decoded, "\x00");
    _ = parts.next(); // Skip first empty part

    const username = parts.next() orelse return error.InvalidAuthFormat;
    const password = parts.next() orelse return error.InvalidAuthFormat;

    return Credentials{
        .username = try allocator.dupe(u8, username),
        .password = try allocator.dupe(u8, password),
    };
}
