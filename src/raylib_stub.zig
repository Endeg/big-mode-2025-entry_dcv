pub const FLAG_WINDOW_RESIZABLE: i32 = 4;

pub const Sound = struct {};
pub const Wave = struct {};
pub const Texture2D = struct {
    // @todo: Cleanup
    const sg = @import("sokol").gfx;

    width: i32,
    height: i32,

    image: sg.Image,
    view: sg.View,
};
pub const Image = struct {
    width: u16,
    height: u16,
    pixels: [*]Color,
};
pub const Rectangle = struct { x: f32 = 0, y: f32 = 0, width: f32 = 0, height: f32 = 0 };
pub const Vector2 = extern struct { x: f32 = 0, y: f32 = 0 };
pub const Vector3 = extern struct { x: f32 = 0, y: f32 = 0, z: f32 = 0 };
pub const Color = packed struct(u32) {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 0,

    pub fn init(r: u8, g: u8, b: u8, a: u8) Color {
        return .{
            .r = r,
            .g = g,
            .b = b,
            .a = a,
        };
    }
};
pub const Camera2D = extern struct {
    offset: Vector2 = .{},
    target: Vector2 = .{},
    rotation: f32 = 0,
    zoom: f32 = 0,
};

const LogEnabled = false;

pub fn InitWindow(width: i32, height: i32, title: [*c]const u8) void {
    if (LogEnabled) log.debug("{s}({d}, {d}, {s})", .{ @src().fn_name, width, height, title });
}

pub fn CloseWindow() void {
    if (LogEnabled) log.debug("{s}()", .{
        @src().fn_name,
    });
}

pub fn SetConfigFlags(flags: u32) void {
    if (LogEnabled) log.debug("{s}({X:8})", .{ @src().fn_name, flags });
}

pub fn SetTargetFPS(fps: i32) void {
    if (LogEnabled) log.debug("{s}({d})", .{ @src().fn_name, fps });
}

pub fn LoadWaveFromMemory(fileType: [*c]const u8, fileData: [*c]const u8, dataSize: i32) Wave {
    if (LogEnabled) {
        log.debug("{s}({s}, <fileData>, {d})", .{ @src().fn_name, fileType, dataSize });
        std.debug.dumpHex(fileData[0..@intCast(@min(dataSize, 16))]);
    }
    return .{};
}

/// Deprecated
pub fn LoadImageFromMemory(fileType: [*c]const u8, fileData: [*c]const u8, dataSize: i32, gpa: std.mem.Allocator) !Image {
    const zigimg = @import("zigimg");

    if (LogEnabled) {
        log.debug("{s}({s}, <fileData>, {d})", .{ @src().fn_name, fileType, dataSize });
        std.debug.dumpHex(fileData[0..@intCast(@min(dataSize, 16))]);
    }

    var image = try zigimg.Image.fromMemory(gpa, fileData[0..@intCast(dataSize)]);
    defer image.deinit(gpa);

    try image.convert(gpa, .rgba32);

    const rgba = image.pixels.rgba32;
    const PixelType = @typeInfo(@TypeOf(rgba)).pointer.child;
    const copy = try gpa.dupe(PixelType, rgba);

    return .{
        .width = @intCast(image.width),
        .height = @intCast(image.height),
        .pixels = @ptrCast(@alignCast(copy.ptr)),
    };
}

pub fn LoadTextureFromImage(image: Image) Texture2D {
    // @todo: Cleanup
    const sg = @import("sokol").gfx;

    const sokol_image = sg.makeImage(.{
        .width = image.width,
        .height = image.height,
        .data = sg.asRange(image.pixels[0..(image.width * image.height)]),
    });

    const view = sg.makeView(.{
        .texture = .{ .image = sokol_image },
    });

    return .{
        .width = image.width,
        .height = image.height,
        .image = sokol_image,
        .view = view,
    };
}

/// Deprecated
pub fn UnloadImage(image: Image, gpa: std.mem.Allocator) void {
    const aligned: []align(1) Color = image.pixels[0 .. image.width * image.height];
    gpa.free(aligned);
}

pub fn UnloadWave(wave: Wave) void {
    _ = wave;
    if (LogEnabled) log.debug("{s}()", .{@src().fn_name});
}

