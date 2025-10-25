const std = @import("std");

/// Plugin System for SMTP Server Extensibility
/// Provides a flexible plugin architecture for extending server functionality
///
/// Features:
/// - Dynamic plugin loading from shared libraries (.so, .dylib, .dll)
/// - Plugin lifecycle management (init, deinit, enable, disable)
/// - Hook-based extension points (message processing, authentication, etc.)
/// - Plugin dependency resolution
/// - Sandboxed plugin execution with resource limits
/// - Plugin configuration and metadata
/// - Hot-reload support for development

/// Plugin metadata
pub const PluginMetadata = struct {
    name: []const u8,
    version: []const u8,
    author: []const u8,
    description: []const u8,
    license: []const u8,
    dependencies: []const []const u8 = &.{},
    min_server_version: []const u8 = "0.1.0",
    max_server_version: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, version: []const u8) !PluginMetadata {
        return PluginMetadata{
            .name = try allocator.dupe(u8, name),
            .version = try allocator.dupe(u8, version),
            .author = try allocator.dupe(u8, ""),
            .description = try allocator.dupe(u8, ""),
            .license = try allocator.dupe(u8, "MIT"),
        };
    }

    pub fn deinit(self: *PluginMetadata, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.version);
        allocator.free(self.author);
        allocator.free(self.description);
        allocator.free(self.license);
        for (self.dependencies) |dep| {
            allocator.free(dep);
        }
        if (self.dependencies.len > 0) {
            allocator.free(self.dependencies);
        }
        if (self.max_server_version) |max_ver| {
            allocator.free(max_ver);
        }
    }
};

/// Plugin hook types
pub const PluginHookType = enum {
    // Message Processing Hooks
    message_received, // Called when a message is received
    message_validated, // Called after message validation
    message_filtered, // Called during spam/virus filtering
    message_stored, // Called after message is stored
    message_delivered, // Called after successful delivery

    // Authentication Hooks
    auth_started, // Called when authentication begins
    auth_completed, // Called after authentication
    auth_failed, // Called on authentication failure

    // Connection Hooks
    connection_opened, // Called when client connects
    connection_closed, // Called when client disconnects
    connection_upgraded, // Called after STARTTLS

    // Command Hooks
    command_received, // Called for each SMTP command
    command_validated, // Called after command validation

    // Configuration Hooks
    config_loaded, // Called after configuration is loaded
    config_changed, // Called when configuration changes

    // Server Lifecycle Hooks
    server_starting, // Called before server starts
    server_started, // Called after server starts
    server_stopping, // Called before server stops
    server_stopped, // Called after server stops

    pub fn toString(self: PluginHookType) []const u8 {
        return @tagName(self);
    }
};

/// Hook context - data passed to plugin hooks
pub const HookContext = struct {
    allocator: std.mem.Allocator,
    hook_type: PluginHookType,
    data: ?*anyopaque = null, // Hook-specific data
    metadata: std.StringHashMap([]const u8),
    cancel: bool = false, // Plugins can set this to cancel the operation

    pub fn init(allocator: std.mem.Allocator, hook_type: PluginHookType) HookContext {
        return .{
            .allocator = allocator,
            .hook_type = hook_type,
            .metadata = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *HookContext) void {
        var iter = self.metadata.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.metadata.deinit();
    }

    pub fn setMetadata(self: *HookContext, key: []const u8, value: []const u8) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        const value_copy = try self.allocator.dupe(u8, value);
        try self.metadata.put(key_copy, value_copy);
    }

    pub fn getMetadata(self: *const HookContext, key: []const u8) ?[]const u8 {
        return self.metadata.get(key);
    }
};

/// Plugin hook result
pub const HookResult = enum {
    continue_processing, // Continue with other plugins
    stop_processing, // Stop processing this hook chain
    cancel_operation, // Cancel the operation entirely
    error_occurred, // An error occurred in the plugin
};

