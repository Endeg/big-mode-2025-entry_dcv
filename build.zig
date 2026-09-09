const std = @import("std");

fn raylibModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const raylib_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    raylib_mod.addIncludePath(.{ .src_path = .{ .owner = b, .sub_path = "libs/raylib" } });
    raylib_mod.linkSystemLibrary("gdi32", .{});

    raylib_mod.addCSourceFiles(.{
        .flags = &.{
            // Raylib flags
            "-DEXTERNAL_CONFIG_FLAGS=1",
            "-DPLATFORM_DESKTOP_RGFW=1",
            "-DSUPPORT_MODULE_RSHAPES=1",
            "-DSUPPORT_MODULE_RTEXTURES=1",
            "-DSUPPORT_MODULE_RTEXT=1",
            "-DSUPPORT_MODULE_RMODELS=0",
            "-DSUPPORT_MODULE_RAUDIO=1",
            "-DSUPPORT_FILEFORMAT_TTF=1",
            "-DSUPPORT_FILEFORMAT_PNG=1",
            "-DSUPPORT_FILEFORMAT_WAV=1",
            "-DSUPPORT_TEXT_MANIPULATION=1",
            "-DSUPPORT_DEFAULT_FONT=1",
            "-DSUPPORT_TRACELOG=1",

            // Necessary flags
            "-std=gnu99",
            "-D_GNU_SOURCE",
            "-DGL_SILENCE_DEPRECATION=199309L",
            "-fno-sanitize=undefined", // https://github.com/raysan5/raylib/issues/3674

            // Shared lib specific
            "-fPIC",
            "-DBUILD_LIBTYPE_SHARED",
        },
        .files = &.{
            "libs/raylib/rcore.c",
            "libs/raylib/raudio.c",
            "libs/raylib/rmodels.c",
            "libs/raylib/rshapes.c",
            "libs/raylib/rtext.c",
            "libs/raylib/rtextures.c",
            "libs/raylib/utils.c",
        },
    });

    return raylib_mod;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{ .cpu_model = .baseline },
    });
    const optimize = b.standardOptimizeOption(.{});

    const zglfw_dep = b.dependency("zglfw", .{
        .optimize = optimize,
        .target = target,
        .shared = true,
        .import_vulkan = true,
    });

    const vulkan_mod = b.createModule(.{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("libs/vulkan/root.zig"),
    });
    zglfw_dep.module("root").addImport("vulkan", vulkan_mod);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zglfw", .module = zglfw_dep.module("root") },
            .{ .name = "vulkan", .module = vulkan_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "captain_volt",
        .root_module = exe_mod,
    });
    exe_mod.linkLibrary(zglfw_dep.artifact("glfw"));

    b.installArtifact(zglfw_dep.artifact("glfw"));
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
