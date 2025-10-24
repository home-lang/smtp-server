const std = @import("std");

/// Cluster mode for high availability SMTP server
/// Provides distributed coordination, state sharing, and failover capabilities

/// Cluster node information
pub const ClusterNode = struct {
    id: []const u8,
    address: []const u8,
    port: u16,
    role: NodeRole,
    status: NodeStatus,
    last_heartbeat: i64,
    metadata: NodeMetadata,

    allocator: std.mem.Allocator,

    pub fn deinit(self: *ClusterNode, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.address);
        self.metadata.deinit(allocator);
    }
};

pub const NodeRole = enum {
    leader, // Coordinates cluster activities
    follower, // Regular worker node
    candidate, // Node trying to become leader

    pub fn toString(self: NodeRole) []const u8 {
        return switch (self) {
            .leader => "leader",
            .follower => "follower",
            .candidate => "candidate",
        };
    }
};

pub const NodeStatus = enum {
    healthy,
    degraded,
    unhealthy,
    disconnected,

    pub fn toString(self: NodeStatus) []const u8 {
        return switch (self) {
            .healthy => "healthy",
            .degraded => "degraded",
            .unhealthy => "unhealthy",
            .disconnected => "disconnected",
        };
    }
};

pub const NodeMetadata = struct {
    version: []const u8,
    uptime_seconds: u64,
    active_connections: u32,
    messages_processed: u64,
    cpu_usage: f32,
    memory_usage_mb: u64,

    allocator: std.mem.Allocator,

    pub fn deinit(self: *NodeMetadata, allocator: std.mem.Allocator) void {
        allocator.free(self.version);
        _ = allocator;
    }
};

/// Cluster configuration
pub const ClusterConfig = struct {
    node_id: []const u8,
    bind_address: []const u8,
    bind_port: u16,
    peers: [][]const u8, // List of peer addresses
    heartbeat_interval_ms: u32 = 5000,
    heartbeat_timeout_ms: u32 = 15000,
    leader_election_timeout_ms: u32 = 10000,
    enable_auto_discovery: bool = false,
};

