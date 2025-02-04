const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .cpu_model = .baseline } });
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "captain_volt",
        .root_module = exe_mod,
    });
    exe.linkLibC();
    const SystemLibraries = .{
        "gdi32",
    };
    inline for (SystemLibraries) |lib| {
        exe.linkSystemLibrary(lib);
    }

    const RaylibFlags: []const []const u8 = &.{
        "-DPLATFORM_DESKTOP_RGFW=1",
    };

    const RaylibSourceFiles = .{
        "rcore.c",
        "rshapes.c",
        "rtextures.c",
        "raudio.c",
        "rtext.c",
        "utils.c",
    };

    inline for (RaylibSourceFiles) |rl_src| {
        exe.addCSourceFile(
            .{ .file = .{ .src_path = .{ .owner = b, .sub_path = "libs/raylib/" ++ rl_src } }, .flags = RaylibFlags },
        );
    }
    if (target.result.os.tag == .windows and optimize == .ReleaseFast) {
        exe.subsystem = .Windows;
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
