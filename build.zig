const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tokenizer_mod = b.addModule("HtmlTokenizer", .{
        .root_source_file = b.path("HtmlTokenizer.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests_mod = b.createModule(.{
        .root_source_file = b.path("HtmlTokenizer.tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "HtmlTokenizer", .module = tokenizer_mod }},
    });

    const tests = b.addTest(.{ .root_module = tests_mod });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tokenizer tests");
    test_step.dependOn(&run_tests.step);

    const fuzz_mod = b.createModule(.{
        .root_source_file = b.path("HtmlTokenizer.fuzz.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
        .imports = &.{.{ .name = "HtmlTokenizer", .module = tokenizer_mod }},
    });

    const fuzz_tests = b.addTest(.{
        .root_module = fuzz_mod,
    });

    const run_fuzz = b.addRunArtifact(fuzz_tests);
    const fuzz_step = b.step("fuzz", "Run fuzzer");
    fuzz_step.dependOn(&run_fuzz.step);
}