pub fn IsWaveValid(wave: Wave) bool {
    _ = wave;
    if (LogEnabled) log.debug("{s}()", .{@src().fn_name});
    return true;
}

pub fn IsSoundValid(sound: Sound) bool {
    _ = sound;
    if (LogEnabled) log.debug("{s}()", .{@src().fn_name});
    return true;
}

pub fn LoadSoundFromWave(wave: Wave) Sound {
    _ = wave;
    if (LogEnabled) log.debug("{s}()", .{@src().fn_name});
    return .{};
}

pub fn WindowShouldClose() bool {
    const S = struct {
        var frames: u8 = 100;
    };
    if (LogEnabled) log.debug("{s}()", .{@src().fn_name});

    if (S.frames > 0) {
        S.frames -= 1;
    }

    return S.frames == 0;
}

pub fn GetKeyPressed() Key {
    if (LogEnabled) log.debug("{s}()", .{@src().fn_name});
    return .A;
}

pub fn IsKeyDown(key: Key) bool {
    if (LogEnabled) log.debug("{s}({any})", .{ @src().fn_name, key });

    const S = struct {
        var key_prng: std.Random.DefaultPrng = undefined;
        var key_rng: std.Random = undefined;
        var initialized = false;
        var selected_key: usize = undefined;
        var change_key_timer: u32 = undefined;
    };

    const AwailableKeys = [_]Key{ .W, .A, .S, .D, .I, .J, .K, .L };

    if (!S.initialized) {
        S.key_prng = .init(0x6969);
        S.key_rng = S.key_prng.random();

        S.selected_key = S.key_rng.uintLessThan(usize, AwailableKeys.len);
        S.change_key_timer = S.key_rng.uintAtMost(u32, 200) + 1;

        S.initialized = true;
    }

    if (key == .L or key == .J or key == .I or key == .K or key == .W or key == .A or key == .S or key == .D) {
        S.change_key_timer -= 1;
        if (S.change_key_timer == 0) {
            S.selected_key = S.key_rng.uintLessThan(usize, AwailableKeys.len);
            S.change_key_timer = S.key_rng.uintAtMost(u32, 200) + 1;
        }

        return key == AwailableKeys[S.selected_key];
    }

    return false;
}

pub fn PlaySound(sound: Sound) void {
    _ = sound;
    if (LogEnabled) log.debug("{s}()", .{@src().fn_name});
}

pub fn GetFrameTime() f32 {
    if (false) {
        if (LogEnabled) log.debug("{s}()", .{@src().fn_name});
    }

    return 1.0 / 60.0;
}

pub fn GetScreenWidth() i32 {
    if (LogEnabled) log.debug("{s}()", .{@src().fn_name});
    return m.ScreenSize[0];
}

pub fn GetScreenHeight() i32 {
    if (LogEnabled) log.debug("{s}()", .{@src().fn_name});
    return m.ScreenSize[1];
}

pub fn MeasureText(text: [*c]const u8, fontSize: i32) i32 {
    if (LogEnabled) log.debug("{s}({s}, {d})", .{ @src().fn_name, text, fontSize });

    return 1 * fontSize;
}

pub fn DrawText(text: [*c]const u8, posX: i32, posY: i32, fontSize: i32, color: Color) void {
    if (LogEnabled) log.debug("{s}({s}, {d}, {d}, {d}, {any})", .{ @src().fn_name, text, posX, posY, fontSize, color });
}

pub fn ColorLerp(color1: Color, color2: Color, factor: f32) Color {
    const factor_norm = std.math.clamp(factor, 0, 1);

    var color: Color = .{};

    color.r = @intFromFloat(((1 - factor_norm) * @as(f32, @floatFromInt(color1.r)) + factor * @as(f32, @floatFromInt(color2.r))));
    color.g = @intFromFloat(((1 - factor_norm) * @as(f32, @floatFromInt(color1.g)) + factor * @as(f32, @floatFromInt(color2.g))));
    color.b = @intFromFloat(((1 - factor_norm) * @as(f32, @floatFromInt(color1.b)) + factor * @as(f32, @floatFromInt(color2.b))));
    color.a = @intFromFloat(((1 - factor_norm) * @as(f32, @floatFromInt(color1.a)) + factor * @as(f32, @floatFromInt(color2.a))));

    return color;
}

