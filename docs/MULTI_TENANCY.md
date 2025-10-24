# Multi-Tenancy Guide

This guide explains how to configure and use the multi-tenancy features in the SMTP server.

## Overview

Multi-tenancy enables multiple isolated organizations to share the same SMTP infrastructure while maintaining complete data isolation, resource limits, and feature sets per tenant.

## Features

- **Complete Tenant Isolation**: Each tenant's data is isolated at the database level
- **Resource Limits**: Configure per-tenant limits for users, domains, storage, and messages
- **Feature Flags**: Enable/disable features per tenant tier
- **Tenant Tiers**: Four built-in tiers with progressive capabilities
- **Usage Tracking**: Monitor tenant resource usage in real-time
- **REST API**: Full CRUD operations for tenant management

## Tenant Tiers

### Free Tier
- **Max Users**: 5
- **Max Domains**: 1
- **Storage**: 1 GB
- **Messages/Day**: 100
- **Features**: Basic spam filtering only

### Starter Tier
- **Max Users**: 25
- **Max Domains**: 3
- **Storage**: 10 GB
- **Messages/Day**: 1,000
- **Features**: Spam filtering, virus scanning, DKIM signing, API access

### Professional Tier
- **Max Users**: 100
- **Max Domains**: 10
- **Storage**: 100 GB
- **Messages/Day**: 10,000
- **Features**: All starter features plus mailing lists, webhooks, custom domains

### Enterprise Tier
- **Max Users**: Unlimited
- **Max Domains**: Unlimited
- **Storage**: Unlimited
- **Messages/Day**: Unlimited
- **Features**: All features including priority support

## Database Schema

### Initial Setup

1. **Create the multi-tenancy schema**:

```bash
sqlite3 smtp_server.db < sql/schema_multitenancy.sql
```

2. **Create a default tenant**:

```sql
INSERT INTO tenants (id, name, domain, enabled, created_at, updated_at, tier, max_users, max_domains, max_storage_mb, max_messages_per_day, features)
VALUES ('default', 'Default Organization', 'example.com', 1, strftime('%s', 'now'), strftime('%s', 'now'), 'enterprise', 0, 0, 0, 0,
  '{"spam_filtering":true,"virus_scanning":true,"dkim_signing":true,"mailing_lists":true,"webhooks":true,"api_access":true,"custom_domains":true,"priority_support":true}');
```

3. **Migrate existing users** (if any):

```sql
-- Add tenant_id to existing users
ALTER TABLE users ADD COLUMN tenant_id TEXT REFERENCES tenants(id);

-- Assign to default tenant
UPDATE users SET tenant_id = 'default' WHERE tenant_id IS NULL;
```

## REST API

### List All Tenants

```bash
curl http://localhost:8080/api/tenants
```

**Response**:
```json
{
  "tenants": [
    {
      "id": "tenant_abc123",
      "name": "Acme Corp",
      "domain": "acme.example.com",
      "enabled": true,
      "created_at": 1234567890,
      "max_users": 25,
      "max_domains": 3,
      "max_storage_mb": 10240,
      "max_messages_per_day": 1000
    }
  ]
}
```

### Get Single Tenant

```bash
curl http://localhost:8080/api/tenants/tenant_abc123
```

**Response**:
```json
{
  "id": "tenant_abc123",
  "name": "Acme Corp",
  "domain": "acme.example.com",
  "enabled": true,
  "created_at": 1234567890,
  "updated_at": 1234567890,
  "max_users": 25,
  "max_domains": 3,
  "max_storage_mb": 10240,
  "max_messages_per_day": 1000,
  "features": {
    "spam_filtering": true,
    "virus_scanning": true,
    "dkim_signing": true,
    "mailing_lists": false,
    "webhooks": false,
    "api_access": true,
    "custom_domains": false,
    "priority_support": false
  }
}
```

### Create Tenant

```bash
curl -X POST http://localhost:8080/api/tenants \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Acme Corp",
    "domain": "acme.example.com",
    "tier": "starter"
  }'
```

**Response**:
```json
{
  "id": "tenant_abc123",
  "name": "Acme Corp",
  "domain": "acme.example.com",
  "tier": "starter",
  "created_at": 1234567890
}
```

### Update Tenant

```bash
curl -X PUT http://localhost:8080/api/tenants/tenant_abc123 \
  -H "Content-Type: application/json" \
  -d '{
    "max_users": 50,
    "enabled": true
  }'
```

**Response**:
```json
{
  "success": true
}
```

### Delete Tenant

```bash
curl -X DELETE http://localhost:8080/api/tenants/tenant_abc123
```

**Response**:
```json
{
  "success": true
}
```

### Get Tenant Usage

```bash
curl http://localhost:8080/api/tenants/tenant_abc123/usage
```

**Response**:
```json
{
  "tenant_id": "tenant_abc123",
  "usage": {
    "users": 12,
    "domains": 2,
    "storage_mb": 2048,
    "messages_today": 45
  },
  "limits": {
    "max_users": 25,
    "max_domains": 3,
    "max_storage_mb": 10240,
    "max_messages_per_day": 1000
  }
}
```

## Usage in Code

### Initialize Multi-Tenancy Manager

```zig
const multitenancy = @import("features/multitenancy.zig");
const TenantDB = @import("storage/tenant_db.zig").TenantDB;

// Initialize database
const tenant_db = try TenantDB.init(allocator, "smtp_server.db");
defer tenant_db.deinit();

// Initialize manager
const tenant_manager = try multitenancy.MultiTenancyManager.init(allocator, tenant_db);
defer tenant_manager.deinit();
```

### Create a Tenant

```zig
const tenant = try tenant_manager.createTenant(
    "Acme Corp",
    "acme.example.com",
    .starter, // TenantTier
);

std.log.info("Created tenant: {s}", .{tenant.id});
```

