const std = @import("std");
const net = std.net;
const Allocator = std.mem.Allocator;
const auth = @import("../auth/auth.zig");

/// CalDAV/CardDAV Server Implementation
/// RFC 4791 (CalDAV) and RFC 6352 (CardDAV)
///
/// Provides calendar and contact synchronization over WebDAV

// ============================================================================
// Configuration
// ============================================================================

pub const CalDavConfig = struct {
    port: u16 = 8008,
    ssl_port: u16 =8443,
    enable_ssl: bool = true,
    max_connections: usize = 100,
    connection_timeout_seconds: u64 = 300,
    max_resource_size: usize = 10 * 1024 * 1024, // 10 MB
    calendar_path: []const u8 = "/var/spool/caldav/calendars",
    contacts_path: []const u8 = "/var/spool/caldav/contacts",
    enable_caldav: bool = true,
    enable_carddav: bool = true,
};

// ============================================================================
// HTTP Methods
// ============================================================================

pub const HttpMethod = enum {
    get,
    put,
    post,
    delete,
    options,
    propfind,
    proppatch,
    mkcalendar,
    report,
    mkcol,
    move,
    copy,

    pub fn fromString(method: []const u8) ?HttpMethod {
        const upper = std.ascii.allocUpperString(std.heap.page_allocator, method) catch return null;
        defer std.heap.page_allocator.free(upper);

        const methods = std.StaticStringMap(HttpMethod).initComptime(.{
            .{ "GET", .get },
            .{ "PUT", .put },
            .{ "POST", .post },
            .{ "DELETE", .delete },
            .{ "OPTIONS", .options },
            .{ "PROPFIND", .propfind },
            .{ "PROPPATCH", .proppatch },
            .{ "MKCALENDAR", .mkcalendar },
            .{ "REPORT", .report },
            .{ "MKCOL", .mkcol },
            .{ "MOVE", .move },
            .{ "COPY", .copy },
        });
        return methods.get(upper);
    }
};

// ============================================================================
// Resource Types
// ============================================================================

pub const ResourceType = enum {
    calendar,
    addressbook,
    event,
    todo,
    journal,
    vcard,
    collection,
};

pub const CalendarResource = struct {
    uid: []const u8,
    summary: []const u8,
    description: ?[]const u8 = null,
    dtstart: []const u8,
    dtend: ?[]const u8 = null,
    rrule: ?[]const u8 = null, // Recurrence rule
    location: ?[]const u8 = null,
    organizer: ?[]const u8 = null,
    attendees: std.ArrayList([]const u8),
    created: i64,
    last_modified: i64,
    etag: []const u8,

    pub fn deinit(self: *CalendarResource, allocator: Allocator) void {
        self.attendees.deinit(allocator);
    }
};

pub const ContactResource = struct {
    uid: []const u8,
    full_name: []const u8,
    given_name: ?[]const u8 = null,
    family_name: ?[]const u8 = null,
    email_addresses: std.ArrayList([]const u8),
    phone_numbers: std.ArrayList([]const u8),
    organization: ?[]const u8 = null,
    title: ?[]const u8 = null,
    note: ?[]const u8 = null,
    created: i64,
    last_modified: i64,
    etag: []const u8,

    pub fn deinit(self: *ContactResource, allocator: Allocator) void {
        self.email_addresses.deinit(allocator);
        self.phone_numbers.deinit(allocator);
    }
};

// ============================================================================
// CalDAV/CardDAV Session
// ============================================================================