pub fn DrawRectangleV(position: Vector2, size: Vector2, color: Color) void {
    if (LogEnabled) log.debug("{s}({any}, {any}, {any})", .{ @src().fn_name, position, size, color });
}

pub fn GetTime() f64 {
    if (LogEnabled) log.debug("{s}()", .{@src().fn_name});
    return 0;
}

pub fn DrawFPS(posX: i32, posY: i32) void {
    if (LogEnabled) log.debug("{s}({d}, {d})", .{ @src().fn_name, posX, posY });
}

pub fn Vector2Lerp(arg_v1: Vector2, arg_v2: Vector2, arg_amount: f32) callconv(.c) Vector2 {
    var v1 = arg_v1;
    _ = &v1;
    var v2 = arg_v2;
    _ = &v2;
    var amount = arg_amount;
    _ = &amount;
    var result: Vector2 = Vector2{
        .x = @as(f32, @floatFromInt(@as(i32, 0))),
        .y = 0,
    };
    _ = &result;
    result.x = v1.x + (amount * (v2.x - v1.x));
    result.y = v1.y + (amount * (v2.y - v1.y));
    return result;
}

pub fn Vector2Add(arg_v1: Vector2, arg_v2: Vector2) callconv(.c) Vector2 {
    var v1 = arg_v1;
    _ = &v1;
    var v2 = arg_v2;
    _ = &v2;
    var result: Vector2 = Vector2{
        .x = v1.x + v2.x,
        .y = v1.y + v2.y,
    };
    _ = &result;
    return result;
}

pub fn Vector2Scale(arg_v: Vector2, arg_scale: f32) callconv(.c) Vector2 {
    var v = arg_v;
    _ = &v;
    var scale = arg_scale;
    _ = &scale;
    var result: Vector2 = Vector2{
        .x = v.x * scale,
        .y = v.y * scale,
    };
    _ = &result;
    return result;
}

pub fn Vector2Rotate(arg_v: Vector2, arg_angle: f32) callconv(.c) Vector2 {
    var v = arg_v;
    _ = &v;
    var angle = arg_angle;
    _ = &angle;
    var result: Vector2 = Vector2{
        .x = @as(f32, @floatFromInt(@as(i32, 0))),
        .y = 0,
    };
    _ = &result;
    var cosres: f32 = @cos(angle);
    _ = &cosres;
    var sinres: f32 = @sin(angle);
    _ = &sinres;
    result.x = (v.x * cosres) - (v.y * sinres);
    result.y = (v.x * sinres) + (v.y * cosres);
    return result;
}

pub fn Vector2Normalize(arg_v: Vector2) callconv(.c) Vector2 {
    var v = arg_v;
    _ = &v;
    var result: Vector2 = Vector2{
        .x = @as(f32, @floatFromInt(@as(i32, 0))),
        .y = 0,
    };
    _ = &result;
    var length: f32 = @sqrt((v.x * v.x) + (v.y * v.y));
    _ = &length;
    if (length > @as(f32, @floatFromInt(@as(i32, 0)))) {
        var ilength: f32 = 1.0 / length;
        _ = &ilength;
        result.x = v.x * ilength;
        result.y = v.y * ilength;
    }
    return result;
}

pub fn Vector2Distance(arg_v1: Vector2, arg_v2: Vector2) callconv(.c) f32 {
    var v1 = arg_v1;
    _ = &v1;
    var v2 = arg_v2;
    _ = &v2;
    var result: f32 = @sqrt(((v1.x - v2.x) * (v1.x - v2.x)) + ((v1.y - v2.y) * (v1.y - v2.y)));
    _ = &result;
    return result;
}

pub fn Vector2Length(arg_v: Vector2) callconv(.c) f32 {
    var v = arg_v;
    _ = &v;
    var result: f32 = @sqrt((v.x * v.x) + (v.y * v.y));
    _ = &result;
    return result;
}

pub fn Vector2DotProduct(arg_v1: Vector2, arg_v2: Vector2) callconv(.c) f32 {
    var v1 = arg_v1;
    _ = &v1;
    var v2 = arg_v2;
    _ = &v2;
    var result: f32 = (v1.x * v2.x) + (v1.y * v2.y);
    _ = &result;
    return result;
}

