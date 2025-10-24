const std = @import("std");

/// Multi-tenancy support for SMTP server
/// Enables multiple isolated organizations to share the same infrastructure
/// Each tenant has isolated data, quotas, and configuration

/// Tenant information
pub const Tenant = struct {
    id: []const u8,
    name: []const u8,
    domain: []const u8,
    enabled: bool,
    created_at: i64,
    updated_at: i64,

    // Resource limits
    max_users: u32,
    max_domains: u32,
    max_storage_mb: u64,
    max_messages_per_day: u32,

    // Features enabled
    features: TenantFeatures,

    // Metadata
    metadata: ?[]const u8, // JSON string

    allocator: std.mem.Allocator,

    pub fn deinit(self: *Tenant, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.domain);
        if (self.metadata) |metadata| {
            allocator.free(metadata);
        }
    }
};

/// Features that can be enabled per tenant
pub const TenantFeatures = struct {
    spam_filtering: bool = true,
    virus_scanning: bool = true,
    dkim_signing: bool = true,
    mailing_lists: bool = false,
    webhooks: bool = false,
    api_access: bool = true,
    custom_domains: bool = false,
    priority_support: bool = false,
};

/// Tenant tier/plan
pub const TenantTier = enum {
    free,
    starter,
    professional,
    enterprise,

    pub fn getLimits(self: TenantTier) TenantLimits {
        return switch (self) {
            .free => TenantLimits{
                .max_users = 5,
                .max_domains = 1,
                .max_storage_mb = 1024, // 1 GB
                .max_messages_per_day = 100,
            },
            .starter => TenantLimits{
                .max_users = 25,
                .max_domains = 3,
                .max_storage_mb = 10240, // 10 GB
                .max_messages_per_day = 1000,
            },
            .professional => TenantLimits{
                .max_users = 100,
                .max_domains = 10,
                .max_storage_mb = 102400, // 100 GB
                .max_messages_per_day = 10000,
            },
            .enterprise => TenantLimits{
                .max_users = 0, // unlimited
                .max_domains = 0, // unlimited
                .max_storage_mb = 0, // unlimited
                .max_messages_per_day = 0, // unlimited
            },
        };
    }

    pub fn getFeatures(self: TenantTier) TenantFeatures {
        return switch (self) {
            .free => TenantFeatures{
                .spam_filtering = true,
                .virus_scanning = false,
                .dkim_signing = false,
                .mailing_lists = false,
                .webhooks = false,
                .api_access = false,
                .custom_domains = false,
                .priority_support = false,
            },
            .starter => TenantFeatures{
                .spam_filtering = true,
                .virus_scanning = true,
                .dkim_signing = true,
                .mailing_lists = false,
                .webhooks = false,
                .api_access = true,
                .custom_domains = false,
                .priority_support = false,
            },
            .professional => TenantFeatures{
                .spam_filtering = true,
                .virus_scanning = true,
                .dkim_signing = true,
                .mailing_lists = true,
                .webhooks = true,
                .api_access = true,
                .custom_domains = true,
                .priority_support = false,
            },
            .enterprise => TenantFeatures{
                .spam_filtering = true,
                .virus_scanning = true,
                .dkim_signing = true,
                .mailing_lists = true,
                .webhooks = true,
                .api_access = true,
                .custom_domains = true,
                .priority_support = true,
            },
        };
    }
};

pub const TenantLimits = struct {
    max_users: u32,
    max_domains: u32,
    max_storage_mb: u64,
    max_messages_per_day: u32,
};

/// Tenant context for request handling
pub const TenantContext = struct {
    tenant_id: []const u8,
    tenant: *Tenant,
    user_id: ?[]const u8,

    pub fn init(tenant_id: []const u8, tenant: *Tenant, user_id: ?[]const u8) TenantContext {
        return .{
            .tenant_id = tenant_id,
            .tenant = tenant,
            .user_id = user_id,
        };
    }
};

const TenantDB = @import("../storage/tenant_db.zig").TenantDB;

