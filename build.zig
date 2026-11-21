fn compileShaders(b: *std.Build, dep_sokol: *std.Build.Dependency, imports: *std.ArrayList(std.Build.Module.Import)) !void {
    const dep_shdc = dep_sokol.builder.dependency("shdc", .{});

    const mod_sokol = dep_sokol.module("sokol");

    const Shaders = .{"sprite2d"};

    inline for (Shaders) |shader_name| {
        const mod_shd = try sokol.shdc.createModule(b, "shader", mod_sokol, .{
            .shdc_dep = dep_shdc,
            .input = "src/shaders/" ++ shader_name ++ ".glsl",
            .output = "shader.zig",
            .slang = .{
                .hlsl5 = true,
                .glsl430 = true,
            },
        });

        imports.appendAssumeCapacity(.{
            .name = "shader_" ++ shader_name,
            .module = mod_shd,
        });
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .cpu_model = .baseline } });
    const optimize = b.standardOptimizeOption(.{});

    const dep_zigimg = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });

    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        // .backend = .gl,
    });

    const dep_mr_geom = b.dependency("mr_geom", .{
        .target = target,
        .optimize = optimize,
    });

    const mod_sokol = dep_sokol.module("sokol");

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sokol", .module = mod_sokol },
            .{ .name = "zigimg", .module = dep_zigimg.module("zigimg") },
            .{ .name = "mr_geom", .module = dep_mr_geom.module("mr_geom") },
        },
    });

    var shader_imports_buffer: [32]std.Build.Module.Import = undefined;
    var shader_imports: std.ArrayList(std.Build.Module.Import) = .initBuffer(shader_imports_buffer[0..]);

    compileShaders(b, dep_sokol, &shader_imports) catch |err| {
        _ = b.addFail(@errorName(err));
    };

    for (shader_imports.items) |shader_import| {
        exe_mod.addImport(shader_import.name, shader_import.module);
    }

    const exe = b.addExecutable(.{
        .name = "captain_volt",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    // if (b.args) |args| {
    //     run_cmd.addArgs(args);
    // }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const mod_test = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_unit_tests = b.addTest(.{
        .root_module = mod_test,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

const std = @import("std");

const sokol = @import("sokol");