pub fn Vector2Subtract(arg_v1: Vector2, arg_v2: Vector2) callconv(.c) Vector2 {
    var v1 = arg_v1;
    _ = &v1;
    var v2 = arg_v2;
    _ = &v2;
    var result: Vector2 = Vector2{
        .x = v1.x - v2.x,
        .y = v1.y - v2.y,
    };
    _ = &result;
    return result;
}

pub fn Vector2ClampValue(arg_v: Vector2, arg_min: f32, arg_max: f32) callconv(.c) Vector2 {
    var v = arg_v;
    _ = &v;
    var min = arg_min;
    _ = &min;
    var max = arg_max;
    _ = &max;
    var result: Vector2 = v;
    _ = &result;
    var length: f32 = (v.x * v.x) + (v.y * v.y);
    _ = &length;
    if (length > 0.0) {
        length = @sqrt(length);
        var scale: f32 = 1;
        _ = &scale;
        if (length < min) {
            scale = min / length;
        } else if (length > max) {
            scale = max / length;
        }
        result.x = v.x * scale;
        result.y = v.y * scale;
    }
    return result;
}

pub fn DrawRectangle(posX: i32, posY: i32, width: i32, height: i32, color: Color) void {
    if (LogEnabled) log.debug("{s}({d}, {d}, {d}, {d}, {any})", .{ @src().fn_name, posX, posY, width, height, color });
}

pub fn DrawTexturePro(texture: Texture2D, source: Rectangle, dest: Rectangle, origin: Vector2, rotation: f32, tint: Color) void {
    if (LogEnabled) log.debug("{s}({any}, {any}, {any}, {any}, {d}, {any})", .{ @src().fn_name, texture, source, dest, origin, rotation, tint });

    const q: m.Quad = .{
        .pos = .{ dest.x + current_camera.offset.x, dest.y + current_camera.offset.y },
        .size = .{ 16, 16 },
        .origin = .{ 0, 0 },
        .screen_size = m.ScreenSize,
        .color = @bitCast(tint),
    };

    m.sokol_state.immediate_render.pushQuad(q.toVertices(), texture.view);
}

pub fn BeginDrawing() void {
    if (LogEnabled) log.debug("{s}()", .{@src().fn_name});
}

pub fn EndDrawing() void {
    if (LogEnabled) log.debug("{s}()", .{@src().fn_name});
}

var current_camera: Camera2D = .{};

pub fn BeginMode2D(camera: Camera2D) void {
    if (LogEnabled) log.debug("{s}({any})", .{ @src().fn_name, camera });
    current_camera = camera;
}

pub fn EndMode2D() void {
    if (LogEnabled) log.debug("{s}()", .{@src().fn_name});
}

pub fn ClearBackground(color: Color) void {
    if (LogEnabled) log.debug("{s}({any})", .{ @src().fn_name, color });
}

pub fn ColorToHSV(color: Color) Vector3 {
    // @note: Converted from Raylib
    var hsv: Vector3 = .{ .x = 0, .y = 0, .z = 0 };

    const rgb: Vector3 = .{
        .x = @as(f32, color.r) / 255,
        .y = @as(f32, color.g) / 255,
        .z = @as(f32, color.b) / 255,
    };

    var min: f32 = 0;
    var max: f32 = 0;
    var delta: f32 = 0;

    min = if (rgb.x < rgb.y) rgb.x else rgb.y;
    min = if (min < rgb.z) min else rgb.z;

    max = if (rgb.x > rgb.y) rgb.x else rgb.y;
    max = if (max > rgb.z) max else rgb.z;

    hsv.z = max;
    delta = max - min;

    if (delta < 0.00001) {
        hsv.y = 0;
        hsv.x = 0; // Undefined, maybe NAN?
        return hsv;
    }

    if (max > 0) {
        // NOTE: If max is 0, this divide would cause a crash
        hsv.y = (delta / max); // Saturation
    } else {
        // NOTE: If max is 0, then r = g = b = 0, s = 0, h is undefined
        hsv.y = 0.0;
        hsv.x = std.math.nan(f32); // Undefined
        return hsv;
    }

    // NOTE: Comparing float values could not work properly
    if (rgb.x >= max) {
        hsv.x = (rgb.y - rgb.z) / delta; // Between yellow & magenta
    } else {
        if (rgb.y >= max) {
            hsv.x = 2.0 + (rgb.z - rgb.x) / delta; // Between cyan & yellow
        } else {
            hsv.x = 4.0 + (rgb.x - rgb.y) / delta; // Between magenta & cyan
        }
    }

    hsv.x *= 60.0; // Convert to degrees

    if (hsv.x < 0) hsv.x += 360.0;

    return hsv;
}