/// Multi-tenancy manager
pub const MultiTenancyManager = struct {
    allocator: std.mem.Allocator,
    db: *TenantDB,
    tenant_cache: std.StringHashMap(*Tenant),
    cache_mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, db: *TenantDB) !*MultiTenancyManager {
        const manager = try allocator.create(MultiTenancyManager);
        manager.* = .{
            .allocator = allocator,
            .db = db,
            .tenant_cache = std.StringHashMap(*Tenant).init(allocator),
            .cache_mutex = std.Thread.Mutex{},
        };
        return manager;
    }

    pub fn deinit(self: *MultiTenancyManager) void {
        // Clear cache
        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();

        var iter = self.tenant_cache.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.tenant_cache.deinit();

        self.allocator.destroy(self);
    }

    /// Get tenant by ID
    pub fn getTenant(self: *MultiTenancyManager, tenant_id: []const u8) !*Tenant {
        // Check cache first
        self.cache_mutex.lock();
        if (self.tenant_cache.get(tenant_id)) |tenant| {
            self.cache_mutex.unlock();
            return tenant;
        }
        self.cache_mutex.unlock();

        // Load from database
        const tenant_opt = try self.db.getTenant(tenant_id);
        if (tenant_opt) |tenant_data| {
            const tenant = try self.allocator.create(Tenant);
            tenant.* = tenant_data;

            // Add to cache
            self.cache_mutex.lock();
            defer self.cache_mutex.unlock();
            try self.tenant_cache.put(try self.allocator.dupe(u8, tenant_id), tenant);

            return tenant;
        }

        return error.TenantNotFound;
    }

    /// Get tenant by domain
    pub fn getTenantByDomain(self: *MultiTenancyManager, domain: []const u8) !*Tenant {
        // Load from database
        const tenant_opt = try self.db.getTenantByDomain(domain);
        if (tenant_opt) |tenant_data| {
            const tenant = try self.allocator.create(Tenant);
            tenant.* = tenant_data;

            // Add to cache
            self.cache_mutex.lock();
            defer self.cache_mutex.unlock();
            try self.tenant_cache.put(try self.allocator.dupe(u8, tenant_data.id), tenant);

            return tenant;
        }

        return error.TenantNotFound;
    }

    /// Create new tenant
    pub fn createTenant(
        self: *MultiTenancyManager,
        name: []const u8,
        domain: []const u8,
        tier: TenantTier,
    ) !*Tenant {
        const tenant_id = try self.generateTenantId();
        defer self.allocator.free(tenant_id);

        const limits = tier.getLimits();
        const features = tier.getFeatures();

        const tenant = try self.allocator.create(Tenant);
        tenant.* = .{
            .id = try self.allocator.dupe(u8, tenant_id),
            .name = try self.allocator.dupe(u8, name),
            .domain = try self.allocator.dupe(u8, domain),
            .enabled = true,
            .created_at = std.time.timestamp(),
            .updated_at = std.time.timestamp(),
            .max_users = limits.max_users,
            .max_domains = limits.max_domains,
            .max_storage_mb = limits.max_storage_mb,
            .max_messages_per_day = limits.max_messages_per_day,
            .features = features,
            .metadata = null,
            .allocator = self.allocator,
        };

        // Save to database
        try self.db.createTenant(tenant);

        // Add to cache
        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();
        try self.tenant_cache.put(try self.allocator.dupe(u8, tenant_id), tenant);

        return tenant;
    }

    /// Update tenant
    pub fn updateTenant(self: *MultiTenancyManager, tenant: *Tenant) !void {
        tenant.updated_at = std.time.timestamp();

        // Update in database
        try self.db.updateTenant(tenant);

        // Update cache
        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();

        if (self.tenant_cache.get(tenant.id)) |cached_tenant| {
            // Update cached tenant
            cached_tenant.name = try self.allocator.dupe(u8, tenant.name);
            cached_tenant.domain = try self.allocator.dupe(u8, tenant.domain);
            cached_tenant.enabled = tenant.enabled;
            cached_tenant.updated_at = tenant.updated_at;
            cached_tenant.max_users = tenant.max_users;
            cached_tenant.max_domains = tenant.max_domains;
            cached_tenant.max_storage_mb = tenant.max_storage_mb;
            cached_tenant.max_messages_per_day = tenant.max_messages_per_day;
            cached_tenant.features = tenant.features;
        }
    }

    /// Delete tenant
    pub fn deleteTenant(self: *MultiTenancyManager, tenant_id: []const u8) !void {
        // Delete from database
        try self.db.deleteTenant(tenant_id);

        // Remove from cache
        self.cache_mutex.lock();
        defer self.cache_mutex.unlock();

        if (self.tenant_cache.fetchRemove(tenant_id)) |entry| {
            entry.value.deinit(self.allocator);
            self.allocator.destroy(entry.value);
        }
    }

    /// Check if tenant has reached limit
    pub fn checkLimit(self: *MultiTenancyManager, tenant_id: []const u8, limit_type: LimitType) !bool {
        const tenant = try self.getTenant(tenant_id);

        return switch (limit_type) {
            .users => tenant.max_users == 0 or try self.getUserCount(tenant_id) < tenant.max_users,
            .domains => tenant.max_domains == 0 or try self.getDomainCount(tenant_id) < tenant.max_domains,
            .storage => tenant.max_storage_mb == 0 or try self.getStorageUsageMB(tenant_id) < tenant.max_storage_mb,
            .messages_per_day => tenant.max_messages_per_day == 0 or try self.getTodayMessageCount(tenant_id) < tenant.max_messages_per_day,
        };
    }

    /// Generate unique tenant ID
    fn generateTenantId(self: *MultiTenancyManager) ![]const u8 {
        var buf: [16]u8 = undefined;
        std.crypto.random.bytes(&buf);

        const id = try std.fmt.allocPrint(
            self.allocator,
            "tenant_{s}",
            .{std.fmt.fmtSliceHexLower(&buf)},
        );

        return id;
    }

    // Database-backed usage tracking methods
    fn getUserCount(self: *MultiTenancyManager, tenant_id: []const u8) !u32 {
        return try self.db.getUserCount(tenant_id);
    }

    fn getDomainCount(self: *MultiTenancyManager, tenant_id: []const u8) !u32 {
        return try self.db.getDomainCount(tenant_id);
    }

    fn getStorageUsageMB(self: *MultiTenancyManager, tenant_id: []const u8) !u64 {
        return try self.db.getStorageUsageMB(tenant_id);
    }

    fn getTodayMessageCount(self: *MultiTenancyManager, tenant_id: []const u8) !u32 {
        return try self.db.getTodayMessageCount(tenant_id);
    }
};

