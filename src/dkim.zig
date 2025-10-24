const std = @import("std");

/// DKIM validation result
pub const DKIMResult = enum {
    pass,
    fail,
    neutral,
    temperror,
    permerror,

    pub fn toString(self: DKIMResult) []const u8 {
        return switch (self) {
            .pass => "pass",
            .fail => "fail",
            .neutral => "neutral",
            .temperror => "temperror",
            .permerror => "permerror",
        };
    }
};

/// DKIM signature (RFC 6376)
pub const DKIMSignature = struct {
    version: []const u8,
    algorithm: []const u8, // e.g., "rsa-sha256"
    domain: []const u8, // d= tag
    selector: []const u8, // s= tag
    headers: []const u8, // h= tag (signed headers)
    body_hash: []const u8, // bh= tag
    signature: []const u8, // b= tag
    canonicalization: []const u8, // c= tag (default: simple/simple)
    query_method: []const u8, // q= tag (default: dns/txt)
    allocator: std.mem.Allocator,

    pub fn deinit(self: *DKIMSignature) void {
        self.allocator.free(self.version);
        self.allocator.free(self.algorithm);
        self.allocator.free(self.domain);
        self.allocator.free(self.selector);
        self.allocator.free(self.headers);
        self.allocator.free(self.body_hash);
        self.allocator.free(self.signature);
        self.allocator.free(self.canonicalization);
        self.allocator.free(self.query_method);
    }

    /// Parse DKIM-Signature header value
    pub fn parse(allocator: std.mem.Allocator, header_value: []const u8) !DKIMSignature {
        var sig = DKIMSignature{
            .version = "",
            .algorithm = "",
            .domain = "",
            .selector = "",
            .headers = "",
            .body_hash = "",
            .signature = "",
            .canonicalization = try allocator.dupe(u8, "simple/simple"),
            .query_method = try allocator.dupe(u8, "dns/txt"),
            .allocator = allocator,
        };
        errdefer {
            if (sig.version.len > 0) allocator.free(sig.version);
            if (sig.algorithm.len > 0) allocator.free(sig.algorithm);
            if (sig.domain.len > 0) allocator.free(sig.domain);
            if (sig.selector.len > 0) allocator.free(sig.selector);
            if (sig.headers.len > 0) allocator.free(sig.headers);
            if (sig.body_hash.len > 0) allocator.free(sig.body_hash);
            if (sig.signature.len > 0) allocator.free(sig.signature);
            allocator.free(sig.canonicalization);
            allocator.free(sig.query_method);
        }

        // Parse tag=value pairs
        var tags = std.mem.splitScalar(u8, header_value, ';');
        while (tags.next()) |tag| {
            const trimmed = std.mem.trim(u8, tag, " \t\r\n");
            if (trimmed.len == 0) continue;

            const eq_pos = std.mem.indexOf(u8, trimmed, "=") orelse continue;
            const tag_name = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
            const tag_value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");

            if (std.mem.eql(u8, tag_name, "v")) {
                sig.version = try allocator.dupe(u8, tag_value);
            } else if (std.mem.eql(u8, tag_name, "a")) {
                sig.algorithm = try allocator.dupe(u8, tag_value);
            } else if (std.mem.eql(u8, tag_name, "d")) {
                sig.domain = try allocator.dupe(u8, tag_value);
            } else if (std.mem.eql(u8, tag_name, "s")) {
                sig.selector = try allocator.dupe(u8, tag_value);
            } else if (std.mem.eql(u8, tag_name, "h")) {
                sig.headers = try allocator.dupe(u8, tag_value);
            } else if (std.mem.eql(u8, tag_name, "bh")) {
                sig.body_hash = try allocator.dupe(u8, tag_value);
            } else if (std.mem.eql(u8, tag_name, "b")) {
                sig.signature = try allocator.dupe(u8, tag_value);
            } else if (std.mem.eql(u8, tag_name, "c")) {
                allocator.free(sig.canonicalization);
                sig.canonicalization = try allocator.dupe(u8, tag_value);
            } else if (std.mem.eql(u8, tag_name, "q")) {
                allocator.free(sig.query_method);
                sig.query_method = try allocator.dupe(u8, tag_value);
            }
        }

        // Validate required fields
        if (sig.version.len == 0 or sig.algorithm.len == 0 or sig.domain.len == 0 or
            sig.selector.len == 0 or sig.signature.len == 0)
        {
            return error.InvalidDKIMSignature;
        }

        return sig;
    }
};

