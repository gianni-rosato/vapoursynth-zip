const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "vszip",
        .root_source_file = b.path("src/vszip.zig"),
        .target = target,
        .optimize = optimize,
    });

    const vapoursynth_dep = b.dependency("vapoursynth", .{
        .target = target,
        .optimize = optimize,
    });

    lib.root_module.addImport("vapoursynth", vapoursynth_dep.module("vapoursynth"));
    lib.addIncludePath(b.path("src/filters"));
    lib.addCSourceFiles(.{
        .files = &.{
            "src/filters/metric_xpsnr.c",
        },
        .flags = &.{
            "-std=c99",
            "-lm",
            "-O3",
        },
    });
    lib.linkLibC();

    if (lib.root_module.optimize == .ReleaseFast) {
        lib.root_module.strip = true;
    }

    b.installArtifact(lib);
}
