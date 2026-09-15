const Config = @This();

// This file purpose is to keep all application-related configs here:
//   - Graphics: shader enums, vertex layouts, required features that should be checked
//   - Audio: Buffer format, size
//
// With this approach e.g. `GfxVulan.zig` can be reusable and extendable for other projects, and at the same time, do not require too much focus on reusability of the code.
// For me, that focus on reusability of the code, slows down the process of actually finishing the project. So, I'm trying to first finish the project, and see it as the foundation for the next project. Then, eventually, when patterns emerge, reusable libraries can be created. But, for now, this code should just go into `template` repository.

pub const graphics: Graphics = .{};

const Graphics = struct {
    shader_enum: enum(u1) { simple },
};

comptime {
    // TODO: do config validation, e.g. check that `shader_enum` is the enum.
}
