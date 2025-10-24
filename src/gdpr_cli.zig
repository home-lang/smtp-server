const std = @import("std");
const gdpr = @import("gdpr.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
        return;
    }

    const command = args[1];

    // Get database path from environment or use default
    const db_path = std.process.getEnvVarOwned(allocator, "SMTP_DB_PATH") catch
        try allocator.dupe(u8, "smtp.db");
    defer allocator.free(db_path);

    var manager = try gdpr.GDPRManager.init(allocator, db_path);
    defer manager.deinit();

    if (std.mem.eql(u8, command, "export")) {
        try exportCommand(&manager, allocator, args);
    } else if (std.mem.eql(u8, command, "delete")) {
        try deleteCommand(&manager, allocator, args);
    } else if (std.mem.eql(u8, command, "log")) {
        try logCommand(&manager, allocator, args);
    } else {
        std.debug.print("Unknown command: {s}\n\n", .{command});
        try printUsage();
    }
}

fn printUsage() !void {
    std.debug.print(
        \\GDPR CLI - Data Protection Tool
        \\
        \\Usage: gdpr-cli <command> [options]
        \\
        \\Commands:
        \\  export <username> [output_file]  Export all user data to JSON
        \\  delete <username>                Delete all user data permanently
        \\  log <username> <action> <ip>     Log GDPR data access
        \\
        \\Environment Variables:
        \\  SMTP_DB_PATH  Path to SQLite database (default: smtp.db)
        \\
        \\Examples:
        \\  gdpr-cli export john john_data.json
        \\  gdpr-cli delete john
        \\  gdpr-cli log john "data_export" "192.168.1.100"
        \\
        \\GDPR Compliance:
        \\  - Article 15: Right to access (export command)
        \\  - Article 17: Right to erasure (delete command)
        \\  - Article 20: Data portability (JSON export)
        \\  - Article 30: Processing activities (log command)
        \\
        \\
    , .{});
}

fn exportCommand(manager: *gdpr.GDPRManager, allocator: std.mem.Allocator, args: [][:0]u8) !void {
    if (args.len < 3) {
        std.debug.print("Error: Missing username\n", .{});
        std.debug.print("Usage: gdpr-cli export <username> [output_file]\n", .{});
        return;
    }

    const username = args[2];
    const output_file = if (args.len >= 4) args[3] else null;

    std.debug.print("Exporting data for user: {s}\n", .{username});

    // Log the data export access
    try manager.logDataAccess(username, "GDPR_DATA_EXPORT", "127.0.0.1");

    // Export user data
    var export_data = manager.exportUserData(username) catch |err| {
        std.debug.print("Error exporting data: {}\n", .{err});
        return err;
    };
    defer export_data.deinit();

    std.debug.print("Export complete:\n", .{});
    std.debug.print("  User: {s}\n", .{export_data.data.personal_info.username});
    std.debug.print("  Email: {s}\n", .{export_data.data.personal_info.email});
    std.debug.print("  Messages: {d}\n", .{export_data.data.messages.len});
    std.debug.print("  Activity records: {d}\n", .{export_data.data.activity.len});
    std.debug.print("  Total size: {d} bytes\n", .{export_data.data.metadata.total_size_bytes});

    // Write to file or stdout
    if (output_file) |path| {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        var buffer = std.ArrayList(u8){};
        defer buffer.deinit(allocator);
        try export_data.toJSON(buffer.writer(allocator));
        try file.writeAll(buffer.items);

        std.debug.print("\nData exported to: {s}\n", .{path});
    } else {
        var buffer = std.ArrayList(u8){};
        defer buffer.deinit(allocator);

        try export_data.toJSON(buffer.writer(allocator));
        std.debug.print("\nJSON Output:\n{s}\n", .{buffer.items});
    }

    std.debug.print("\n✓ Export completed successfully\n", .{});
    std.debug.print("This export contains all personal data as required by GDPR Article 15.\n", .{});
}

fn deleteCommand(manager: *gdpr.GDPRManager, allocator: std.mem.Allocator, args: [][:0]u8) !void {
    _ = allocator;

    if (args.len < 3) {
        std.debug.print("Error: Missing username\n", .{});
        std.debug.print("Usage: gdpr-cli delete <username>\n", .{});
        return;
    }

    const username = args[2];

    std.debug.print("WARNING: Deleting ALL data for user: {s}\n", .{username});
    std.debug.print("This action cannot be undone!\n", .{});
    std.debug.print("\nDeleting user data...\n", .{});

    // Log the data deletion
    try manager.logDataAccess(username, "GDPR_DATA_DELETION", "127.0.0.1");

    // Delete user data
    manager.deleteUserData(username) catch |err| {
        std.debug.print("Error deleting data: {}\n", .{err});
        return err;
    };

    std.debug.print("\n✓ User data deleted successfully\n", .{});
    std.debug.print("All personal data has been permanently removed as required by GDPR Article 17.\n", .{});
}

fn logCommand(manager: *gdpr.GDPRManager, allocator: std.mem.Allocator, args: [][:0]u8) !void {
    _ = allocator;

    if (args.len < 5) {
        std.debug.print("Error: Missing arguments\n", .{});
        std.debug.print("Usage: gdpr-cli log <username> <action> <ip_address>\n", .{});
        return;
    }

    const username = args[2];
    const action = args[3];
    const ip_address = args[4];

    std.debug.print("Logging GDPR data access...\n", .{});
    std.debug.print("  User: {s}\n", .{username});
    std.debug.print("  Action: {s}\n", .{action});
    std.debug.print("  IP: {s}\n", .{ip_address});

    manager.logDataAccess(username, action, ip_address) catch |err| {
        std.debug.print("Error logging access: {}\n", .{err});
        return err;
    };

    std.debug.print("\n✓ Access logged successfully\n", .{});
    std.debug.print("This log entry will be retained as required by GDPR Article 30.\n", .{});
}