pub const CalDavSession = struct {
    allocator: Allocator,
    stream: net.Stream,
    username: ?[]const u8 = null,
    authenticated: bool = false,
    request_buffer: std.ArrayList(u8),
    current_path: []const u8 = "/",
    auth_backend: *auth.AuthBackend,

    pub fn init(allocator: Allocator, stream: net.Stream, auth_backend: *auth.AuthBackend) !CalDavSession {
        return CalDavSession{
            .allocator = allocator,
            .stream = stream,
            .request_buffer = std.ArrayList(u8){},
            .auth_backend = auth_backend,
        };
    }

    pub fn deinit(self: *CalDavSession) void {
        self.request_buffer.deinit(self.allocator);
        if (self.username) |username| {
            self.allocator.free(username);
        }
    }

    /// Handle incoming HTTP request
    pub fn handleRequest(self: *CalDavSession, config: *const CalDavConfig) !bool {
        var buffer: [4096]u8 = undefined;
        const bytes_read = try self.stream.read(&buffer);

        if (bytes_read == 0) {
            return false; // Connection closed
        }

        const request = buffer[0..bytes_read];

        // Parse HTTP request line
        var lines = std.mem.splitScalar(u8, request, '\n');
        const request_line = lines.next() orelse return false;

        var parts = std.mem.splitScalar(u8, request_line, ' ');
        const method_str = parts.next() orelse return false;
        const path = parts.next() orelse return false;
        const http_version = parts.next() orelse return false;
        _ = http_version;

        const method = HttpMethod.fromString(method_str) orelse {
            try self.sendError(405, "Method Not Allowed");
            return true;
        };

        // Check authentication (Basic Auth)
        if (!self.authenticated) {
            var auth_header: ?[]const u8 = null;
            while (lines.next()) |line| {
                const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
                if (trimmed.len == 0) break;

                if (std.mem.startsWith(u8, trimmed, "Authorization:")) {
                    auth_header = std.mem.trim(u8, trimmed[14..], &std.ascii.whitespace);
                    break;
                }
            }

            if (auth_header == null) {
                try self.sendAuthRequired();
                return true;
            }

            // Validate credentials using auth backend
            const validated_username = self.auth_backend.verifyBasicAuth(auth_header.?) catch |err| {
                std.log.err("CalDAV authentication error: {}", .{err});
                try self.sendAuthRequired();
                return true;
            };

            if (validated_username) |username| {
                self.authenticated = true;
                self.username = username;
                std.log.info("Successful CalDAV authentication for user: {s}", .{username});
            } else {
                std.log.warn("Failed CalDAV authentication attempt");
                try self.sendAuthRequired();
                return true;
            }
        }

        // Route request based on method and path
        try self.routeRequest(method, path, request, config);

        return true;
    }

    /// Route request to appropriate handler
    fn routeRequest(
        self: *CalDavSession,
        method: HttpMethod,
        path: []const u8,
        request: []const u8,
        config: *const CalDavConfig,
    ) !void {
        switch (method) {
            .options => try self.handleOptions(path),
            .propfind => try self.handlePropfind(path, request, config),
            .get => try self.handleGet(path, config),
            .put => try self.handlePut(path, request, config),
            .delete => try self.handleDelete(path, config),
            .mkcalendar => try self.handleMkcalendar(path, config),
            .mkcol => try self.handleMkcol(path, config),
            .report => try self.handleReport(path, request, config),
            else => try self.sendError(501, "Not Implemented"),
        }
    }

    /// Handle OPTIONS request (WebDAV/CalDAV/CardDAV capabilities)
    fn handleOptions(self: *CalDavSession, path: []const u8) !void {
        _ = path;

        const response =
            \\HTTP/1.1 200 OK
            \\DAV: 1, 2, 3, calendar-access, addressbook
            \\Allow: OPTIONS, GET, HEAD, POST, PUT, DELETE, PROPFIND, PROPPATCH, MKCALENDAR, MKCOL, REPORT
            \\Content-Length: 0
            \\
            \\
        ;

        _ = try self.stream.write(response);
    }

    /// Handle PROPFIND request (property discovery)
    fn handlePropfind(
        self: *CalDavSession,
        path: []const u8,
        request: []const u8,
        config: *const CalDavConfig,
    ) !void {
        _ = config;

        // Parse Depth header (future use for recursive PROPFIND)
        var lines = std.mem.splitScalar(u8, request, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
            if (std.mem.startsWith(u8, trimmed, "Depth:")) {
                // TODO: Use depth for recursive PROPFIND
                break;
            }
        }

        // Build XML response
        var response_body = std.ArrayList(u8){};
        defer response_body.deinit(self.allocator);

        const writer = response_body.writer(self.allocator);

        try writer.writeAll(
            \\<?xml version="1.0" encoding="utf-8" ?>
            \\<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav" xmlns:CARD="urn:ietf:params:xml:ns:carddav">
            \\  <D:response>
            \\    <D:href>
        );
        try writer.writeAll(path);
        try writer.writeAll(
            \\</D:href>
            \\    <D:propstat>
            \\      <D:prop>
            \\        <D:resourcetype>
            \\          <D:collection/>
            \\          <C:calendar/>
            \\        </D:resourcetype>
            \\        <D:displayname>Calendar</D:displayname>
            \\        <C:supported-calendar-component-set>
            \\          <C:comp name="VEVENT"/>
            \\          <C:comp name="VTODO"/>
            \\        </C:supported-calendar-component-set>
            \\      </D:prop>
            \\      <D:status>HTTP/1.1 200 OK</D:status>
            \\    </D:propstat>
            \\  </D:response>
            \\</D:multistatus>
        );

        const response_header = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 207 Multi-Status\r\nContent-Type: application/xml; charset=utf-8\r\nContent-Length: {d}\r\n\r\n",
            .{response_body.items.len},
        );
        defer self.allocator.free(response_header);

        _ = try self.stream.write(response_header);
        _ = try self.stream.write(response_body.items);
    }

    /// Handle GET request (retrieve calendar/contact resource)
    fn handleGet(self: *CalDavSession, path: []const u8, config: *const CalDavConfig) !void {
        _ = config;

        // Check if path is a calendar event or contact
        if (std.mem.endsWith(u8, path, ".ics")) {
            // Return iCalendar data
            const ical_data =
                \\BEGIN:VCALENDAR
                \\VERSION:2.0
                \\PRODID:-//SMTP Server//CalDAV Server//EN
                \\BEGIN:VEVENT
                \\UID:event-001@smtp-server
                \\DTSTAMP:20250124T120000Z
                \\DTSTART:20250124T140000Z
                \\DTEND:20250124T150000Z
                \\SUMMARY:Test Event
                \\DESCRIPTION:This is a test calendar event
                \\END:VEVENT
                \\END:VCALENDAR
            ;

            const response_header = try std.fmt.allocPrint(
                self.allocator,
                "HTTP/1.1 200 OK\r\nContent-Type: text/calendar; charset=utf-8\r\nETag: \"event-001\"\r\nContent-Length: {d}\r\n\r\n",
                .{ical_data.len},
            );
            defer self.allocator.free(response_header);

            _ = try self.stream.write(response_header);
            _ = try self.stream.write(ical_data);
        } else if (std.mem.endsWith(u8, path, ".vcf")) {
            // Return vCard data
            const vcard_data =
                \\BEGIN:VCARD
                \\VERSION:3.0
                \\FN:John Doe
                \\N:Doe;John;;;
                \\EMAIL;TYPE=INTERNET:john@example.com
                \\TEL;TYPE=CELL:+1-555-1234
                \\END:VCARD
            ;

            const response_header = try std.fmt.allocPrint(
                self.allocator,
                "HTTP/1.1 200 OK\r\nContent-Type: text/vcard; charset=utf-8\r\nETag: \"contact-001\"\r\nContent-Length: {d}\r\n\r\n",
                .{vcard_data.len},
            );
            defer self.allocator.free(response_header);

            _ = try self.stream.write(response_header);
            _ = try self.stream.write(vcard_data);
        } else {
            try self.sendError(404, "Not Found");
        }
    }

    /// Handle PUT request (create/update calendar/contact resource)
    fn handlePut(
        self: *CalDavSession,
        path: []const u8,
        request: []const u8,
        config: *const CalDavConfig,
    ) !void {
        _ = path;
        _ = config;

        // Extract body from request
        const body_start = std.mem.indexOf(u8, request, "\r\n\r\n") orelse {
            try self.sendError(400, "Bad Request");
            return;
        };

        const body = request[body_start + 4 ..];

        // Validate iCalendar or vCard format
        if (std.mem.indexOf(u8, body, "BEGIN:VCALENDAR") != null) {
            // Parse and store calendar event
            // TODO: Actual storage implementation
            try self.sendSuccess(201, "Created");
        } else if (std.mem.indexOf(u8, body, "BEGIN:VCARD") != null) {
            // Parse and store contact
            // TODO: Actual storage implementation
            try self.sendSuccess(201, "Created");
        } else {
            try self.sendError(400, "Invalid format");
        }
    }

    /// Handle DELETE request (delete calendar/contact resource)
    fn handleDelete(self: *CalDavSession, path: []const u8, config: *const CalDavConfig) !void {
        _ = path;
        _ = config;

        // TODO: Actual deletion implementation
        try self.sendSuccess(204, "No Content");
    }

    /// Handle MKCALENDAR request (create new calendar)
    fn handleMkcalendar(self: *CalDavSession, path: []const u8, config: *const CalDavConfig) !void {
        _ = path;
        _ = config;

        // TODO: Create calendar collection
        try self.sendSuccess(201, "Created");
    }

    /// Handle MKCOL request (create collection)
    fn handleMkcol(self: *CalDavSession, path: []const u8, config: *const CalDavConfig) !void {
        _ = path;
        _ = config;

        // TODO: Create addressbook collection
        try self.sendSuccess(201, "Created");
    }

    /// Handle REPORT request (calendar/contact queries)
    fn handleReport(
        self: *CalDavSession,
        path: []const u8,
        request: []const u8,
        config: *const CalDavConfig,
    ) !void {
        _ = path;
        _ = config;

        // Check report type
        if (std.mem.indexOf(u8, request, "calendar-query") != null) {
            try self.handleCalendarQuery(request);
        } else if (std.mem.indexOf(u8, request, "addressbook-query") != null) {
            try self.handleAddressbookQuery(request);
        } else {
            try self.sendError(400, "Invalid report type");
        }
    }

    /// Handle calendar-query REPORT
    fn handleCalendarQuery(self: *CalDavSession, request: []const u8) !void {
        _ = request;

        // Build calendar query response
        var response_body = std.ArrayList(u8){};
        defer response_body.deinit(self.allocator);

        const writer = response_body.writer(self.allocator);

        try writer.writeAll(
            \\<?xml version="1.0" encoding="utf-8" ?>
            \\<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
            \\  <D:response>
            \\    <D:href>/calendars/user/test/event-001.ics</D:href>
            \\    <D:propstat>
            \\      <D:prop>
            \\        <D:getetag>"event-001"</D:getetag>
            \\        <C:calendar-data>BEGIN:VCALENDAR
            \\VERSION:2.0
            \\BEGIN:VEVENT
            \\UID:event-001
            \\SUMMARY:Test Event
            \\END:VEVENT
            \\END:VCALENDAR</C:calendar-data>
            \\      </D:prop>
            \\      <D:status>HTTP/1.1 200 OK</D:status>
            \\    </D:propstat>
            \\  </D:response>
            \\</D:multistatus>
        );

        const response_header = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 207 Multi-Status\r\nContent-Type: application/xml; charset=utf-8\r\nContent-Length: {d}\r\n\r\n",
            .{response_body.items.len},
        );
        defer self.allocator.free(response_header);

        _ = try self.stream.write(response_header);
        _ = try self.stream.write(response_body.items);
    }

    /// Handle addressbook-query REPORT
    fn handleAddressbookQuery(self: *CalDavSession, request: []const u8) !void {
        _ = request;

        // Build addressbook query response
        var response_body = std.ArrayList(u8){};
        defer response_body.deinit(self.allocator);

        const writer = response_body.writer(self.allocator);

        try writer.writeAll(
            \\<?xml version="1.0" encoding="utf-8" ?>
            \\<D:multistatus xmlns:D="DAV:" xmlns:CARD="urn:ietf:params:xml:ns:carddav">
            \\  <D:response>
            \\    <D:href>/addressbooks/user/test/contact-001.vcf</D:href>
            \\    <D:propstat>
            \\      <D:prop>
            \\        <D:getetag>"contact-001"</D:getetag>
            \\        <CARD:address-data>BEGIN:VCARD
            \\VERSION:3.0
            \\FN:John Doe
            \\EMAIL:john@example.com
            \\END:VCARD</CARD:address-data>
            \\      </D:prop>
            \\      <D:status>HTTP/1.1 200 OK</D:status>
            \\    </D:propstat>
            \\  </D:response>
            \\</D:multistatus>
        );

        const response_header = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 207 Multi-Status\r\nContent-Type: application/xml; charset=utf-8\r\nContent-Length: {d}\r\n\r\n",
            .{response_body.items.len},
        );
        defer self.allocator.free(response_header);

        _ = try self.stream.write(response_header);
        _ = try self.stream.write(response_body.items);
    }

    /// Send authentication required response
    fn sendAuthRequired(self: *CalDavSession) !void {
        const response =
            \\HTTP/1.1 401 Unauthorized
            \\WWW-Authenticate: Basic realm="CalDAV/CardDAV Server"
            \\Content-Length: 0
            \\
            \\
        ;
        _ = try self.stream.write(response);
    }

    /// Send error response
    fn sendError(self: *CalDavSession, code: u16, message: []const u8) !void {
        const response = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 {d} {s}\r\nContent-Length: 0\r\n\r\n",
            .{ code, message },
        );
        defer self.allocator.free(response);

        _ = try self.stream.write(response);
    }

    /// Send success response
    fn sendSuccess(self: *CalDavSession, code: u16, message: []const u8) !void {
        const response = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 {d} {s}\r\nContent-Length: 0\r\n\r\n",
            .{ code, message },
        );
        defer self.allocator.free(response);

        _ = try self.stream.write(response);
    }
};