/// Cluster manager
pub const ClusterManager = struct {
    allocator: std.mem.Allocator,
    config: ClusterConfig,
    local_node: *ClusterNode,
    nodes: std.StringHashMap(*ClusterNode),
    nodes_mutex: std.Thread.Mutex,
    state_store: *DistributedStateStore,
    heartbeat_thread: ?std.Thread = null,
    running: std.atomic.Value(bool),

    pub fn init(allocator: std.mem.Allocator, config: ClusterConfig) !*ClusterManager {
        const manager = try allocator.create(ClusterManager);

        // Create local node
        const local_node = try allocator.create(ClusterNode);
        local_node.* = .{
            .id = try allocator.dupe(u8, config.node_id),
            .address = try allocator.dupe(u8, config.bind_address),
            .port = config.bind_port,
            .role = .follower, // Start as follower
            .status = .healthy,
            .last_heartbeat = std.time.timestamp(),
            .metadata = .{
                .version = try allocator.dupe(u8, "v0.26.0"),
                .uptime_seconds = 0,
                .active_connections = 0,
                .messages_processed = 0,
                .cpu_usage = 0.0,
                .memory_usage_mb = 0,
                .allocator = allocator,
            },
            .allocator = allocator,
        };

        manager.* = .{
            .allocator = allocator,
            .config = config,
            .local_node = local_node,
            .nodes = std.StringHashMap(*ClusterNode).init(allocator),
            .nodes_mutex = std.Thread.Mutex{},
            .state_store = try DistributedStateStore.init(allocator),
            .running = std.atomic.Value(bool).init(false),
        };

        return manager;
    }

    pub fn deinit(self: *ClusterManager) void {
        self.stop();

        self.local_node.deinit(self.allocator);
        self.allocator.destroy(self.local_node);

        // Clean up nodes
        self.nodes_mutex.lock();
        var iter = self.nodes.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.nodes.deinit();
        self.nodes_mutex.unlock();

        self.state_store.deinit();
        self.allocator.destroy(self);
    }

    /// Start cluster operations
    pub fn start(self: *ClusterManager) !void {
        self.running.store(true, .release);

        // Start heartbeat thread
        self.heartbeat_thread = try std.Thread.spawn(.{}, heartbeatLoop, .{self});

        // Discover peers if enabled
        if (self.config.enable_auto_discovery) {
            try self.discoverPeers();
        } else {
            try self.connectToPeers();
        }

        std.log.info("Cluster manager started - Node ID: {s}, Role: {s}", .{
            self.local_node.id,
            self.local_node.role.toString(),
        });
    }

    /// Stop cluster operations
    pub fn stop(self: *ClusterManager) void {
        self.running.store(false, .release);

        if (self.heartbeat_thread) |thread| {
            thread.join();
            self.heartbeat_thread = null;
        }

        std.log.info("Cluster manager stopped", .{});
    }

    /// Heartbeat loop
    fn heartbeatLoop(self: *ClusterManager) void {
        while (self.running.load(.acquire)) {
            self.sendHeartbeat() catch |err| {
                std.log.err("Heartbeat failed: {}", .{err});
            };

            self.checkNodeHealth() catch |err| {
                std.log.err("Health check failed: {}", .{err});
            };

            std.time.sleep(self.config.heartbeat_interval_ms * std.time.ns_per_ms);
        }
    }

    /// Send heartbeat to all nodes
    fn sendHeartbeat(self: *ClusterManager) !void {
        self.local_node.last_heartbeat = std.time.timestamp();

        self.nodes_mutex.lock();
        defer self.nodes_mutex.unlock();

        var iter = self.nodes.iterator();
        while (iter.next()) |entry| {
            const node = entry.value_ptr.*;
            // TODO: Send actual heartbeat message over network
            _ = node;
        }
    }

    /// Check health of all nodes
    fn checkNodeHealth(self: *ClusterManager) !void {
        const now = std.time.timestamp();
        const timeout = @divFloor(self.config.heartbeat_timeout_ms, 1000);

        self.nodes_mutex.lock();
        defer self.nodes_mutex.unlock();

        var iter = self.nodes.iterator();
        while (iter.next()) |entry| {
            const node = entry.value_ptr.*;
            const elapsed = now - node.last_heartbeat;

            if (elapsed > timeout) {
                node.status = .disconnected;
                std.log.warn("Node {s} marked as disconnected (last heartbeat: {d}s ago)", .{
                    node.id,
                    elapsed,
                });

                // Trigger leader election if leader is disconnected
                if (node.role == .leader) {
                    try self.startLeaderElection();
                }
            }
        }
    }

    /// Discover peers automatically
    fn discoverPeers(self: *ClusterManager) !void {
        // TODO: Implement service discovery (e.g., via DNS, Consul, etcd)
        _ = self;
        std.log.info("Auto-discovery not yet implemented", .{});
    }

    /// Connect to configured peers
    fn connectToPeers(self: *ClusterManager) !void {
        for (self.config.peers) |peer_address| {
            try self.addPeer(peer_address);
        }
    }

    /// Add peer node
    fn addPeer(self: *ClusterManager, address: []const u8) !void {
        // Parse address (format: "host:port")
        const colon_pos = std.mem.indexOf(u8, address, ":") orelse return error.InvalidPeerAddress;
        const host = address[0..colon_pos];
        const port_str = address[colon_pos + 1 ..];
        const port = try std.fmt.parseInt(u16, port_str, 10);

        // Generate node ID from address
        const node_id = try std.fmt.allocPrint(
            self.allocator,
            "node_{s}_{d}",
            .{ host, port },
        );
        defer self.allocator.free(node_id);

        const node = try self.allocator.create(ClusterNode);
        node.* = .{
            .id = try self.allocator.dupe(u8, node_id),
            .address = try self.allocator.dupe(u8, host),
            .port = port,
            .role = .follower,
            .status = .healthy,
            .last_heartbeat = std.time.timestamp(),
            .metadata = .{
                .version = try self.allocator.dupe(u8, "unknown"),
                .uptime_seconds = 0,
                .active_connections = 0,
                .messages_processed = 0,
                .cpu_usage = 0.0,
                .memory_usage_mb = 0,
                .allocator = self.allocator,
            },
            .allocator = self.allocator,
        };

        self.nodes_mutex.lock();
        defer self.nodes_mutex.unlock();
        try self.nodes.put(try self.allocator.dupe(u8, node_id), node);

        std.log.info("Added peer node: {s} ({s}:{d})", .{ node_id, host, port });
    }

    /// Start leader election
    fn startLeaderElection(self: *ClusterManager) !void {
        if (self.local_node.role == .leader) {
            return; // Already leader
        }

        std.log.info("Starting leader election", .{});

        self.local_node.role = .candidate;

        // Simple election: node with lowest ID wins
        // In production, use Raft or similar consensus algorithm
        var lowest_id = self.local_node.id;

        self.nodes_mutex.lock();
        var iter = self.nodes.iterator();
        while (iter.next()) |entry| {
            const node = entry.value_ptr.*;
            if (node.status == .healthy or node.status == .degraded) {
                if (std.mem.lessThan(u8, node.id, lowest_id)) {
                    lowest_id = node.id;
                }
            }
        }
        self.nodes_mutex.unlock();

        if (std.mem.eql(u8, lowest_id, self.local_node.id)) {
            self.local_node.role = .leader;
            std.log.info("Node elected as LEADER", .{});
        } else {
            self.local_node.role = .follower;
            std.log.info("Node remains as FOLLOWER (leader: {s})", .{lowest_id});
        }
    }

    /// Get current leader
    pub fn getLeader(self: *ClusterManager) !*ClusterNode {
        if (self.local_node.role == .leader) {
            return self.local_node;
        }

        self.nodes_mutex.lock();
        defer self.nodes_mutex.unlock();

        var iter = self.nodes.iterator();
        while (iter.next()) |entry| {
            const node = entry.value_ptr.*;
            if (node.role == .leader and (node.status == .healthy or node.status == .degraded)) {
                return node;
            }
        }

        return error.NoLeaderAvailable;
    }

    /// Get cluster statistics
    pub fn getStats(self: *ClusterManager) ClusterStats {
        self.nodes_mutex.lock();
        defer self.nodes_mutex.unlock();

        var stats = ClusterStats{
            .total_nodes = 1, // Include local node
            .healthy_nodes = if (self.local_node.status == .healthy) @as(u32, 1) else 0,
            .leader_node_id = if (self.local_node.role == .leader) self.local_node.id else null,
            .total_connections = self.local_node.metadata.active_connections,
            .total_messages_processed = self.local_node.metadata.messages_processed,
        };

        var iter = self.nodes.iterator();
        while (iter.next()) |entry| {
            const node = entry.value_ptr.*;
            stats.total_nodes += 1;
            if (node.status == .healthy) {
                stats.healthy_nodes += 1;
            }
            if (node.role == .leader) {
                stats.leader_node_id = node.id;
            }
            stats.total_connections += node.metadata.active_connections;
            stats.total_messages_processed += node.metadata.messages_processed;
        }

        return stats;
    }
};

