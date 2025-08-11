const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main executable
    const exe = b.addExecutable(.{
        .name = "extractor",
        .root_source_file = b.path("extractor.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Link SQLite3
    exe.linkSystemLibrary("sqlite3");
    exe.linkLibC();
    
    b.installArtifact(exe);

    // Create run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    
    const run_step = b.step("run", "Run the extractor");
    run_step.dependOn(&run_cmd.step);

    // Shared library for Flutter FFI
    const lib = b.addSharedLibrary(.{
        .name = "claude_extractor",
        .root_source_file = b.path("extractor.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    lib.linkSystemLibrary("sqlite3");
    lib.linkLibC();
    
    b.installArtifact(lib);
    
    // Test step
    const test_step = b.step("test", "Run unit tests");
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("extractor.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    unit_tests.linkSystemLibrary("sqlite3");
    unit_tests.linkLibC();
    
    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);
}