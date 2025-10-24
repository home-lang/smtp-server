const std = @import("std");
const smtp = @import("smtp.zig");
const config = @import("config.zig");
const logger = @import("logger.zig");
const args_parser = @import("args.zig");
const database = @import("database.zig");
const auth = @import("auth.zig");

// Global shutdown flag
var shutdown_requested = std.atomic.Value(bool).init(false);

fn signalHandler(sig: i32) callconv(.c) void {
    _ = sig;
    shutdown_requested.store(true, .release);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command-line arguments
    var cli_args = args_parser.parseArgs(allocator) catch |err| {
        if (err != error.UnknownArgument) {
            args_parser.printHelp();
        }
        return err;
    };
    defer cli_args.deinit(allocator);

    // Handle --help
    if (cli_args.help) {
        args_parser.printHelp();
        return;
    }

    // Handle --version
    if (cli_args.version) {
        args_parser.printVersion();
        return;
    }

    // Initialize logger with CLI overrides
    const log_level = cli_args.log_level orelse .info;
    const log_file = cli_args.log_file orelse "smtp-server.log";
    var log = try logger.Logger.init(allocator, log_level, log_file);
    defer log.deinit();
    logger.setGlobalLogger(&log);

    log.info("=== SMTP Server Starting ===", .{});

    // Load configuration (with CLI args and env vars)
    const cfg = try config.loadConfig(allocator, cli_args);
    defer cfg.deinit(allocator);

    log.info("Configuration loaded:", .{});
    log.info("  Host: {s}:{d}", .{ cfg.host, cfg.port });
    log.info("  Max connections: {d}", .{cfg.max_connections});
    log.info("  TLS enabled: {}", .{cfg.enable_tls});
    log.info("  Auth enabled: {}", .{cfg.enable_auth});
    log.info("  Max message size: {d} bytes", .{cfg.max_message_size});

    // Setup signal handlers for graceful shutdown
    const empty_set = std.posix.sigemptyset();

    const act = std.posix.Sigaction{
        .handler = .{ .handler = signalHandler },
        .mask = empty_set,
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &act, null);
    std.posix.sigaction(std.posix.SIG.TERM, &act, null);

    log.info("Signal handlers installed (SIGINT, SIGTERM)", .{});

    // Initialize database and auth backend if auth is enabled
    var db: ?database.Database = null;
    var auth_backend: ?auth.AuthBackend = null;
    var db_ptr: ?*database.Database = null;
    var auth_ptr: ?*auth.AuthBackend = null;

    if (cfg.enable_auth) {
        const db_path = std.posix.getenv("SMTP_DB_PATH") orelse "./smtp.db";
        log.info("Initializing database at: {s}", .{db_path});

        db = try database.Database.init(allocator, db_path);
        errdefer if (db) |*d| d.deinit();

        db_ptr = &db.?;
        auth_backend = auth.AuthBackend.init(allocator, db_ptr.?);
        auth_ptr = &auth_backend.?;

        log.info("Database-backed authentication enabled", .{});
    } else {
        log.info("Authentication disabled", .{});
    }

    defer if (db) |*d| d.deinit();

    // Create and start SMTP server
    var server = try smtp.Server.init(allocator, cfg, &log, db_ptr, auth_ptr);
    defer server.deinit();

    log.info("Starting SMTP server...", .{});

    server.start(&shutdown_requested) catch |err| {
        log.critical("Server error: {}", .{err});
        return err;
    };

    log.info("=== SMTP Server Shutdown Complete ===", .{});
}
