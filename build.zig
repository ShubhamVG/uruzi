const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // WARNING: zigimg does not work with self-hosted backend/without LLVM
    // (https://codeberg.org/ziglang/zig/issues/31837)
    const no_llvm = b.option(bool, "no-llvm", "Disable LLVM") orelse false;
    const use_llvm = !no_llvm;

    const exe = b.addExecutable(.{
        .name = "uruzi",
        .use_llvm = use_llvm,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const clap = b.dependency("clap", .{});
    exe.root_module.addImport("clap", clap.module("clap"));

    const raylib_dep = b.dependency("raylib_zig", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("raylib", raylib_dep.module("raylib"));
    exe.root_module.addImport("raygui", raylib_dep.module("raygui"));

    const nfd = b.dependency("nfd", .{ .target = target, .optimize = optimize });
    const nfd_mod = nfd.module("nfd");
    exe.root_module.addImport("nfd", nfd_mod);

    const zigimg_dep = b.dependency("zigimg", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("zigimg", zigimg_dep.module("zigimg"));

    b.installArtifact(exe);

    const run_step = b.step("run", "run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