### Check Resource Limits

```zig
const can_add_user = try tenant_manager.checkLimit(tenant_id, .users);
if (!can_add_user) {
    return error.TenantUserLimitReached;
}
```

### Tenant-Aware Database Queries

```zig
const TenantIsolation = @import("features/multitenancy.zig").TenantIsolation;

// Add tenant filter to query
const base_query = "SELECT * FROM messages";
const filtered_query = try TenantIsolation.addTenantFilter(
    base_query,
    tenant_id,
    allocator,
);
// Result: "SELECT * FROM messages WHERE tenant_id = 'tenant_abc123'"
```

### Validate Access

```zig
// Ensure tenant can only access their own resources
try TenantIsolation.validateAccess(current_tenant_id, resource_tenant_id);
```

## Configuration

Add these environment variables:

```bash
# Enable multi-tenancy mode
export SMTP_MULTITENANCY_ENABLED=true

# Database path
export SMTP_DB_PATH="smtp_server.db"

# Default tenant for non-authenticated connections
export SMTP_DEFAULT_TENANT="default"
```

## Usage Tracking

The system automatically tracks:

- **Daily Message Counts**: Messages sent and received per day
- **Storage Usage**: Current storage used in MB
- **User Count**: Number of active users
- **Domain Count**: Number of configured domains

Usage data is stored in the `tenant_usage` table and updated automatically.

## Best Practices

### 1. Tenant Isolation

Always use tenant-aware queries:

```zig
// Good - Tenant isolated
const query = try TenantIsolation.addTenantFilter(
    "SELECT * FROM users",
    tenant_id,
    allocator,
);

// Bad - No isolation
const query = "SELECT * FROM users";
```

### 2. Limit Checking

Check limits before operations:

```zig
// Before adding a user
if (!try tenant_manager.checkLimit(tenant_id, .users)) {
    return error.TenantUserLimitReached;
}

// Before sending a message
if (!try tenant_manager.checkLimit(tenant_id, .messages_per_day)) {
    return error.TenantDailyLimitReached;
}
```

### 3. Feature Flags

Check feature availability:

```zig
const tenant = try tenant_manager.getTenant(tenant_id);

if (!tenant.features.webhooks) {
    return error.FeatureNotAvailable;
}
```

### 4. Error Handling

Handle tenant-specific errors:

```zig
const tenant = tenant_manager.getTenant(tenant_id) catch |err| {
    return switch (err) {
        error.TenantNotFound => handleTenantNotFound(),
        error.TenantDisabled => handleTenantDisabled(),
        else => err,
    };
};
```

## Monitoring

### Check Tenant Health

```bash
# Get tenant usage
curl http://localhost:8080/api/tenants/TENANT_ID/usage

# Check if approaching limits
# - users >= 80% of max_users
# - storage_mb >= 80% of max_storage_mb
# - messages_today >= 80% of max_messages_per_day
```

### Tenant Metrics

Monitor these metrics per tenant:

- Message throughput (messages/hour)
- Storage growth rate (MB/day)
- User activity (active users)
- Limit violations (rate limit hits)
- Error rates

## Migration

### From Single-Tenant to Multi-Tenant

1. **Backup your database**:

```bash
sqlite3 smtp_server.db ".backup smtp_server_backup.db"
```

2. **Apply multi-tenancy schema**:

```bash
sqlite3 smtp_server.db < sql/schema_multitenancy.sql
```

3. **Create default tenant**:

```sql
INSERT INTO tenants (id, name, domain, enabled, created_at, updated_at, tier)
VALUES ('default', 'Default', 'localhost', 1, strftime('%s', 'now'), strftime('%s', 'now'), 'enterprise');
```

4. **Migrate existing users**:

```sql
UPDATE users SET tenant_id = 'default' WHERE tenant_id IS NULL;
```

5. **Restart the server** with `SMTP_MULTITENANCY_ENABLED=true`

## Troubleshooting

### Issue: Tenant Not Found

**Cause**: Tenant doesn't exist or is disabled

**Solution**:
```bash
# Check if tenant exists
curl http://localhost:8080/api/tenants/TENANT_ID

# Enable tenant
curl -X PUT http://localhost:8080/api/tenants/TENANT_ID \
  -H "Content-Type: application/json" \
  -d '{"enabled": true}'
```

### Issue: Limit Reached

**Cause**: Tenant has reached resource limit

**Solution**:
```bash
# Check usage
curl http://localhost:8080/api/tenants/TENANT_ID/usage

# Increase limits
curl -X PUT http://localhost:8080/api/tenants/TENANT_ID \
  -H "Content-Type: application/json" \
  -d '{"max_users": 100}'
```

### Issue: Cross-Tenant Access

**Cause**: Missing tenant isolation in query

**Solution**: Always use `TenantIsolation.addTenantFilter()` for database queries

## Security Considerations

1. **Authentication**: Always verify tenant ownership before operations
2. **Authorization**: Check feature flags before allowing operations
3. **Isolation**: Never allow cross-tenant data access
4. **Audit Logging**: Log all tenant management operations
5. **Rate Limiting**: Apply per-tenant rate limits

## Performance Tips

1. **Cache Tenants**: Tenant data is cached in memory for fast access
2. **Index Usage**: Database indexes on `tenant_id` for fast filtering
3. **Connection Pooling**: Share database connections across tenants
4. **Batch Operations**: Use batch operations for usage tracking updates

## Related Documentation

- [Cluster Mode](CLUSTER_MODE.md) - High availability clustering
- [API Documentation](API.md) - Complete API reference
- [Database Schema](../sql/schema_multitenancy.sql) - Multi-tenancy schema
