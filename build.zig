const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add zig-tls dependency
    const tls = b.dependency("tls", .{
        .target = target,
        .optimize = optimize,
    });
    const tls_module = tls.module("tls");

    // Create the root module
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    root_module.addImport("tls", tls_module);

    const exe = b.addExecutable(.{
        .name = "smtp-server",
        .root_module = root_module,
    });

    // Link SQLite3
    exe.linkLibC();
    exe.linkSystemLibrary("sqlite3");

    b.installArtifact(exe);

    // User management CLI tool
    const user_cli_module = b.createModule(.{
        .root_source_file = b.path("src/user_cli.zig"),
        .target = target,
        .optimize = optimize,
    });

    const user_cli = b.addExecutable(.{
        .name = "user-cli",
        .root_module = user_cli_module,
    });
    user_cli.linkLibC();
    user_cli.linkSystemLibrary("sqlite3");
    b.installArtifact(user_cli);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the SMTP server");
    run_step.dependOn(&run_cmd.step);

    // Create test step
    const test_step = b.step("test", "Run unit tests");

    // Add tests for each module
    const test_files = [_][]const u8{
        "src/security_test.zig",
        "src/errors_test.zig",
        "src/config_test.zig",
    };

    for (test_files) |test_file| {
        const test_module = b.createModule(.{
            .root_source_file = b.path(test_file),
            .target = target,
            .optimize = optimize,
        });
        test_module.addImport("tls", tls_module);

        const unit_tests = b.addTest(.{
            .root_module = test_module,
        });

        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_unit_tests.step);
    }
}
