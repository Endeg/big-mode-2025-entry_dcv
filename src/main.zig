const std = @import("std");
const assert = std.debug.assert;
const log = std.log;

const c = @import("c.zig");

const util = @import("util.zig");

//TODO: GPA allocator: dupeZ/free - possible bug

// TODO: Entity manager - use GigaEntity
//>TODO: Sprite assets - load/render
// TODO: Audio assets - load/play
// TODO: List assets configuration in json
// TODO: json config with hot-reloading
// TODO: Main loop: 1. read input; 2. update game; 3. render

const Json = struct {
    const Sprite = struct {
        image: []const u8,
        size: ?c.Vector2 = null,
        origin: c.Vector2,
    };
};

const Sprite = struct {
    texture: TextureManager.Handle,
    source: c.Rectangle,
    size: c.Vector2,
    origin: c.Vector2,
};

const TextureManager = struct {
    const ElementsCount = 16;

    textures: std.ArrayListUnmanaged(c.Texture2D),
    texture_file_names: std.StringHashMapUnmanaged(Handle),
    allocator: std.mem.Allocator,

    const Self = @This();

    const Handle = enum(u8) { _ };

    pub fn init(allocator: std.mem.Allocator) !TextureManager {
        var texture_file_names = std.StringHashMapUnmanaged(Handle){};
        try texture_file_names.ensureTotalCapacity(allocator, ElementsCount);

        return .{
            .textures = try std.ArrayListUnmanaged(c.Texture2D).initCapacity(allocator, ElementsCount),
            .texture_file_names = texture_file_names,
            .allocator = allocator,
        };
    }

    pub fn fetchHandle(self: *Self, file_name: []const u8) !Handle {
        if (self.texture_file_names.get(file_name)) |found_handle| {
            errdefer comptime unreachable;
            return found_handle;
        }

        var i = file_name.len - 1;
        var ext: ?[]const u8 = null;
        while (i > 0) : (i -= 1) {
            if (file_name[i] == '.') {
                ext = file_name[i..];
                break;
            }
        }

        const ext_z = std.mem.zeroes([6]u8);

        log.debug("ext = {?s}", .{ext});
        assert(ext != null);

        if (ext) |actual_ext| {
            std.mem.copyForwards(u8, @constCast(ext_z[0..]), actual_ext);
        }

        const file_data = try util.readEntireFileAlloc("assets", file_name, self.allocator);
        defer self.allocator.free(file_data);

        const image = c.LoadImageFromMemory(&ext_z, file_data.ptr, @intCast(file_data.len));
        defer c.UnloadImage(image);
        log.debug("image = {any}.", .{image});

        const texture = c.LoadTextureFromImage(image);
        log.debug("texture = {any}.", .{texture});

        const result_handle: Handle = @enumFromInt(self.textures.items.len);

        self.textures.appendAssumeCapacity(texture);

        const file_name_dup = try self.allocator.dupe(u8, file_name);
        self.texture_file_names.putAssumeCapacity(file_name_dup, result_handle);

        return result_handle;
    }

    pub fn get(self: *const Self, handle: Handle) *c.Texture2D {
        const index: usize = @intFromEnum(handle);
        assert(index < self.textures.items.len);
        return &self.textures.items[index];
    }
};

const SpriteManager = struct {
    const Error = error{
        malformed_sprites_json,
    };

    texture_manager: *TextureManager,
    sprites: std.ArrayListUnmanaged(Sprite),
    sprite_names: std.StringHashMapUnmanaged(Handle),
    allocator: std.mem.Allocator,

    const Self = @This();

    const ElementsCount = 16;

    const Handle = enum(u8) { _ };

    pub fn init(
        texture_manager: *TextureManager,
        allocator: std.mem.Allocator,
    ) !Self {
        var sprite_names = std.StringHashMapUnmanaged(Handle){};
        try sprite_names.ensureTotalCapacity(allocator, ElementsCount);

        return .{
            .texture_manager = texture_manager,
            .sprite_names = sprite_names,
            .sprites = try std.ArrayListUnmanaged(Sprite).initCapacity(allocator, ElementsCount),
            .allocator = allocator,
        };
    }

    pub fn loadFromJson(self: *Self, json_data: []const u8) !void {
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json_data, .{});
        defer parsed.deinit();
        var created: usize = 0;
        var updated: usize = 0;
        switch (parsed.value) {
            .object => |sprites_json_value| {
                var iter = sprites_json_value.iterator();

                while (iter.next()) |entry| {
                    const sprite_name = entry.key_ptr.*;
                    const sprite_json_value = entry.value_ptr.*;

                    const parsed_sprite = try std.json.parseFromValue(Json.Sprite, self.allocator, sprite_json_value, .{});
                    defer parsed_sprite.deinit();
                    var sprite: *Sprite = undefined;
                    if (self.sprite_names.get(sprite_name)) |existing_sprite_handle| {
                        sprite = self.get(existing_sprite_handle);
                        updated += 1;
                    } else {
                        const new_sprite_handle: Handle = @enumFromInt(self.sprites.items.len);
                        self.sprites.appendAssumeCapacity(undefined);
                        const sprite_name_dup = try self.allocator.dupe(u8, sprite_name);
                        self.sprite_names.putAssumeCapacity(sprite_name_dup, new_sprite_handle);
                        sprite = self.get(new_sprite_handle);
                        created += 1;
                    }

                    sprite.texture = try self.texture_manager.fetchHandle(parsed_sprite.value.image);
                    const texture = self.texture_manager.get(sprite.texture);
                    log.debug("texture = {any}.", .{texture});
                    sprite.source = .{
                        .x = 0,
                        .y = 0,
                        .width = @floatFromInt(texture.width),
                        .height = @floatFromInt(texture.height),
                    };
                    if (parsed_sprite.value.size) |provided_size| {
                        sprite.size = provided_size;
                    } else {
                        sprite.size = .{
                            .x = @floatFromInt(texture.width),
                            .y = @floatFromInt(texture.height),
                        };
                    }
                    sprite.origin = parsed_sprite.value.origin;
                }
                log.debug("[Sprite Manager] created {d} and updated {d} sprites.", .{ created, updated });
            },
            else => return Error.malformed_sprites_json,
        }
    }

    pub fn get(self: *const Self, handle: Handle) *Sprite {
        const index: usize = @intFromEnum(handle);
        assert(index < self.sprites.items.len);
        return &self.sprites.items[index];
    }

    pub fn find(self: *const Self, name: []const u8) ?Handle {
        if (self.sprite_names.get(name)) |found_sprite_handle| {
            return found_sprite_handle;
        } else {
            return null;
        }
    }
};

