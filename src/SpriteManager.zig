const SpriteManager = @This();

const std = @import("std");
const assert = std.debug.assert;
const log = std.log;

const c = @import("c.zig");

const Error = error{
    malformed_sprites_json,
};

textures: std.EnumArray(TextureAsset, c.Texture2D),
sprites: std.EnumArray(SpriteHandle, Sprite),

pub const Sprite = struct {
    texture: c.Texture2D,
    source: c.Rectangle,
    size: c.Vector2,
    origin: c.Vector2,
};

pub fn init() SpriteManager {
    var textures = std.EnumArray(TextureAsset, c.Texture2D).initUndefined();
    inline for (@typeInfo(TextureAsset).@"enum".fields) |texture_asset_field| {
        const texture_asset: TextureAsset = @enumFromInt(texture_asset_field.value);

        const file_data = TextureAssets.get(texture_asset);

        const image = c.LoadImageFromMemory(".png", file_data.ptr, @intCast(file_data.len));
        defer c.UnloadImage(image);
        log.debug("image = {any}.", .{image});

        const texture = c.LoadTextureFromImage(image);
        log.debug("texture = {any}.", .{texture});
        textures.set(texture_asset, texture);
    }

    var sprites = std.EnumArray(SpriteHandle, Sprite).initUndefined();
    inline for (@typeInfo(SpriteHandle).@"enum".fields) |sprite_handle_field| {
        const sprite_handle: SpriteHandle = @enumFromInt(sprite_handle_field.value);
        var sprite: Sprite = undefined;

        const sprite_info = SpriteInfos.get(sprite_handle);

        sprite.texture = textures.get(sprite_info.texture);
        log.debug("texture = {any}.", .{sprite.texture});
        if (sprite_info.source) |provided_source| {
            sprite.source = provided_source;
        } else {
            sprite.source = .{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(sprite.texture.width),
                .height = @floatFromInt(sprite.texture.height),
            };
        }
        if (sprite_info.size) |provided_size| {
            sprite.size = provided_size;
        } else {
            sprite.size = .{
                .x = @floatFromInt(sprite.texture.width),
                .y = @floatFromInt(sprite.texture.height),
            };
        }
        sprite.origin = sprite_info.origin;

        sprites.set(sprite_handle, sprite);
    }

    return .{
        .textures = textures,
        .sprites = sprites,
    };
}

pub fn get(self: *SpriteManager, handle: SpriteHandle) *Sprite {
    return self.sprites.getPtr(handle);
}

//---------------------------------------------

const TextureAsset = enum {
    MainGuy,
    Projectile,
    Blaster,
    Enemy0,
    Heart,
    Potion,
    Battery,
    Decor0,
    Decor1,
    Helmet,
};

const TextureAssets = std.EnumArray(TextureAsset, []const u8).init(.{
    .MainGuy = @embedFile("assets-to-embed/tile-28x9.png"),
    .Projectile = @embedFile("assets-to-embed/tile-27x20.png"),
    .Blaster = @embedFile("assets-to-embed/tile-38x9.png"),
    .Enemy0 = @embedFile("assets-to-embed/tile-28x6.png"),
    .Heart = @embedFile("assets-to-embed/tile-39x10.png"),
    .Potion = @embedFile("assets-to-embed/tile-34x13.png"),
    .Battery = @embedFile("assets-to-embed/battery-item.png"),
    .Decor0 = @embedFile("assets-to-embed/tile-0x1.png"),
    .Decor1 = @embedFile("assets-to-embed/tile-0x2.png"),
    .Helmet = @embedFile("assets-to-embed/tile-37x0.png"),
});

//---------------------------------------------

pub const SpriteHandle = enum {
    Player,
    Projectile,
    Blaster,
    Enemy0,
    Heart,
    Potion,
    Battery,
    Decor0,
    Decor1,
    Helmet,
};

const SpriteInfos = std.EnumArray(SpriteHandle, SpriteInfo).init(.{
    .Player = .{
        .texture = .MainGuy,
        .origin = .{ .x = 0.5, .y = 1 },
    },
    .Projectile = .{
        .texture = .Projectile,
        .origin = .{ .x = 0.5, .y = 0.5 },
    },
    .Blaster = .{
        .texture = .Blaster,
        .origin = .{ .x = 0.2, .y = 0.4 },
    },
    .Enemy0 = .{
        .texture = .Enemy0,
        .origin = .{ .x = 0.5, .y = 1 },
    },
    .Heart = .{
        .texture = .Heart,
        .origin = .{ .x = 0, .y = 0 },
    },
    .Helmet = .{
        .texture = .Helmet,
        .origin = .{ .x = 0, .y = 0 },
    },
    .Potion = .{
        .texture = .Potion,
        .origin = .{ .x = 0.5, .y = 1 },
    },
    .Battery = .{
        .texture = .Battery,
        .origin = .{ .x = 0.5, .y = 0.9 },
    },
    .Decor0 = .{
        .texture = .Decor0,
        .origin = .{ .x = 0.5, .y = 0.5 },
    },
    .Decor1 = .{
        .texture = .Decor1,
        .origin = .{ .x = 0.5, .y = 0.5 },
    },
});

const SpriteInfo = struct {
    texture: TextureAsset,
    source: ?c.Rectangle = null,
    size: ?c.Vector2 = null,
    origin: c.Vector2,
};
