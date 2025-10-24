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

pub const Logger = struct {
    allocator: std.mem.Allocator,
    min_level: LogLevel,
    use_colors: bool,
    log_file: ?std.fs.File,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, min_level: LogLevel, log_file_path: ?[]const u8) !Logger {
        var log_file: ?std.fs.File = null;

        if (log_file_path) |path| {
            log_file = try std.fs.cwd().createFile(path, .{
                .truncate = false,
                .read = false,
            });
            try log_file.?.seekFromEnd(0);
        }

        return Logger{
            .allocator = allocator,
            .min_level = min_level,
            .use_colors = true,
            .log_file = log_file,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *Logger) void {
        if (self.log_file) |file| {
            file.close();
        }
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

        // Create log entry
        var log_buf: [8192]u8 = undefined;
        const log_entry = std.fmt.bufPrint(&log_buf, "[{d}] [{s}] {s}\n", .{
            timestamp,
            level.toString(),
            message,
        }) catch return;

        // Write to stderr with colors
        if (self.use_colors) {
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
var global_logger: ?*Logger = null;

pub fn setGlobalLogger(logger: *Logger) void {
    global_logger = logger;
}

pub fn getGlobalLogger() ?*Logger {
    return global_logger;
}

// Convenience functions for global logging
pub fn debug(comptime fmt: []const u8, args: anytype) void {
    if (global_logger) |logger| {
        logger.debug(fmt, args);
    }
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    if (global_logger) |logger| {
        logger.info(fmt, args);
    }
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    if (global_logger) |logger| {
        logger.warn(fmt, args);
    }
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    if (global_logger) |logger| {
        logger.err(fmt, args);
    }
}

pub fn critical(comptime fmt: []const u8, args: anytype) void {
    if (global_logger) |logger| {
        logger.critical(fmt, args);
    }
}
