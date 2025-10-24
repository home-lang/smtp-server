const std = @import("std");

/// Benchmark result
pub const BenchmarkResult = struct {
    name: []const u8,
    iterations: usize,
    total_duration_ns: u64,
    min_duration_ns: u64,
    max_duration_ns: u64,
    avg_duration_ns: u64,
    ops_per_second: f64,

    pub fn print(self: *const BenchmarkResult, writer: anytype) !void {
        try writer.print("Benchmark: {s}\n", .{self.name});
        try writer.print("  Iterations: {d}\n", .{self.iterations});
        try writer.print("  Total time: {d} ns ({d:.2} ms)\n", .{ self.total_duration_ns, @as(f64, @floatFromInt(self.total_duration_ns)) / 1_000_000.0 });
        try writer.print("  Average: {d} ns ({d:.2} μs)\n", .{ self.avg_duration_ns, @as(f64, @floatFromInt(self.avg_duration_ns)) / 1_000.0 });
        try writer.print("  Min: {d} ns ({d:.2} μs)\n", .{ self.min_duration_ns, @as(f64, @floatFromInt(self.min_duration_ns)) / 1_000.0 });
        try writer.print("  Max: {d} ns ({d:.2} μs)\n", .{ self.max_duration_ns, @as(f64, @floatFromInt(self.max_duration_ns)) / 1_000.0 });
        try writer.print("  Ops/sec: {d:.2}\n", .{self.ops_per_second});
    }
};

/// Benchmark runner
pub const Benchmark = struct {
    allocator: std.mem.Allocator,
    warmup_iterations: usize = 10,
    iterations: usize = 1000,

    pub fn init(allocator: std.mem.Allocator) Benchmark {
        return .{ .allocator = allocator };
    }

    /// Run a benchmark function
    pub fn run(
        self: *Benchmark,
        name: []const u8,
        comptime func: fn () anyerror!void,
    ) !BenchmarkResult {
        // Warmup
        var i: usize = 0;
        while (i < self.warmup_iterations) : (i += 1) {
            try func();
        }

        // Actual benchmark
        var durations = try self.allocator.alloc(u64, self.iterations);
        defer self.allocator.free(durations);

        var total_duration: u64 = 0;
        var min_duration: u64 = std.math.maxInt(u64);
        var max_duration: u64 = 0;

        i = 0;
        while (i < self.iterations) : (i += 1) {
            const start = std.time.nanoTimestamp();
            try func();
            const end = std.time.nanoTimestamp();

            const duration = @as(u64, @intCast(end - start));
            durations[i] = duration;
            total_duration += duration;
            min_duration = @min(min_duration, duration);
            max_duration = @max(max_duration, duration);
        }

        const avg_duration = total_duration / self.iterations;
        const ops_per_second = 1_000_000_000.0 / @as(f64, @floatFromInt(avg_duration));

        return BenchmarkResult{
            .name = name,
            .iterations = self.iterations,
            .total_duration_ns = total_duration,
            .min_duration_ns = min_duration,
            .max_duration_ns = max_duration,
            .avg_duration_ns = avg_duration,
            .ops_per_second = ops_per_second,
        };
    }

    /// Run a benchmark with context
    pub fn runWithContext(
        self: *Benchmark,
        name: []const u8,
        context: anytype,
        comptime func: fn (@TypeOf(context)) anyerror!void,
    ) !BenchmarkResult {
        // Warmup
        var i: usize = 0;
        while (i < self.warmup_iterations) : (i += 1) {
            try func(context);
        }

        // Actual benchmark
        var durations = try self.allocator.alloc(u64, self.iterations);
        defer self.allocator.free(durations);

        var total_duration: u64 = 0;
        var min_duration: u64 = std.math.maxInt(u64);
        var max_duration: u64 = 0;

        i = 0;
        while (i < self.iterations) : (i += 1) {
            const start = std.time.nanoTimestamp();
            try func(context);
            const end = std.time.nanoTimestamp();

            const duration = @as(u64, @intCast(end - start));
            durations[i] = duration;
            total_duration += duration;
            min_duration = @min(min_duration, duration);
            max_duration = @max(max_duration, duration);
        }

        const avg_duration = total_duration / self.iterations;
        const ops_per_second = 1_000_000_000.0 / @as(f64, @floatFromInt(avg_duration));

        return BenchmarkResult{
            .name = name,
            .iterations = self.iterations,
            .total_duration_ns = total_duration,
            .min_duration_ns = min_duration,
            .max_duration_ns = max_duration,
            .avg_duration_ns = avg_duration,
            .ops_per_second = ops_per_second,
        };
    }
};