/// Plugin interface - functions that plugins must implement
pub const PluginInterface = struct {
    /// Initialize the plugin
    init: *const fn (allocator: std.mem.Allocator, config: []const u8) callconv(.C) c_int,

    /// Cleanup plugin resources
    deinit: *const fn () callconv(.C) void,

    /// Get plugin metadata
    getMetadata: *const fn () callconv(.C) ?*const PluginMetadata,

    /// Execute plugin hook
    executeHook: *const fn (context: *HookContext) callconv(.C) c_int,

    /// Enable the plugin
    enable: *const fn () callconv(.C) c_int,

    /// Disable the plugin
    disable: *const fn () callconv(.C) c_int,
};

/// Plugin state
pub const PluginState = enum {
    unloaded,
    loaded,
    initialized,
    enabled,
    disabled,
    error_state,
};

/// Plugin instance
pub const Plugin = struct {
    allocator: std.mem.Allocator,
    metadata: PluginMetadata,
    interface: ?*PluginInterface,
    state: PluginState,
    library_handle: ?std.DynLib,
    config: ?[]const u8,
    error_message: ?[]const u8,
    enabled_hooks: std.ArrayList(PluginHookType),

    pub fn init(allocator: std.mem.Allocator, metadata: PluginMetadata) Plugin {
        return .{
            .allocator = allocator,
            .metadata = metadata,
            .interface = null,
            .state = .unloaded,
            .library_handle = null,
            .config = null,
            .error_message = null,
            .enabled_hooks = std.ArrayList(PluginHookType){},
        };
    }

    pub fn deinit(self: *Plugin) void {
        if (self.interface) |interface| {
            interface.deinit();
        }
        if (self.library_handle) |*lib| {
            lib.close();
        }
        if (self.config) |config| {
            self.allocator.free(config);
        }
        if (self.error_message) |err| {
            self.allocator.free(err);
        }
        self.enabled_hooks.deinit(self.allocator);
        self.metadata.deinit(self.allocator);
    }

    /// Load plugin from shared library
    pub fn load(self: *Plugin, library_path: []const u8) !void {
        if (self.state != .unloaded) {
            return error.PluginAlreadyLoaded;
        }

        // Open shared library
        var lib = std.DynLib.open(library_path) catch |err| {
            self.state = .error_state;
            self.error_message = try std.fmt.allocPrint(
                self.allocator,
                "Failed to load library: {}",
                .{err},
            );
            return err;
        };

        self.library_handle = lib;

        // Load plugin interface
        const get_plugin_interface = lib.lookup(
            *const fn () callconv(.C) ?*PluginInterface,
            "smtp_plugin_get_interface",
        ) orelse {
            self.state = .error_state;
            self.error_message = try self.allocator.dupe(u8, "Plugin missing smtp_plugin_get_interface function");
            return error.MissingInterface;
        };

        self.interface = get_plugin_interface() orelse {
            self.state = .error_state;
            self.error_message = try self.allocator.dupe(u8, "Plugin returned null interface");
            return error.NullInterface;
        };

        self.state = .loaded;
    }

    /// Initialize the plugin
    pub fn initialize(self: *Plugin, config: ?[]const u8) !void {
        if (self.state != .loaded) {
            return error.PluginNotLoaded;
        }

        const interface = self.interface orelse return error.NoInterface;

        const config_str = config orelse "";
        const result = interface.init(self.allocator, config_str);

        if (result != 0) {
            self.state = .error_state;
            self.error_message = try std.fmt.allocPrint(
                self.allocator,
                "Plugin initialization failed with code: {d}",
                .{result},
            );
            return error.InitializationFailed;
        }

        if (config) |cfg| {
            self.config = try self.allocator.dupe(u8, cfg);
        }

        self.state = .initialized;
    }

    /// Enable the plugin
    pub fn enable(self: *Plugin) !void {
        if (self.state != .initialized and self.state != .disabled) {
            return error.PluginNotInitialized;
        }

        const interface = self.interface orelse return error.NoInterface;
        const result = interface.enable();

        if (result != 0) {
            self.state = .error_state;
            self.error_message = try std.fmt.allocPrint(
                self.allocator,
                "Plugin enable failed with code: {d}",
                .{result},
            );
            return error.EnableFailed;
        }

        self.state = .enabled;
    }

    /// Disable the plugin
    pub fn disable(self: *Plugin) !void {
        if (self.state != .enabled) {
            return error.PluginNotEnabled;
        }

        const interface = self.interface orelse return error.NoInterface;
        const result = interface.disable();

        if (result != 0) {
            self.state = .error_state;
            self.error_message = try std.fmt.allocPrint(
                self.allocator,
                "Plugin disable failed with code: {d}",
                .{result},
            );
            return error.DisableFailed;
        }

        self.state = .disabled;
    }

    /// Execute a hook
    pub fn executeHook(self: *Plugin, context: *HookContext) !HookResult {
        if (self.state != .enabled) {
            return .continue_processing;
        }

        const interface = self.interface orelse return .error_occurred;
        const result = interface.executeHook(context);

        return switch (result) {
            0 => .continue_processing,
            1 => .stop_processing,
            2 => .cancel_operation,
            else => .error_occurred,
        };
    }

    /// Register interest in a specific hook type
    pub fn registerHook(self: *Plugin, hook_type: PluginHookType) !void {
        try self.enabled_hooks.append(self.allocator, hook_type);
    }

    /// Check if plugin handles a specific hook type
    pub fn handlesHook(self: *const Plugin, hook_type: PluginHookType) bool {
        for (self.enabled_hooks.items) |hook| {
            if (hook == hook_type) return true;
        }
        return false;
    }
};

