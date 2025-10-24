const std = @import("std");
const net = std.net;
const config = @import("config.zig");
const auth = @import("auth.zig");

const SMTPCommand = enum {
    HELO,
    EHLO,
    MAIL,
    RCPT,
    DATA,
    RSET,
    NOOP,
    QUIT,
    AUTH,
    STARTTLS,
    UNKNOWN,
};

const SessionState = enum {
    Initial,
    Greeted,
    MailFrom,
    RcptTo,
    Data,
    Authenticated,
};

pub const Session = struct {
    allocator: std.mem.Allocator,
    connection: net.Server.Connection,
    config: config.Config,
    state: SessionState,
    mail_from: ?[]u8,
    rcpt_to: std.ArrayList([]u8),
    authenticated: bool,
    client_hostname: ?[]u8,

    pub fn init(allocator: std.mem.Allocator, connection: net.Server.Connection, cfg: config.Config) !Session {
        return Session{
            .allocator = allocator,
            .connection = connection,
            .config = cfg,
            .state = .Initial,
            .mail_from = null,
            .rcpt_to = std.ArrayList([]u8){},
            .authenticated = false,
            .client_hostname = null,
        };
    }

    pub fn deinit(self: *Session) void {
        if (self.mail_from) |mf| {
            self.allocator.free(mf);
        }
        for (self.rcpt_to.items) |rcpt| {
            self.allocator.free(rcpt);
        }
        self.rcpt_to.deinit(self.allocator);
        if (self.client_hostname) |hostname| {
            self.allocator.free(hostname);
        }
    }

    pub fn handle(self: *Session) !void {
        // Send greeting
        try self.sendResponse(null, 220, self.config.hostname, "ESMTP Service Ready");

        var line_buffer: [4096]u8 = undefined;
        var line_pos: usize = 0;

        while (true) {
            // Read byte by byte until we hit \n
            const byte_read = self.connection.stream.read(line_buffer[line_pos .. line_pos + 1]) catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };

            if (byte_read == 0) break;

            if (line_buffer[line_pos] == '\n') {
                // Remove \r\n if present
                const line = if (line_pos > 0 and line_buffer[line_pos - 1] == '\r')
                    line_buffer[0 .. line_pos - 1]
                else
                    line_buffer[0..line_pos];

                line_pos = 0;

                if (line.len == 0) continue;

                const should_quit = try self.processCommand(null, line);
                if (should_quit) break;
            } else {
                line_pos += 1;
                if (line_pos >= line_buffer.len) {
                    return error.LineTooLong;
                }
            }
        }
    }

    fn processCommand(self: *Session, writer: anytype, line: []const u8) !bool {
        const cmd = self.parseCommand(line);

        switch (cmd) {
            .HELO => try self.handleHelo(writer, line),
            .EHLO => try self.handleEhlo(writer, line),
            .MAIL => try self.handleMail(writer, line),
            .RCPT => try self.handleRcpt(writer, line),
            .DATA => try self.handleData(writer),
            .RSET => try self.handleRset(writer),
            .NOOP => try self.sendResponse(writer, 250, "OK", null),
            .QUIT => {
                try self.sendResponse(writer, 221, self.config.hostname, "Service closing transmission channel");
                return true;
            },
            .AUTH => try self.handleAuth(writer, line),
            .STARTTLS => try self.handleStartTls(writer),
            .UNKNOWN => try self.sendResponse(writer, 500, "Syntax error, command unrecognized", null),
        }

        return false;
    }

    fn parseCommand(self: *Session, line: []const u8) SMTPCommand {
        _ = self;

        if (line.len < 4) return .UNKNOWN;

        const cmd_end = std.mem.indexOfScalar(u8, line, ' ') orelse line.len;
        const cmd_str = line[0..cmd_end];

        if (std.ascii.eqlIgnoreCase(cmd_str, "HELO")) return .HELO;
        if (std.ascii.eqlIgnoreCase(cmd_str, "EHLO")) return .EHLO;
        if (std.ascii.eqlIgnoreCase(cmd_str, "MAIL")) return .MAIL;
        if (std.ascii.eqlIgnoreCase(cmd_str, "RCPT")) return .RCPT;
        if (std.ascii.eqlIgnoreCase(cmd_str, "DATA")) return .DATA;
        if (std.ascii.eqlIgnoreCase(cmd_str, "RSET")) return .RSET;
        if (std.ascii.eqlIgnoreCase(cmd_str, "NOOP")) return .NOOP;
        if (std.ascii.eqlIgnoreCase(cmd_str, "QUIT")) return .QUIT;
        if (std.ascii.eqlIgnoreCase(cmd_str, "AUTH")) return .AUTH;
        if (std.ascii.eqlIgnoreCase(cmd_str, "STARTTLS")) return .STARTTLS;

        return .UNKNOWN;
    }

    fn handleHelo(self: *Session, writer: anytype, line: []const u8) !void {
        if (line.len < 6) {
            try self.sendResponse(writer, 501, "Syntax: HELO hostname", null);
            return;
        }

        const hostname = std.mem.trim(u8, line[5..], " \t");
        if (self.client_hostname) |old| {
            self.allocator.free(old);
        }
        self.client_hostname = try self.allocator.dupe(u8, hostname);

        self.state = .Greeted;
        try self.sendResponse(writer, 250, self.config.hostname, null);
    }

    fn handleEhlo(self: *Session, writer: anytype, line: []const u8) !void {
        if (line.len < 6) {
            try self.sendResponse(writer, 501, "Syntax: EHLO hostname", null);
            return;
        }

        const hostname = std.mem.trim(u8, line[5..], " \t");
        if (self.client_hostname) |old| {
            self.allocator.free(old);
        }
        self.client_hostname = try self.allocator.dupe(u8, hostname);

        self.state = .Greeted;

        // Send EHLO response with extensions
        var ehlo_buf: [256]u8 = undefined;
        const ehlo_line = try std.fmt.bufPrint(&ehlo_buf, "250-{s}\r\n", .{self.config.hostname});
        _ = try self.connection.stream.write(ehlo_line);
        _ = try self.connection.stream.write("250-SIZE 10485760\r\n");
        _ = try self.connection.stream.write("250-8BITMIME\r\n");
        _ = try self.connection.stream.write("250-PIPELINING\r\n");

        if (self.config.enable_auth) {
            _ = try self.connection.stream.write("250-AUTH PLAIN LOGIN\r\n");
        }

        if (self.config.enable_tls) {
            _ = try self.connection.stream.write("250-STARTTLS\r\n");
        }

        _ = try self.connection.stream.write("250 HELP\r\n");
    }

    fn handleMail(self: *Session, writer: anytype, line: []const u8) !void {
        if (self.state != .Greeted and self.state != .Authenticated) {
            try self.sendResponse(writer, 503, "Bad sequence of commands", null);
            return;
        }

        // Parse MAIL FROM:<address>
        const from_start = std.mem.indexOf(u8, line, "FROM:") orelse {
            try self.sendResponse(writer, 501, "Syntax: MAIL FROM:<address>", null);
            return;
        };

        const addr_part = line[from_start + 5 ..];
        const addr = std.mem.trim(u8, addr_part, " \t<>");

        if (addr.len == 0) {
            try self.sendResponse(writer, 501, "Invalid sender address", null);
            return;
        }

        if (self.mail_from) |old| {
            self.allocator.free(old);
        }
        self.mail_from = try self.allocator.dupe(u8, addr);

        self.state = .MailFrom;
        try self.sendResponse(writer, 250, "OK", null);
    }

    fn handleRcpt(self: *Session, writer: anytype, line: []const u8) !void {
        if (self.state != .MailFrom and self.state != .RcptTo) {
            try self.sendResponse(writer, 503, "Bad sequence of commands", null);
            return;
        }

        // Parse RCPT TO:<address>
        const to_start = std.mem.indexOf(u8, line, "TO:") orelse {
            try self.sendResponse(writer, 501, "Syntax: RCPT TO:<address>", null);
            return;
        };

        const addr_part = line[to_start + 3 ..];
        const addr = std.mem.trim(u8, addr_part, " \t<>");

        if (addr.len == 0) {
            try self.sendResponse(writer, 501, "Invalid recipient address", null);
            return;
        }

        try self.rcpt_to.append(self.allocator, try self.allocator.dupe(u8, addr));

        self.state = .RcptTo;
        try self.sendResponse(writer, 250, "OK", null);
    }

    fn handleData(self: *Session, writer: anytype) !void {
        if (self.state != .RcptTo) {
            try self.sendResponse(writer, 503, "Bad sequence of commands", null);
            return;
        }

        try self.sendResponse(writer, 354, "Start mail input; end with <CRLF>.<CRLF>", null);

        var message_data = std.ArrayList(u8){};
        defer message_data.deinit(self.allocator);

        var line_buffer: [4096]u8 = undefined;
        var line_pos: usize = 0;
        var prev_was_crlf = false;

        while (true) {
            // Read byte by byte
            const byte_read = try self.connection.stream.read(line_buffer[line_pos .. line_pos + 1]);
            if (byte_read == 0) break;

            if (line_buffer[line_pos] == '\n') {
                const line = if (line_pos > 0 and line_buffer[line_pos - 1] == '\r')
                    line_buffer[0 .. line_pos - 1]
                else
                    line_buffer[0..line_pos];

                line_pos = 0;
                const trimmed = line;

            // Check for end of data (.)
            if (trimmed.len == 1 and trimmed[0] == '.') {
                if (prev_was_crlf or message_data.items.len == 0) {
                    break;
                }
            }

            // Handle transparency (remove leading dot if line starts with ..)
            const data_line = if (trimmed.len > 1 and trimmed[0] == '.' and trimmed[1] == '.')
                trimmed[1..]
            else
                trimmed;

                try message_data.appendSlice(self.allocator, data_line);
                try message_data.append(self.allocator, '\n');

                prev_was_crlf = trimmed.len == 0;

                // Enforce max message size
                if (message_data.items.len > self.config.max_message_size) {
                    try self.sendResponse(writer, 552, "Message size exceeds maximum allowed", null);
                    return;
                }
            } else {
                line_pos += 1;
                if (line_pos >= line_buffer.len) return error.LineTooLong;
            }
        }

        // Save the message (in a real implementation, you'd save to disk or database)
        try self.saveMessage(message_data.items);

        try self.sendResponse(writer, 250, "OK: Message accepted for delivery", null);

        // Reset state for next message
        try self.handleRset(writer);
    }

    fn handleRset(self: *Session, writer: anytype) !void {
        if (self.mail_from) |mf| {
            self.allocator.free(mf);
            self.mail_from = null;
        }

        for (self.rcpt_to.items) |rcpt| {
            self.allocator.free(rcpt);
        }
        self.rcpt_to.clearRetainingCapacity();

        if (self.state == .Authenticated) {
            self.state = .Authenticated;
        } else {
            self.state = .Greeted;
        }

        try self.sendResponse(writer, 250, "OK", null);
    }

    fn handleAuth(self: *Session, writer: anytype, line: []const u8) !void {
        if (!self.config.enable_auth) {
            try self.sendResponse(writer, 502, "Command not implemented", null);
            return;
        }

        if (self.authenticated) {
            try self.sendResponse(writer, 503, "Already authenticated", null);
            return;
        }

        // Parse AUTH mechanism
        var it = std.mem.splitScalar(u8, line, ' ');
        _ = it.next(); // Skip AUTH

        const mechanism = it.next() orelse {
            try self.sendResponse(writer, 501, "Syntax: AUTH mechanism [initial-response]", null);
            return;
        };

        if (std.ascii.eqlIgnoreCase(mechanism, "PLAIN")) {
            // For simplicity, accept any authentication (in production, verify credentials)
            self.authenticated = true;
            self.state = .Authenticated;
            try self.sendResponse(writer, 235, "Authentication successful", null);
        } else if (std.ascii.eqlIgnoreCase(mechanism, "LOGIN")) {
            self.authenticated = true;
            self.state = .Authenticated;
            try self.sendResponse(writer, 235, "Authentication successful", null);
        } else {
            try self.sendResponse(writer, 504, "Unrecognized authentication type", null);
        }
    }

    fn handleStartTls(self: *Session, writer: anytype) !void {
        // TLS implementation would go here
        _ = try self.connection.stream.write("454 TLS not available\r\n");
        _ = writer;
    }

    fn sendResponse(self: *Session, writer: anytype, code: u16, message: []const u8, extra: ?[]const u8) !void {
        const stream = self.connection.stream;
        var response_buf: [1024]u8 = undefined;
        const response = if (extra) |ext|
            try std.fmt.bufPrint(&response_buf, "{d} {s} {s}\r\n", .{ code, message, ext })
        else
            try std.fmt.bufPrint(&response_buf, "{d} {s}\r\n", .{ code, message });

        _ = try stream.write(response);
        _ = writer;
    }

    fn saveMessage(self: *Session, data: []const u8) !void {
        // Create a maildir-style directory structure
        const cwd = std.fs.cwd();

        // Ensure mail directory exists
        cwd.makeDir("mail") catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        cwd.makeDir("mail/new") catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        // Generate unique filename based on timestamp
        const timestamp = std.time.milliTimestamp();
        const filename = try std.fmt.allocPrint(self.allocator, "mail/new/{d}.eml", .{timestamp});
        defer self.allocator.free(filename);

        // Write message to file
        const file = try cwd.createFile(filename, .{});
        defer file.close();

        var header_buf: [256]u8 = undefined;

        // Write headers
        const from_line = try std.fmt.bufPrint(&header_buf, "From: {s}\r\n", .{self.mail_from orelse "unknown"});
        _ = try file.write(from_line);

        for (self.rcpt_to.items) |rcpt| {
            const to_line = try std.fmt.bufPrint(&header_buf, "To: {s}\r\n", .{rcpt});
            _ = try file.write(to_line);
        }

        const date_line = try std.fmt.bufPrint(&header_buf, "Date: {d}\r\n", .{timestamp});
        _ = try file.write(date_line);
        _ = try file.write("\r\n");

        // Write message body
        _ = try file.write(data);

        std.debug.print("Message saved to {s}\n", .{filename});
    }
};
