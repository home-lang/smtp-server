const std = @import("std");

/// Filter action to take when a rule matches
pub const FilterAction = enum {
    accept,
    reject,
    forward,
    discard,
    tag,

    pub fn toString(self: FilterAction) []const u8 {
        return switch (self) {
            .accept => "accept",
            .reject => "reject",
            .forward => "forward",
            .discard => "discard",
            .tag => "tag",
        };
    }
};

/// Filter condition type
pub const FilterConditionType = enum {
    from,
    to,
    subject,
    header,
    body_contains,
    size_greater,
    size_less,
    has_attachment,

    pub fn toString(self: FilterConditionType) []const u8 {
        return switch (self) {
            .from => "from",
            .to => "to",
            .subject => "subject",
            .header => "header",
            .body_contains => "body_contains",
            .size_greater => "size_greater",
            .size_less => "size_less",
            .has_attachment => "has_attachment",
        };
    }
};

/// Filter condition
pub const FilterCondition = struct {
    condition_type: FilterConditionType,
    pattern: []const u8,
    case_sensitive: bool,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *FilterCondition) void {
        self.allocator.free(self.pattern);
    }

    pub fn matches(self: *const FilterCondition, message: *const Message) bool {
        return switch (self.condition_type) {
            .from => self.matchesString(message.from, self.pattern, self.case_sensitive),
            .to => self.matchesString(message.to, self.pattern, self.case_sensitive),
            .subject => self.matchesString(message.subject, self.pattern, self.case_sensitive),
            .header => blk: {
                // Check if any header matches
                var it = message.headers.iterator();
                while (it.next()) |entry| {
                    if (self.matchesString(entry.value_ptr.*, self.pattern, self.case_sensitive)) {
                        break :blk true;
                    }
                }
                break :blk false;
            },
            .body_contains => self.matchesString(message.body, self.pattern, self.case_sensitive),
            .size_greater => blk: {
                const size_limit = std.fmt.parseInt(usize, self.pattern, 10) catch 0;
                break :blk message.size > size_limit;
            },
            .size_less => blk: {
                const size_limit = std.fmt.parseInt(usize, self.pattern, 10) catch 0;
                break :blk message.size < size_limit;
            },
            .has_attachment => message.has_attachment,
        };
    }

    fn matchesString(self: *const FilterCondition, text: []const u8, pattern: []const u8, case_sensitive: bool) bool {
        _ = self;
        if (case_sensitive) {
            return std.mem.indexOf(u8, text, pattern) != null;
        } else {
            // Simple case-insensitive search
            var text_lower = std.ArrayList(u8).init(self.allocator);
            defer text_lower.deinit();
            var pattern_lower = std.ArrayList(u8).init(self.allocator);
            defer pattern_lower.deinit();

            for (text) |c| {
                text_lower.append(std.ascii.toLower(c)) catch return false;
            }
            for (pattern) |c| {
                pattern_lower.append(std.ascii.toLower(c)) catch return false;
            }

            return std.mem.indexOf(u8, text_lower.items, pattern_lower.items) != null;
        }
    }
};

/// Filter rule
pub const FilterRule = struct {
    name: []const u8,
    enabled: bool,
    conditions: std.ArrayList(FilterCondition),
    action: FilterAction,
    action_parameter: ?[]const u8, // e.g., forward address, tag name
    priority: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, action: FilterAction) !FilterRule {
        return .{
            .name = try allocator.dupe(u8, name),
            .enabled = true,
            .conditions = std.ArrayList(FilterCondition).init(allocator),
            .action = action,
            .action_parameter = null,
            .priority = 100,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FilterRule) void {
        self.allocator.free(self.name);
        for (self.conditions.items) |*cond| {
            cond.deinit();
        }
        self.conditions.deinit();
        if (self.action_parameter) |param| {
            self.allocator.free(param);
        }
    }

    pub fn addCondition(
        self: *FilterRule,
        condition_type: FilterConditionType,
        pattern: []const u8,
        case_sensitive: bool,
    ) !void {
        const condition = FilterCondition{
            .condition_type = condition_type,
            .pattern = try self.allocator.dupe(u8, pattern),
            .case_sensitive = case_sensitive,
            .allocator = self.allocator,
        };
        try self.conditions.append(condition);
    }

    pub fn setActionParameter(self: *FilterRule, param: []const u8) !void {
        if (self.action_parameter) |old| {
            self.allocator.free(old);
        }
        self.action_parameter = try self.allocator.dupe(u8, param);
    }

    /// Check if this rule matches a message (all conditions must match)
    pub fn matches(self: *const FilterRule, message: *const Message) bool {
        if (!self.enabled) return false;
        if (self.conditions.items.len == 0) return false;

        // All conditions must match (AND logic)
        for (self.conditions.items) |*cond| {
            if (!cond.matches(message)) {
                return false;
            }
        }

        return true;
    }
};

