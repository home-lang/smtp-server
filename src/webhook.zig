const std = @import("std");
const logger = @import("logger.zig");
const tls = @import("tls");

pub const WebhookConfig = struct {
    url: ?[]const u8,
    enabled: bool,
    timeout_ms: u32,
};

pub const WebhookPayload = struct {
    from: []const u8,
    recipients: []const []const u8,
    size: usize,
    timestamp: i64,
    remote_addr: []const u8,
};

pub fn sendWebhook(allocator: std.mem.Allocator, cfg: WebhookConfig, payload: WebhookPayload, log: *logger.Logger) !void {
    if (!cfg.enabled or cfg.url == null) {
        return;
    }

    const url = cfg.url.?;

    // Build JSON payload
    var json_buf = std.ArrayList(u8){};
    defer json_buf.deinit(allocator);

    const writer = json_buf.writer(allocator);

    try writer.writeAll("{");
    try writer.print("\"from\":\"{s}\",", .{payload.from});
    try writer.writeAll("\"recipients\":[");
    for (payload.recipients, 0..) |rcpt, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print("\"{s}\"", .{rcpt});
    }
    try writer.writeAll("],");
    try writer.print("\"size\":{d},", .{payload.size});
    try writer.print("\"timestamp\":{d},", .{payload.timestamp});
    try writer.print("\"remote_addr\":\"{s}\"", .{payload.remote_addr});
    try writer.writeAll("}");

    log.debug("Webhook payload: {s}", .{json_buf.items});

    // Parse URL
    const uri = std.Uri.parse(url) catch |err| {
        log.err("Invalid webhook URL: {s} - {}", .{ url, err });
        return error.InvalidWebhookUrl;
    };

    // Determine if HTTPS
    const use_tls_flag = std.mem.eql(u8, uri.scheme, "https");

    // Get host and port
    const host = uri.host.?.percent_encoded;
    const port: u16 = uri.port orelse if (use_tls_flag) 443 else 80;

    // Connect to webhook server
    var address: std.net.Address = undefined;

    // Try direct IP parsing first
    address = std.net.Address.parseIp(host, port) catch blk: {
        // Try DNS resolution
        const address_list = try std.net.getAddressList(allocator, host, port);
        defer address_list.deinit();

        if (address_list.addrs.len == 0) {
            log.err("Could not resolve webhook host: {s}", .{host});
            return error.WebhookHostNotFound;
        }

        break :blk address_list.addrs[0];
    };

    const stream = std.net.tcpConnectToAddress(address) catch |err| {
        log.err("Failed to connect to webhook: {s}:{d} - {}", .{ host, port, err });
        return error.WebhookConnectionFailed;
    };
    defer stream.close();

    // Build HTTP request
    var request_buf: [4096]u8 = undefined;
    const path = if (uri.path.percent_encoded.len > 0) uri.path.percent_encoded else "/";

    const request = try std.fmt.bufPrint(&request_buf,
        "POST {s} HTTP/1.1\r\n" ++
        "Host: {s}\r\n" ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: {d}\r\n" ++
        "User-Agent: SMTP-Server-Zig/1.0\r\n" ++
        "Connection: close\r\n" ++
        "\r\n" ++
        "{s}",
        .{ path, host, json_buf.items.len, json_buf.items },
    );

    if (use_tls_flag) {
        // HTTPS request
        try sendHttpsRequest(allocator, stream, request, host, url, log);
    } else {
        // HTTP request
        try sendHttpRequest(stream, request, url, log);
    }
}

fn sendHttpRequest(stream: std.net.Stream, request: []const u8, url: []const u8, log: *logger.Logger) !void {
    // Send request
    _ = stream.write(request) catch |err| {
        log.err("Failed to send webhook request: {}", .{err});
        return error.WebhookSendFailed;
    };

    // Read response (basic validation)
    var response_buf: [1024]u8 = undefined;
    const bytes_read = stream.read(&response_buf) catch |err| {
        log.warn("Failed to read webhook response: {}", .{err});
        return; // Don't fail on response read errors
    };

    if (bytes_read > 0) {
        const response = response_buf[0..bytes_read];
        if (std.mem.indexOf(u8, response, "HTTP/1") != null) {
            if (std.mem.indexOf(u8, response, "200") != null or
               std.mem.indexOf(u8, response, "201") != null or
               std.mem.indexOf(u8, response, "202") != null) {
                log.info("Webhook delivered successfully to {s}", .{url});
            } else {
                log.warn("Webhook returned non-2xx status: {s}", .{response[0..@min(100, response.len)]});
            }
        }
    }
}

fn sendHttpsRequest(
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    request: []const u8,
    hostname: []const u8,
    url: []const u8,
    log: *logger.Logger,
) !void {
    _ = allocator; // TLS library will handle allocation internally

    // Initialize TLS client connection from stream
    // For webhook HTTPS, we skip certificate verification for simplicity
    // In production, you may want to provide proper root CAs
    var tls_conn = tls.clientFromStream(stream, .{
        .host = hostname,
        .root_ca = .{},
        .insecure_skip_verify = true,
    }) catch |err| {
        log.err("Failed to initialize TLS client: {}", .{err});
        return error.TlsInitFailed;
    };
    defer tls_conn.close() catch {};

    // Send HTTPS request
    tls_conn.writeAll(request) catch |err| {
        log.err("Failed to send HTTPS webhook request: {}", .{err});
        return error.WebhookSendFailed;
    };

    // Read response
    var response_buf: [1024]u8 = undefined;
    const bytes_read = tls_conn.read(&response_buf) catch |err| {
        log.warn("Failed to read HTTPS webhook response: {}", .{err});
        return; // Don't fail on response read errors
    };

    if (bytes_read > 0) {
        const response = response_buf[0..bytes_read];
        if (std.mem.indexOf(u8, response, "HTTP/1") != null) {
            if (std.mem.indexOf(u8, response, "200") != null or
               std.mem.indexOf(u8, response, "201") != null or
               std.mem.indexOf(u8, response, "202") != null) {
                log.info("HTTPS webhook delivered successfully to {s}", .{url});
            } else {
                log.warn("HTTPS webhook returned non-2xx status: {s}", .{response[0..@min(100, response.len)]});
            }
        }
    }
}