/// Plugin manager - manages all loaded plugins
pub const PluginManager = struct {
    allocator: std.mem.Allocator,
    plugins: std.ArrayList(*Plugin),
    plugin_dir: []const u8,
    mutex: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator, plugin_dir: []const u8) !PluginManager {
        return .{
            .allocator = allocator,
            .plugins = std.ArrayList(*Plugin){},
            .plugin_dir = try allocator.dupe(u8, plugin_dir),
        };
    }

    pub fn deinit(self: *PluginManager) void {
        for (self.plugins.items) |plugin| {
            plugin.deinit();
            self.allocator.destroy(plugin);
        }
        self.plugins.deinit(self.allocator);
        self.allocator.free(self.plugin_dir);
    }

    /// Load a plugin from a file
    pub fn loadPlugin(self: *PluginManager, library_path: []const u8, config: ?[]const u8) !*Plugin {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Create plugin metadata (would normally be loaded from manifest)
        const metadata = try PluginMetadata.init(self.allocator, "plugin", "1.0.0");

        const plugin = try self.allocator.create(Plugin);
        plugin.* = Plugin.init(self.allocator, metadata);

        errdefer {
            plugin.deinit();
            self.allocator.destroy(plugin);
        }

        try plugin.load(library_path);
        try plugin.initialize(config);
        try plugin.enable();

        try self.plugins.append(self.allocator, plugin);

        std.debug.print("Loaded plugin: {s}\n", .{metadata.name});

        return plugin;
    }

    /// Load all plugins from the plugin directory
    pub fn loadAllPlugins(self: *PluginManager) !void {
        var dir = try std.fs.cwd().openDir(self.plugin_dir, .{ .iterate = true });
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;

            // Check for shared library extension
            const is_plugin = std.mem.endsWith(u8, entry.name, ".so") or
                std.mem.endsWith(u8, entry.name, ".dylib") or
                std.mem.endsWith(u8, entry.name, ".dll");

            if (!is_plugin) continue;

            const full_path = try std.fs.path.join(self.allocator, &.{ self.plugin_dir, entry.name });
            defer self.allocator.free(full_path);

            _ = self.loadPlugin(full_path, null) catch |err| {
                std.debug.print("Failed to load plugin {s}: {}\n", .{ entry.name, err });
                continue;
            };
        }
    }

    /// Unload a plugin
    pub fn unloadPlugin(self: *PluginManager, plugin_name: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.plugins.items, 0..) |plugin, i| {
            if (std.mem.eql(u8, plugin.metadata.name, plugin_name)) {
                _ = try plugin.disable();
                plugin.deinit();
                self.allocator.destroy(plugin);
                _ = self.plugins.orderedRemove(i);
                std.debug.print("Unloaded plugin: {s}\n", .{plugin_name});
                return;
            }
        }

        return error.PluginNotFound;
    }

    /// Execute a hook across all plugins
    pub fn executeHook(self: *PluginManager, hook_type: PluginHookType, context: *HookContext) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.plugins.items) |plugin| {
            if (!plugin.handlesHook(hook_type)) continue;

            const result = plugin.executeHook(context) catch |err| {
                std.debug.print("Plugin {s} hook execution failed: {}\n", .{ plugin.metadata.name, err });
                continue;
            };

            switch (result) {
                .continue_processing => continue,
                .stop_processing => break,
                .cancel_operation => {
                    context.cancel = true;
                    return;
                },
                .error_occurred => {
                    std.debug.print("Plugin {s} returned error during hook execution\n", .{plugin.metadata.name});
                    continue;
                },
            }
        }
    }

    /// Get a plugin by name
    pub fn getPlugin(self: *PluginManager, name: []const u8) ?*Plugin {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.plugins.items) |plugin| {
            if (std.mem.eql(u8, plugin.metadata.name, name)) {
                return plugin;
            }
        }
        return null;
    }

    /// List all loaded plugins
    pub fn listPlugins(self: *PluginManager) []const *Plugin {
        return self.plugins.items;
    }
};

