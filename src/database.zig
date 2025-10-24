const std = @import("std");
const sqlite = @cImport({
    @cInclude("sqlite3.h");
});

pub const DatabaseError = error{
    OpenFailed,
    ExecFailed,
    PrepareFailed,
    StepFailed,
    BindFailed,
    ColumnFailed,
    NotFound,
    AlreadyExists,
};

pub const User = struct {
    id: i64,
    username: []const u8,
    password_hash: []const u8,
    email: []const u8,
    enabled: bool,
    created_at: i64,
    updated_at: i64,

    pub fn deinit(self: *User, allocator: std.mem.Allocator) void {
        allocator.free(self.username);
        allocator.free(self.password_hash);
        allocator.free(self.email);
    }
};

pub const Database = struct {
    db: ?*sqlite.sqlite3,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, db_path: []const u8) !Database {
        var db: ?*sqlite.sqlite3 = null;

        // Add null terminator for C string
        const path_z = try allocator.dupeZ(u8, db_path);
        defer allocator.free(path_z);

        const rc = sqlite.sqlite3_open(path_z.ptr, &db);
        if (rc != sqlite.SQLITE_OK) {
            if (db) |d| {
                _ = sqlite.sqlite3_close(d);
            }
            return DatabaseError.OpenFailed;
        }

        var database = Database{
            .db = db,
            .allocator = allocator,
        };

        // Initialize schema
        try database.initSchema();

        return database;
    }

    pub fn deinit(self: *Database) void {
        if (self.db) |db| {
            _ = sqlite.sqlite3_close(db);
        }
    }

    fn initSchema(self: *Database) !void {
        const schema =
            \\CREATE TABLE IF NOT EXISTS users (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    username TEXT UNIQUE NOT NULL,
            \\    password_hash TEXT NOT NULL,
            \\    email TEXT UNIQUE NOT NULL,
            \\    enabled INTEGER DEFAULT 1,
            \\    created_at INTEGER NOT NULL,
            \\    updated_at INTEGER NOT NULL
            \\);
            \\
            \\CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
            \\CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
        ;

        try self.exec(schema);
    }

    fn exec(self: *Database, sql: []const u8) !void {
        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);

        var errmsg: [*c]u8 = null;
        const rc = sqlite.sqlite3_exec(self.db, sql_z.ptr, null, null, @ptrCast(&errmsg));

        if (rc != sqlite.SQLITE_OK) {
            if (errmsg) |msg| {
                defer sqlite.sqlite3_free(msg);
            }
            return DatabaseError.ExecFailed;
        }
    }

    pub fn createUser(
        self: *Database,
        username: []const u8,
        password_hash: []const u8,
        email: []const u8,
    ) !i64 {
        const sql =
            \\INSERT INTO users (username, password_hash, email, created_at, updated_at)
            \\VALUES (?1, ?2, ?3, ?4, ?5)
        ;

        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);

        var stmt: ?*sqlite.sqlite3_stmt = null;
        var rc = sqlite.sqlite3_prepare_v2(self.db, sql_z.ptr, -1, &stmt, null);
        if (rc != sqlite.SQLITE_OK) {
            return DatabaseError.PrepareFailed;
        }
        defer _ = sqlite.sqlite3_finalize(stmt);

        const username_z = try self.allocator.dupeZ(u8, username);
        defer self.allocator.free(username_z);
        const password_z = try self.allocator.dupeZ(u8, password_hash);
        defer self.allocator.free(password_z);
        const email_z = try self.allocator.dupeZ(u8, email);
        defer self.allocator.free(email_z);

        const now = std.time.timestamp();

        _ = sqlite.sqlite3_bind_text(stmt, 1, username_z.ptr, -1, null);
        _ = sqlite.sqlite3_bind_text(stmt, 2, password_z.ptr, -1, null);
        _ = sqlite.sqlite3_bind_text(stmt, 3, email_z.ptr, -1, null);
        _ = sqlite.sqlite3_bind_int64(stmt, 4, now);
        _ = sqlite.sqlite3_bind_int64(stmt, 5, now);

        rc = sqlite.sqlite3_step(stmt);
        if (rc != sqlite.SQLITE_DONE) {
            if (rc == sqlite.SQLITE_CONSTRAINT) {
                return DatabaseError.AlreadyExists;
            }
            return DatabaseError.StepFailed;
        }

        return sqlite.sqlite3_last_insert_rowid(self.db);
    }

    pub fn getUserByUsername(self: *Database, username: []const u8) !User {
        const sql =
            \\SELECT id, username, password_hash, email, enabled, created_at, updated_at
            \\FROM users
            \\WHERE username = ?1
        ;

        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);

        var stmt: ?*sqlite.sqlite3_stmt = null;
        var rc = sqlite.sqlite3_prepare_v2(self.db, sql_z.ptr, -1, &stmt, null);
        if (rc != sqlite.SQLITE_OK) {
            return DatabaseError.PrepareFailed;
        }
        defer _ = sqlite.sqlite3_finalize(stmt);

        const username_z = try self.allocator.dupeZ(u8, username);
        defer self.allocator.free(username_z);

        _ = sqlite.sqlite3_bind_text(stmt, 1, username_z.ptr, -1, null);

        rc = sqlite.sqlite3_step(stmt);
        if (rc != sqlite.SQLITE_ROW) {
            return DatabaseError.NotFound;
        }

        const id = sqlite.sqlite3_column_int64(stmt, 0);
        const username_ptr = sqlite.sqlite3_column_text(stmt, 1);
        const password_ptr = sqlite.sqlite3_column_text(stmt, 2);
        const email_ptr = sqlite.sqlite3_column_text(stmt, 3);
        const enabled = sqlite.sqlite3_column_int(stmt, 4) != 0;
        const created_at = sqlite.sqlite3_column_int64(stmt, 5);
        const updated_at = sqlite.sqlite3_column_int64(stmt, 6);

        return User{
            .id = id,
            .username = try self.allocator.dupe(u8, std.mem.span(username_ptr)),
            .password_hash = try self.allocator.dupe(u8, std.mem.span(password_ptr)),
            .email = try self.allocator.dupe(u8, std.mem.span(email_ptr)),
            .enabled = enabled,
            .created_at = created_at,
            .updated_at = updated_at,
        };
    }

    pub fn updateUserPassword(self: *Database, username: []const u8, new_password_hash: []const u8) !void {
        const sql =
            \\UPDATE users
            \\SET password_hash = ?1, updated_at = ?2
            \\WHERE username = ?3
        ;

        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);

        var stmt: ?*sqlite.sqlite3_stmt = null;
        var rc = sqlite.sqlite3_prepare_v2(self.db, sql_z.ptr, -1, &stmt, null);
        if (rc != sqlite.SQLITE_OK) {
            return DatabaseError.PrepareFailed;
        }
        defer _ = sqlite.sqlite3_finalize(stmt);

        const password_z = try self.allocator.dupeZ(u8, new_password_hash);
        defer self.allocator.free(password_z);
        const username_z = try self.allocator.dupeZ(u8, username);
        defer self.allocator.free(username_z);

        const now = std.time.timestamp();

        _ = sqlite.sqlite3_bind_text(stmt, 1, password_z.ptr, -1, null);
        _ = sqlite.sqlite3_bind_int64(stmt, 2, now);
        _ = sqlite.sqlite3_bind_text(stmt, 3, username_z.ptr, -1, null);

        rc = sqlite.sqlite3_step(stmt);
        if (rc != sqlite.SQLITE_DONE) {
            return DatabaseError.StepFailed;
        }
    }

    pub fn deleteUser(self: *Database, username: []const u8) !void {
        const sql = "DELETE FROM users WHERE username = ?1";

        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);

        var stmt: ?*sqlite.sqlite3_stmt = null;
        var rc = sqlite.sqlite3_prepare_v2(self.db, sql_z.ptr, -1, &stmt, null);
        if (rc != sqlite.SQLITE_OK) {
            return DatabaseError.PrepareFailed;
        }
        defer _ = sqlite.sqlite3_finalize(stmt);

        const username_z = try self.allocator.dupeZ(u8, username);
        defer self.allocator.free(username_z);

        _ = sqlite.sqlite3_bind_text(stmt, 1, username_z.ptr, -1, null);

        rc = sqlite.sqlite3_step(stmt);
        if (rc != sqlite.SQLITE_DONE) {
            return DatabaseError.StepFailed;
        }
    }

    pub fn setUserEnabled(self: *Database, username: []const u8, enabled: bool) !void {
        const sql =
            \\UPDATE users
            \\SET enabled = ?1, updated_at = ?2
            \\WHERE username = ?3
        ;

        const sql_z = try self.allocator.dupeZ(u8, sql);
        defer self.allocator.free(sql_z);

        var stmt: ?*sqlite.sqlite3_stmt = null;
        var rc = sqlite.sqlite3_prepare_v2(self.db, sql_z.ptr, -1, &stmt, null);
        if (rc != sqlite.SQLITE_OK) {
            return DatabaseError.PrepareFailed;
        }
        defer _ = sqlite.sqlite3_finalize(stmt);

        const username_z = try self.allocator.dupeZ(u8, username);
        defer self.allocator.free(username_z);

        const now = std.time.timestamp();

        _ = sqlite.sqlite3_bind_int(stmt, 1, if (enabled) 1 else 0);
        _ = sqlite.sqlite3_bind_int64(stmt, 2, now);
        _ = sqlite.sqlite3_bind_text(stmt, 3, username_z.ptr, -1, null);

        rc = sqlite.sqlite3_step(stmt);
        if (rc != sqlite.SQLITE_DONE) {
            return DatabaseError.StepFailed;
        }
    }
};
