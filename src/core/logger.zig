const std = @import("std");

pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,
    critical,

    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
            .critical => "CRITICAL",
        };
    }

    pub fn toColor(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "\x1b[36m", // Cyan
            .info => "\x1b[32m", // Green
            .warn => "\x1b[33m", // Yellow
            .err => "\x1b[31m", // Red
            .critical => "\x1b[35m", // Magenta
        };
    }
};

pub const LogFormat = enum {
    text,
    json,
};

pub const Logger = struct {
    allocator: std.mem.Allocator,
    min_level: LogLevel,
    use_colors: bool,
    log_file: ?std.fs.File,
    mutex: std.Thread.Mutex,
    format: LogFormat,
    service_name: []const u8,
    hostname: []const u8,

    pub fn init(allocator: std.mem.Allocator, min_level: LogLevel, log_file_path: ?[]const u8) !Logger {
        var log_file: ?std.fs.File = null;

        if (log_file_path) |path| {
            log_file = try std.fs.cwd().createFile(path, .{
                .truncate = false,
                .read = false,
            });
            try log_file.?.seekFromEnd(0);
        }

        // Get hostname
        var hostname_buf: [256]u8 = undefined;
        const hostname = std.posix.gethostname(&hostname_buf) catch "unknown";

        return Logger{
            .allocator = allocator,
            .min_level = min_level,
            .use_colors = true,
            .log_file = log_file,
            .mutex = std.Thread.Mutex{},
            .format = .text, // Default to text format
            .service_name = try allocator.dupe(u8, "smtp-server"),
            .hostname = try allocator.dupe(u8, hostname),
        };
    }

    pub fn initWithFormat(allocator: std.mem.Allocator, min_level: LogLevel, log_file_path: ?[]const u8, format: LogFormat) !Logger {
        var logger = try init(allocator, min_level, log_file_path);
        logger.format = format;
        logger.use_colors = (format == .text); // Only use colors in text mode
        return logger;
    }

    pub fn deinit(self: *Logger) void {
        if (self.log_file) |file| {
            file.close();
        }
        self.allocator.free(self.service_name);
        self.allocator.free(self.hostname);
    }

    pub fn log(self: *Logger, level: LogLevel, comptime fmt: []const u8, args: anytype) void {
        if (@intFromEnum(level) < @intFromEnum(self.min_level)) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        const timestamp = std.time.timestamp();
        var buf: [8192]u8 = undefined;

        // Format the message
        const message = std.fmt.bufPrint(&buf, fmt, args) catch |format_err| {
            std.debug.print("Logger formatting error: {}\n", .{format_err});
            return;
        };

        var log_buf: [8192]u8 = undefined;
        const log_entry = switch (self.format) {
            .text => std.fmt.bufPrint(&log_buf, "[{d}] [{s}] {s}\n", .{
                timestamp,
                level.toString(),
                message,
            }) catch return,
            .json => self.formatJSON(&log_buf, timestamp, level, message, null) catch return,
        };

        // Write to stderr with colors (text mode only)
        if (self.use_colors and self.format == .text) {
            const colored = std.fmt.bufPrint(&buf, "{s}{s}\x1b[0m", .{
                level.toColor(),
                log_entry,
            }) catch return;
            _ = std.posix.write(std.posix.STDERR_FILENO, colored) catch {};
        } else {
            _ = std.posix.write(std.posix.STDERR_FILENO, log_entry) catch {};
        }

        // Write to file if configured
        if (self.log_file) |file| {
            _ = file.write(log_entry) catch {};
        }
    }

    /// Format log entry as JSON
    fn formatJSON(
        self: *Logger,
        buf: []u8,
        timestamp: i64,
        level: LogLevel,
        message: []const u8,
        fields: ?std.StringHashMap([]const u8),
    ) ![]const u8 {
        var stream = std.io.fixedBufferStream(buf);
        var writer = stream.writer();

        try writer.writeAll("{\"timestamp\":");
        try std.fmt.formatInt(timestamp, 10, .lower, .{}, writer);
        try writer.writeAll(",\"level\":\"");
        try writer.writeAll(level.toString());
        try writer.writeAll("\",\"service\":\"");
        try writer.writeAll(self.service_name);
        try writer.writeAll("\",\"hostname\":\"");
        try writer.writeAll(self.hostname);
        try writer.writeAll("\",\"message\":\"");
        try self.escapeJSON(writer, message);
        try writer.writeAll("\"");

        // Add custom fields if provided
        if (fields) |f| {
            var it = f.iterator();
            while (it.next()) |entry| {
                try writer.writeAll(",\"");
                try writer.writeAll(entry.key_ptr.*);
                try writer.writeAll("\":\"");
                try self.escapeJSON(writer, entry.value_ptr.*);
                try writer.writeAll("\"");
            }
        }

        try writer.writeAll("}\n");
        return stream.getWritten();
    }

    /// Escape special characters for JSON
    fn escapeJSON(self: *Logger, writer: anytype, str: []const u8) !void {
        _ = self;
        for (str) |c| {
            switch (c) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => if (c < 32) {
                    try writer.print("\\u{x:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                },
            }
        }
    }

    pub fn debug(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.debug, fmt, args);
    }

    pub fn info(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.info, fmt, args);
    }

    pub fn warn(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.warn, fmt, args);
    }

    pub fn err(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.err, fmt, args);
    }

    pub fn critical(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log(.critical, fmt, args);
    }

    // Specialized logging methods for SMTP operations
    pub fn logConnection(self: *Logger, remote_addr: []const u8, event: []const u8) void {
        self.info("Connection from {s}: {s}", .{ remote_addr, event });
    }

    pub fn logSmtpCommand(self: *Logger, remote_addr: []const u8, command: []const u8) void {
        self.debug("SMTP [{s}] -> {s}", .{ remote_addr, command });
    }

    pub fn logSmtpResponse(self: *Logger, remote_addr: []const u8, code: u16, message: []const u8) void {
        self.debug("SMTP [{s}] <- {d} {s}", .{ remote_addr, code, message });
    }

    pub fn logMessageReceived(self: *Logger, from: []const u8, to_count: usize, size: usize) void {
        self.info("Message received: FROM={s}, recipients={d}, size={d} bytes", .{ from, to_count, size });
    }

    pub fn logSecurityEvent(self: *Logger, remote_addr: []const u8, event: []const u8) void {
        self.warn("Security event from {s}: {s}", .{ remote_addr, event });
    }

    pub fn logError(self: *Logger, context: []const u8, error_msg: anytype) void {
        self.err("{s}: {any}", .{ context, error_msg });
    }
};

// Global logger instance (to be initialized in main)
// Using atomic value for thread-safe access
var global_logger: std.atomic.Value(?*Logger) = std.atomic.Value(?*Logger).init(null);

pub fn setGlobalLogger(logger: *Logger) void {
    global_logger.store(logger, .release);
}

pub fn getGlobalLogger() ?*Logger {
    return global_logger.load(.acquire);
}

// Convenience functions for global logging
pub fn debug(comptime fmt: []const u8, args: anytype) void {
    if (getGlobalLogger()) |logger| {
        logger.debug(fmt, args);
    }
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    if (getGlobalLogger()) |logger| {
        logger.info(fmt, args);
    }
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    if (getGlobalLogger()) |logger| {
        logger.warn(fmt, args);
    }
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    if (getGlobalLogger()) |logger| {
        logger.err(fmt, args);
    }
}

pub fn critical(comptime fmt: []const u8, args: anytype) void {
    if (getGlobalLogger()) |logger| {
        logger.critical(fmt, args);
    }
}