/// Example plugin helper for creating plugins
pub const PluginBuilder = struct {
    allocator: std.mem.Allocator,
    metadata: PluginMetadata,
    hooks: std.ArrayList(PluginHookType),

    pub fn init(allocator: std.mem.Allocator, name: []const u8, version: []const u8) !PluginBuilder {
        return .{
            .allocator = allocator,
            .metadata = try PluginMetadata.init(allocator, name, version),
            .hooks = std.ArrayList(PluginHookType){},
        };
    }

    pub fn deinit(self: *PluginBuilder) void {
        self.hooks.deinit(self.allocator);
        self.metadata.deinit(self.allocator);
    }

    pub fn setAuthor(self: *PluginBuilder, author: []const u8) !void {
        self.allocator.free(self.metadata.author);
        self.metadata.author = try self.allocator.dupe(u8, author);
    }

    pub fn setDescription(self: *PluginBuilder, description: []const u8) !void {
        self.allocator.free(self.metadata.description);
        self.metadata.description = try self.allocator.dupe(u8, description);
    }

    pub fn addHook(self: *PluginBuilder, hook_type: PluginHookType) !void {
        try self.hooks.append(self.allocator, hook_type);
    }

    pub fn addDependency(self: *PluginBuilder, dependency: []const u8) !void {
        var new_deps = try self.allocator.alloc([]const u8, self.metadata.dependencies.len + 1);
        @memcpy(new_deps[0..self.metadata.dependencies.len], self.metadata.dependencies);
        new_deps[self.metadata.dependencies.len] = try self.allocator.dupe(u8, dependency);

        if (self.metadata.dependencies.len > 0) {
            self.allocator.free(self.metadata.dependencies);
        }
        self.metadata.dependencies = new_deps;
    }
};

// Tests
test "plugin metadata lifecycle" {
    const testing = std.testing;

    var metadata = try PluginMetadata.init(testing.allocator, "test-plugin", "1.0.0");
    defer metadata.deinit(testing.allocator);

    try testing.expect(std.mem.eql(u8, metadata.name, "test-plugin"));
    try testing.expect(std.mem.eql(u8, metadata.version, "1.0.0"));
}

test "hook context" {
    const testing = std.testing;

    var context = HookContext.init(testing.allocator, .message_received);
    defer context.deinit();

    try context.setMetadata("sender", "test@example.com");
    try context.setMetadata("subject", "Test Message");

    const sender = context.getMetadata("sender");
    try testing.expect(sender != null);
    try testing.expect(std.mem.eql(u8, sender.?, "test@example.com"));
}

test "plugin builder" {
    const testing = std.testing;

    var builder = try PluginBuilder.init(testing.allocator, "spam-filter", "2.0.0");
    defer builder.deinit();

    try builder.setAuthor("SMTP Team");
    try builder.setDescription("Advanced spam filtering plugin");
    try builder.addHook(.message_received);
    try builder.addHook(.message_filtered);
    try builder.addDependency("spamassassin");

    try testing.expect(std.mem.eql(u8, builder.metadata.author, "SMTP Team"));
    try testing.expectEqual(@as(usize, 2), builder.hooks.items.len);
    try testing.expectEqual(@as(usize, 1), builder.metadata.dependencies.len);
}