pub const LimitType = enum {
    users,
    domains,
    storage,
    messages_per_day,
};

/// Tenant isolation helper
pub const TenantIsolation = struct {
    /// Add tenant filter to SQL WHERE clause
    pub fn addTenantFilter(query: []const u8, tenant_id: []const u8, allocator: std.mem.Allocator) ![]const u8 {
        if (std.mem.indexOf(u8, query, "WHERE")) |_| {
            return try std.fmt.allocPrint(
                allocator,
                "{s} AND tenant_id = '{s}'",
                .{ query, tenant_id },
            );
        } else {
            return try std.fmt.allocPrint(
                allocator,
                "{s} WHERE tenant_id = '{s}'",
                .{ query, tenant_id },
            );
        }
    }

    /// Validate tenant access to resource
    pub fn validateAccess(tenant_id: []const u8, resource_tenant_id: []const u8) !void {
        if (!std.mem.eql(u8, tenant_id, resource_tenant_id)) {
            return error.UnauthorizedTenantAccess;
        }
    }
};

test "tenant tier limits" {
    const free_limits = TenantTier.free.getLimits();
    try std.testing.expectEqual(@as(u32, 5), free_limits.max_users);
    try std.testing.expectEqual(@as(u32, 1), free_limits.max_domains);

    const enterprise_limits = TenantTier.enterprise.getLimits();
    try std.testing.expectEqual(@as(u32, 0), enterprise_limits.max_users); // unlimited
}

test "tenant features by tier" {
    const free_features = TenantTier.free.getFeatures();
    try std.testing.expect(free_features.spam_filtering);
    try std.testing.expect(!free_features.webhooks);

    const enterprise_features = TenantTier.enterprise.getFeatures();
    try std.testing.expect(enterprise_features.priority_support);
}