/// SMTP-specific benchmarks
pub const SMTPBenchmarks = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SMTPBenchmarks {
        return .{ .allocator = allocator };
    }

    /// Benchmark email address validation
    pub fn benchmarkEmailValidation(self: *SMTPBenchmarks) !void {
        const security = @import("../auth/security.zig");
        _ = security.isValidEmail("test@example.com");
        _ = self;
    }

    /// Benchmark base64 decoding
    pub fn benchmarkBase64Decode(self: *SMTPBenchmarks) !void {
        const test_data = "dGVzdEB1c2VyOnBhc3N3b3Jk"; // "test@user:password"
        const decoder = std.base64.standard.Decoder;
        const decoded_len = try decoder.calcSizeForSlice(test_data);
        const decoded = try self.allocator.alloc(u8, decoded_len);
        defer self.allocator.free(decoded);
        try decoder.decode(decoded, test_data);
    }

    /// Benchmark string parsing
    pub fn benchmarkCommandParsing(self: *SMTPBenchmarks) !void {
        _ = self;
        const line = "MAIL FROM:<sender@example.com>";
        var it = std.mem.splitScalar(u8, line, ' ');
        _ = it.next(); // MAIL
        _ = it.next(); // FROM:<...>
    }

    /// Benchmark memory allocation
    pub fn benchmarkAllocation(self: *SMTPBenchmarks) !void {
        const data = try self.allocator.alloc(u8, 1024);
        defer self.allocator.free(data);
    }

    /// Run all SMTP benchmarks
    pub fn runAll(self: *SMTPBenchmarks) !void {
        var bench = Benchmark.init(self.allocator);
        bench.iterations = 10000;

        const stdout = std.io.getStdOut().writer();

        try stdout.print("\n=== SMTP Performance Benchmarks ===\n\n", .{});

        // Email validation
        const email_result = try bench.runWithContext(
            "Email Validation",
            self,
            SMTPBenchmarks.benchmarkEmailValidation,
        );
        try email_result.print(stdout);
        try stdout.print("\n", .{});

        // Base64 decoding
        const base64_result = try bench.runWithContext(
            "Base64 Decode",
            self,
            SMTPBenchmarks.benchmarkBase64Decode,
        );
        try base64_result.print(stdout);
        try stdout.print("\n", .{});

        // Command parsing
        const parse_result = try bench.runWithContext(
            "Command Parsing",
            self,
            SMTPBenchmarks.benchmarkCommandParsing,
        );
        try parse_result.print(stdout);
        try stdout.print("\n", .{});

        // Memory allocation
        const alloc_result = try bench.runWithContext(
            "Memory Allocation (1KB)",
            self,
            SMTPBenchmarks.benchmarkAllocation,
        );
        try alloc_result.print(stdout);
        try stdout.print("\n", .{});
    }
};

test "benchmark framework" {
    const testing = std.testing;
    var bench = Benchmark.init(testing.allocator);
    bench.iterations = 100;
    bench.warmup_iterations = 10;

    const TestContext = struct {
        fn testFunc(_: @This()) !void {
            var x: u64 = 0;
            var i: usize = 0;
            while (i < 100) : (i += 1) {
                x += i;
            }
        }
    };

    const result = try bench.runWithContext("test", TestContext{}, TestContext.testFunc);
    try testing.expect(result.iterations == 100);
    try testing.expect(result.avg_duration_ns > 0);
    try testing.expect(result.ops_per_second > 0);
}