// ============================================================================
// CalDAV/CardDAV Server
// ============================================================================

pub const CalDavServer = struct {
    allocator: Allocator,
    config: CalDavConfig,
    server: ?net.Server = null,
    running: std.atomic.Value(bool),
    sessions: std.ArrayList(*CalDavSession),
    sessions_mutex: std.Thread.Mutex,
    auth_backend: *auth.AuthBackend,

    pub fn init(allocator: Allocator, config: CalDavConfig, auth_backend: *auth.AuthBackend) CalDavServer {
        return CalDavServer{
            .allocator = allocator,
            .config = config,
            .running = std.atomic.Value(bool).init(false),
            .sessions = std.ArrayList(*CalDavSession){},
            .sessions_mutex = std.Thread.Mutex{},
            .auth_backend = auth_backend,
        };
    }

    pub fn deinit(self: *CalDavServer) void {
        self.stop();

        // Clean up sessions
        self.sessions_mutex.lock();
        defer self.sessions_mutex.unlock();

        for (self.sessions.items) |session| {
            session.deinit();
            self.allocator.destroy(session);
        }
        self.sessions.deinit(self.allocator);
    }

    /// Start the CalDAV/CardDAV server
    pub fn start(self: *CalDavServer) !void {
        const address = try net.Address.parseIp("0.0.0.0", self.config.port);

        self.server = try address.listen(.{
            .reuse_address = true,
            .reuse_port = true,
        });

        self.running.store(true, .seq_cst);

        std.debug.print("[CalDAV/CardDAV] Server started on port {d}\n", .{self.config.port});

        while (self.running.load(.seq_cst)) {
            const connection = self.server.?.accept() catch |err| {
                std.debug.print("[CalDAV/CardDAV] Accept error: {}\n", .{err});
                continue;
            };

            // Handle connection in new thread
            const thread = try std.Thread.spawn(.{}, handleConnection, .{ self, connection.stream });
            thread.detach();
        }
    }

    /// Stop the server
    pub fn stop(self: *CalDavServer) void {
        self.running.store(false, .seq_cst);
        if (self.server) |*server| {
            server.deinit();
            self.server = null;
        }
    }

    /// Handle client connection
    fn handleConnection(self: *CalDavServer, stream: net.Stream) void {
        defer stream.close();

        var session = CalDavSession.init(self.allocator, stream, self.auth_backend) catch |err| {
            std.debug.print("[CalDAV/CardDAV] Session init error: {}\n", .{err});
            return;
        };
        defer session.deinit();

        // Add to sessions list
        self.sessions_mutex.lock();
        const session_ptr = self.allocator.create(CalDavSession) catch return;
        session_ptr.* = session;
        self.sessions.append(session_ptr) catch {
            self.allocator.destroy(session_ptr);
            self.sessions_mutex.unlock();
            return;
        };
        self.sessions_mutex.unlock();

        // Handle requests
        while (session.handleRequest(&self.config) catch false) {
            // Continue handling requests
        }

        std.debug.print("[CalDAV/CardDAV] Session ended\n", .{});
    }
};

// ============================================================================
// Tests
// ============================================================================

test "CalDAV server initialization" {
    const testing = std.testing;

    const config = CalDavConfig{};
    var server = CalDavServer.init(testing.allocator, config);
    defer server.deinit();

    try testing.expect(!server.running.load(.seq_cst));
}

test "HTTP method parsing" {
    const testing = std.testing;

    try testing.expectEqual(HttpMethod.propfind, HttpMethod.fromString("PROPFIND").?);
    try testing.expectEqual(HttpMethod.mkcalendar, HttpMethod.fromString("MKCALENDAR").?);
    try testing.expectEqual(HttpMethod.report, HttpMethod.fromString("REPORT").?);
    try testing.expect(HttpMethod.fromString("INVALID") == null);
}

test "CalDAV session initialization" {
    // Create a mock stream (just for testing structure)
    const address = try net.Address.parseIp("127.0.0.1", 0);
    var server = try address.listen(.{});
    defer server.deinit();

    // We can't easily test the full session without a real connection,
    // but we can verify the structure compiles and initializes
    _ = CalDavSession.init;
}
