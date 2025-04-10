const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule(
        "Lean",
        .{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/lean.zig")
        }
    );

    const build_test = b.addTest(
        .{
            .root_source_file = b.path("test.zig"),
            .target = target,
            .optimize = optimize,
        }
    );
    const run_tests = b.addRunArtifact(build_test);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}