const GPA = std.heap.GeneralPurposeAllocator(.{});

fn drawSprite(
    sprite: *const Sprite,
    position: c.Vector2,
    rotation: f32,
    tint: c.Color,
    texture_manager: *const TextureManager,
) void {
    const texture = texture_manager.get(sprite.texture).*;

    c.DrawTexturePro(
        texture,
        sprite.source,
        .{ .x = position.x, .y = position.y, .width = sprite.size.x, .height = sprite.size.y },
        .{ .x = sprite.origin.x * sprite.size.x, .y = sprite.origin.y * sprite.size.y },
        rotation,
        tint,
    );
}

pub fn main() !void {
    const s = try std.fs.cwd().statFile("translate-c.cmd");
    log.debug("s.atime = {d}, s.ctime = {d}, s.mtime = {d}.", .{ s.atime, s.ctime, s.mtime });

    c.InitWindow(1280, 720, "Unnamed Game Jam Entry");
    c.SetTargetFPS(60);

    var gpa = GPA{};

    var texture_manager = try TextureManager.init(gpa.allocator());
    var sprite_manager = try SpriteManager.init(&texture_manager, gpa.allocator());
    {
        const allocator = gpa.allocator();
        const sprites_json_content = try util.readEntireFileAlloc(".", "sprites.json", allocator);
        defer allocator.free(sprites_json_content);
        try sprite_manager.loadFromJson(sprites_json_content);
    }

    const kenney_1bitpack = try texture_manager.fetchHandle("kenney_1bitpack_monochrome_transparent.png");
    log.debug("kenney_1bitpack = {any}", .{kenney_1bitpack});

    if (false) {
        const allocator = gpa.allocator();
        const sprites_json_content = try util.readEntireFileAlloc(".", "sprites.json", allocator);
        defer allocator.free(sprites_json_content);
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, sprites_json_content, .{});
        defer parsed.deinit();
        switch (parsed.value) {
            .object => |sprites_json_value| {
                var iter = sprites_json_value.iterator();

                while (iter.next()) |entry| {
                    const sprite_name = entry.key_ptr.*;
                    const sprite_json_value = entry.value_ptr.*;

                    var tmp_iter = sprite_json_value.object.iterator();

                    while (tmp_iter.next()) |tmp_entry| {
                        log.debug("Json - {s} -> {s} : {any}.", .{ sprite_name, tmp_entry.key_ptr.*, tmp_entry.value_ptr.* });
                    }

                    const parsed_object = try std.json.parseFromValue(Json.Sprite, allocator, sprite_json_value, .{});
                    defer parsed_object.deinit();

                    log.debug("Json - {s} -> {any}.", .{ sprite_name, parsed_object.value });
                }
            },
            else => unreachable,
        }
    }

    const screen_width: f32 = @floatFromInt(c.GetScreenWidth());
    const screen_height: f32 = @floatFromInt(c.GetScreenHeight());

    const camera = c.Camera2D{
        .offset = .{ .x = screen_width * 0.5, .y = screen_height * 0.5 },
        .rotation = 0,
        .target = .{ .x = 0, .y = 0 },
        .zoom = 3,
    };

    while (!c.WindowShouldClose()) {
        c.BeginDrawing();
        defer c.EndDrawing();

        c.BeginMode2D(camera);

        c.ClearBackground(c.LIGHTGRAY);

        c.DrawLine(0, 700, 1280, 700, c.DARKBROWN);

        const SpriteNames = .{ "main-guy", "battery" };

        var pos: f32 = 0;

        inline for (SpriteNames) |SpriteName| {
            if (sprite_manager.find(SpriteName)) |sprite_handle| {
                const sprite = sprite_manager.get(sprite_handle);
                drawSprite(sprite, .{ .x = pos, .y = 0 }, 0, c.BLUE, &texture_manager);
                pos += 20;
            }
        }

        c.EndMode2D();

        c.DrawFPS(2, 2);
    }
}