pub const ClusterStats = struct {
    total_nodes: u32,
    healthy_nodes: u32,
    leader_node_id: ?[]const u8,
    total_connections: u32,
    total_messages_processed: u64,
};

/// Distributed state store for sharing state across cluster
pub const DistributedStateStore = struct {
    allocator: std.mem.Allocator,
    data: std.StringHashMap([]const u8),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) !*DistributedStateStore {
        const store = try allocator.create(DistributedStateStore);
        store.* = .{
            .allocator = allocator,
            .data = std.StringHashMap([]const u8).init(allocator),
            .mutex = std.Thread.Mutex{},
        };
        return store;
    }

    pub fn deinit(self: *DistributedStateStore) void {
        self.mutex.lock();
        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.deinit();
        self.mutex.unlock();

        self.allocator.destroy(self);
    }

    /// Set key-value pair
    pub fn set(self: *DistributedStateStore, key: []const u8, value: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const key_copy = try self.allocator.dupe(u8, key);
        const value_copy = try self.allocator.dupe(u8, value);

        // Free old value if exists
        if (self.data.get(key)) |old_value| {
            self.allocator.free(old_value);
        }

        try self.data.put(key_copy, value_copy);

        // TODO: Replicate to other nodes
    }

    /// Get value by key
    pub fn get(self: *DistributedStateStore, key: []const u8) ![]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.data.get(key)) |value| {
            return try self.allocator.dupe(u8, value);
        }

        return error.KeyNotFound;
    }

    /// Delete key
    pub fn delete(self: *DistributedStateStore, key: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.data.fetchRemove(key)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value);
        }

        // TODO: Replicate deletion to other nodes
    }

    /// Check if key exists
    pub fn exists(self: *DistributedStateStore, key: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.data.contains(key);
    }
};

/// Cluster-aware rate limiter
pub const ClusterRateLimiter = struct {
    local_counts: std.StringHashMap(u32),
    state_store: *DistributedStateStore,
    mutex: std.Thread.Mutex,

    pub fn init(state_store: *DistributedStateStore, allocator: std.mem.Allocator) ClusterRateLimiter {
        return .{
            .local_counts = std.StringHashMap(u32).init(allocator),
            .state_store = state_store,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *ClusterRateLimiter) void {
        self.local_counts.deinit();
    }

    /// Check and increment rate limit across cluster
    pub fn checkAndIncrement(self: *ClusterRateLimiter, key: []const u8, limit: u32) !bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Get global count from distributed store
        const global_count_str = self.state_store.get(key) catch "0";
        defer self.state_store.allocator.free(global_count_str);

        const global_count = try std.fmt.parseInt(u32, global_count_str, 10);

        if (global_count >= limit) {
            return false; // Rate limit exceeded
        }

        // Increment global count
        const new_count = global_count + 1;
        const new_count_str = try std.fmt.allocPrint(
            self.state_store.allocator,
            "{d}",
            .{new_count},
        );
        defer self.state_store.allocator.free(new_count_str);

        try self.state_store.set(key, new_count_str);

        return true;
    }
};

test "cluster manager initialization" {
    const allocator = std.testing.allocator;

    const config = ClusterConfig{
        .node_id = "test-node-1",
        .bind_address = "127.0.0.1",
        .bind_port = 5000,
        .peers = &[_][]const u8{},
    };

    const manager = try ClusterManager.init(allocator, config);
    defer manager.deinit();

    try std.testing.expectEqualStrings("test-node-1", manager.local_node.id);
    try std.testing.expectEqual(NodeRole.follower, manager.local_node.role);
}

test "distributed state store" {
    const allocator = std.testing.allocator;

    const store = try DistributedStateStore.init(allocator);
    defer store.deinit();

    try store.set("key1", "value1");
    const value = try store.get("key1");
    defer allocator.free(value);

    try std.testing.expectEqualStrings("value1", value);

    try std.testing.expect(store.exists("key1"));
    try std.testing.expect(!store.exists("nonexistent"));
}