/// DKIM validator
pub const DKIMValidator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DKIMValidator {
        return .{ .allocator = allocator };
    }

    /// Validate DKIM signature in email headers
    pub fn validate(self: *DKIMValidator, headers: []const u8, body: []const u8) !DKIMResult {
        // Extract DKIM-Signature header
        const sig_header = self.extractDKIMSignature(headers) orelse {
            return .neutral;
        };

        // Parse signature
        var signature = DKIMSignature.parse(self.allocator, sig_header) catch {
            return .permerror;
        };
        defer signature.deinit();

        // Verify version
        if (!std.mem.eql(u8, signature.version, "1")) {
            return .permerror;
        }

        // Query DNS for public key
        const public_key = self.queryPublicKey(signature.domain, signature.selector) catch {
            return .temperror;
        };
        defer if (public_key) |key| self.allocator.free(key);

        if (public_key == null) {
            return .permerror;
        }

        // Verify body hash
        const body_hash_valid = try self.verifyBodyHash(&signature, body);
        if (!body_hash_valid) {
            return .fail;
        }

        // Verify signature
        const sig_valid = try self.verifySignature(&signature, headers, public_key.?);
        if (!sig_valid) {
            return .fail;
        }

        return .pass;
    }

    fn extractDKIMSignature(self: *DKIMValidator, headers: []const u8) ?[]const u8 {
        _ = self;
        // Find DKIM-Signature header
        var lines = std.mem.splitSequence(u8, headers, "\r\n");
        var in_dkim_sig = false;
        var sig_value = std.ArrayList(u8).init(self.allocator);
        defer sig_value.deinit();

        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "DKIM-Signature:")) {
                in_dkim_sig = true;
                const value = std.mem.trim(u8, line[15..], " \t");
                sig_value.appendSlice(value) catch return null;
            } else if (in_dkim_sig) {
                // Continuation line
                if (line.len > 0 and (line[0] == ' ' or line[0] == '\t')) {
                    const value = std.mem.trim(u8, line, " \t");
                    sig_value.appendSlice(value) catch return null;
                } else {
                    break;
                }
            }
        }

        if (sig_value.items.len == 0) return null;
        return sig_value.toOwnedSlice() catch return null;
    }

    fn queryPublicKey(self: *DKIMValidator, domain: []const u8, selector: []const u8) !?[]const u8 {
        // In production, query DNS TXT record at: selector._domainkey.domain
        // Format: "v=DKIM1; k=rsa; p=<base64-public-key>"
        _ = self;
        _ = domain;
        _ = selector;

        // For now, return null (no key found)
        // A real implementation would use DNS lookups
        return null;
    }

    fn verifyBodyHash(self: *DKIMValidator, signature: *const DKIMSignature, body: []const u8) !bool {
        _ = signature;
        _ = body;
        _ = self;

        // In production:
        // 1. Canonicalize body according to c= tag
        // 2. Compute hash (SHA256 for rsa-sha256)
        // 3. Base64 encode
        // 4. Compare with bh= tag

        // For now, assume valid
        return true;
    }

    fn verifySignature(self: *DKIMValidator, signature: *const DKIMSignature, headers: []const u8, public_key: []const u8) !bool {
        _ = signature;
        _ = headers;
        _ = public_key;
        _ = self;

        // In production:
        // 1. Extract signed headers (h= tag)
        // 2. Canonicalize headers
        // 3. Verify RSA signature with public key

        // For now, assume valid
        return true;
    }
};

/// DKIM signer for outgoing mail
pub const DKIMSigner = struct {
    allocator: std.mem.Allocator,
    domain: []const u8,
    selector: []const u8,
    private_key: []const u8,

    pub fn init(allocator: std.mem.Allocator, domain: []const u8, selector: []const u8, private_key: []const u8) !DKIMSigner {
        return .{
            .allocator = allocator,
            .domain = try allocator.dupe(u8, domain),
            .selector = try allocator.dupe(u8, selector),
            .private_key = try allocator.dupe(u8, private_key),
        };
    }

    pub fn deinit(self: *DKIMSigner) void {
        self.allocator.free(self.domain);
        self.allocator.free(self.selector);
        self.allocator.free(self.private_key);
    }

    /// Sign an email message
    pub fn sign(self: *DKIMSigner, headers: []const u8, body: []const u8) ![]const u8 {
        _ = headers;
        _ = body;

        // Build DKIM-Signature header
        return try std.fmt.allocPrint(
            self.allocator,
            "DKIM-Signature: v=1; a=rsa-sha256; c=relaxed/relaxed; d={s}; s={s};\r\n\th=from:to:subject:date; bh=<body-hash>; b=<signature>",
            .{ self.domain, self.selector },
        );
    }
};

test "DKIM signature parsing" {
    const testing = std.testing;

    const sig_value =
        \\v=1; a=rsa-sha256; c=relaxed/relaxed;
        \\d=example.com; s=default;
        \\h=from:to:subject:date;
        \\bh=BODYHASH==;
        \\b=SIGNATURE==
    ;

    var sig = try DKIMSignature.parse(testing.allocator, sig_value);
    defer sig.deinit();

    try testing.expectEqualStrings("1", sig.version);
    try testing.expectEqualStrings("rsa-sha256", sig.algorithm);
    try testing.expectEqualStrings("example.com", sig.domain);
    try testing.expectEqualStrings("default", sig.selector);
}

test "DKIM validator neutral" {
    const testing = std.testing;
    var validator = DKIMValidator.init(testing.allocator);

    const headers = "From: test@example.com\r\n\r\n";
    const body = "Test body";

    const result = try validator.validate(headers, body);
    try testing.expect(result == .neutral);
}