const HsvChannel = enum { red, green, blue };

fn hsvChannel(comptime c: HsvChannel, hue: f32, saturation: f32, value: f32) u8 {
    const channel_value: f32 = switch (c) {
        .red => 4,
        .green => 3,
        .blue => 1,
    };

    var k: f32 = @mod(channel_value + hue / 60, 6);
    const t: f32 = 4 - k;
    k = if (t < k) t else k;
    k = if (k < 1) k else 1;
    k = if (k > 0) k else 0;
    return @intFromFloat((value - value * saturation * k) * 0xFF);
}

pub fn ColorFromHSV(hue: f32, saturation: f32, value: f32) Color {
    if (LogEnabled) log.debug("{s}({d}, {d}, {d})", .{ @src().fn_name, hue, saturation, value });
    return .{
        .r = hsvChannel(.red, hue, saturation, value),
        .g = hsvChannel(.green, hue, saturation, value),
        .b = hsvChannel(.blue, hue, saturation, value),
        .a = 255,
    };
}

pub fn Vector2Clamp(arg_v: Vector2, arg_min: Vector2, arg_max: Vector2) callconv(.c) Vector2 {
    var v = arg_v;
    _ = &v;
    var min = arg_min;
    _ = &min;
    var max = arg_max;
    _ = &max;
    var result: Vector2 = Vector2{
        .x = @as(f32, @floatFromInt(@as(i32, 0))),
        .y = 0,
    };
    _ = &result;
    result.x = @min(max.x, @max(min.x, v.x));
    result.y = @min(max.y, @max(min.y, v.y));
    return result;
}

pub const Key = enum(i32) {
    none = 0,
    A = 65,
    D = 68,
    S = 83,
    W = 87,
    I = 73,
    J = 74,
    K = 75,
    L = 76,
    RIGHT = 262,
    LEFT = 263,
    DOWN = 264,
    UP = 265,
};

pub const LIGHTGRAY = Color.init(200, 200, 200, 255);
pub const GRAY = Color.init(130, 130, 130, 255);
pub const DARKGRAY = Color.init(80, 80, 80, 255);
pub const YELLOW = Color.init(253, 249, 0, 255);
pub const GOLD = Color.init(255, 203, 0, 255);
pub const ORANGE = Color.init(255, 161, 0, 255);
pub const PINK = Color.init(255, 109, 194, 255);
pub const RED = Color.init(230, 41, 55, 255);
pub const MAROON = Color.init(190, 33, 55, 255);
pub const GREEN = Color.init(0, 228, 48, 255);
pub const LIME = Color.init(0, 158, 47, 255);
pub const DARKGREEN = Color.init(0, 117, 44, 255);
pub const SKYBLUE = Color.init(102, 191, 255, 255);
pub const BLUE = Color.init(0, 121, 241, 255);
pub const DARKBLUE = Color.init(0, 82, 172, 255);
pub const PURPLE = Color.init(200, 122, 255, 255);
pub const VIOLET = Color.init(135, 60, 190, 255);
pub const DARKPURPLE = Color.init(112, 31, 126, 255);
pub const BEIGE = Color.init(211, 176, 131, 255);
pub const BROWN = Color.init(127, 106, 79, 255);
pub const DARKBROWN = Color.init(76, 63, 47, 255);
pub const WHITE = Color.init(255, 255, 255, 255);
pub const BLACK = Color.init(0, 0, 0, 255);
pub const BLANK = Color.init(0, 0, 0, 0);
pub const MAGENTA = Color.init(255, 0, 255, 255);
pub const RAYWHITE = Color.init(245, 245, 245, 255);

const std = @import("std");
const log = std.log;
const assert = std.debug.assert;

const m = @import("main.zig");