/// Message representation for filtering
pub const Message = struct {
    from: []const u8,
    to: []const u8,
    subject: []const u8,
    body: []const u8,
    headers: std.StringHashMap([]const u8),
    size: usize,
    has_attachment: bool,
};

/// Message filter engine
pub const FilterEngine = struct {
    allocator: std.mem.Allocator,
    rules: std.ArrayList(*FilterRule),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) FilterEngine {
        return .{
            .allocator = allocator,
            .rules = std.ArrayList(*FilterRule).init(allocator),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *FilterEngine) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.rules.items) |rule| {
            rule.deinit();
            self.allocator.destroy(rule);
        }
        self.rules.deinit();
    }

    /// Add a filter rule
    pub fn addRule(self: *FilterEngine, rule: *FilterRule) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.rules.append(rule);

        // Sort rules by priority (higher priority first)
        std.mem.sort(*FilterRule, self.rules.items, {}, struct {
            fn lessThan(_: void, a: *FilterRule, b: *FilterRule) bool {
                return a.priority > b.priority;
            }
        }.lessThan);
    }

    /// Process a message through all filter rules
    pub fn processMessage(self: *FilterEngine, message: *const Message) ?FilterResult {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Apply first matching rule
        for (self.rules.items) |rule| {
            if (rule.matches(message)) {
                return FilterResult{
                    .action = rule.action,
                    .action_parameter = rule.action_parameter,
                    .rule_name = rule.name,
                };
            }
        }

        // No rules matched - default action
        return null;
    }

    /// Get all rules
    pub fn getRules(self: *FilterEngine) []*FilterRule {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.rules.items;
    }

    /// Remove a rule by name
    pub fn removeRule(self: *FilterEngine, name: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.rules.items, 0..) |rule, i| {
            if (std.mem.eql(u8, rule.name, name)) {
                _ = self.rules.swapRemove(i);
                rule.deinit();
                self.allocator.destroy(rule);
                return;
            }
        }

        return error.RuleNotFound;
    }
};

pub const FilterResult = struct {
    action: FilterAction,
    action_parameter: ?[]const u8,
    rule_name: []const u8,
};

test "filter condition matching" {
    const testing = std.testing;

    const condition = FilterCondition{
        .condition_type = .from,
        .pattern = try testing.allocator.dupe(u8, "spam@example.com"),
        .case_sensitive = false,
        .allocator = testing.allocator,
    };
    defer testing.allocator.free(condition.pattern);

    var headers = std.StringHashMap([]const u8).init(testing.allocator);
    defer headers.deinit();

    const message = Message{
        .from = "spam@example.com",
        .to = "user@test.com",
        .subject = "Test",
        .body = "Body",
        .headers = headers,
        .size = 100,
        .has_attachment = false,
    };

    try testing.expect(condition.matches(&message));
}

test "filter rule with multiple conditions" {
    const testing = std.testing;

    var rule = try FilterRule.init(testing.allocator, "spam-filter", .reject);
    defer rule.deinit();

    try rule.addCondition(.from, "spam", false);
    try rule.addCondition(.subject, "urgent", false);

    var headers = std.StringHashMap([]const u8).init(testing.allocator);
    defer headers.deinit();

    const message = Message{
        .from = "spam@example.com",
        .to = "user@test.com",
        .subject = "Urgent: Click here",
        .body = "Body",
        .headers = headers,
        .size = 100,
        .has_attachment = false,
    };

    try testing.expect(rule.matches(&message));
}

test "filter engine rule processing" {
    const testing = std.testing;

    var engine = FilterEngine.init(testing.allocator);
    defer engine.deinit();

    var rule = try testing.allocator.create(FilterRule);
    rule.* = try FilterRule.init(testing.allocator, "test-rule", .reject);
    try rule.addCondition(.from, "spam", false);

    try engine.addRule(rule);

    var headers = std.StringHashMap([]const u8).init(testing.allocator);
    defer headers.deinit();

    const message = Message{
        .from = "spam@example.com",
        .to = "user@test.com",
        .subject = "Test",
        .body = "Body",
        .headers = headers,
        .size = 100,
        .has_attachment = false,
    };

    const result = engine.processMessage(&message);
    try testing.expect(result != null);
    try testing.expect(result.?.action == .reject);
}
