pub const FLAG_WINDOW_RESIZABLE: i32 = 4;

pub const Sound = struct {};
pub const Wave = struct {};
pub const Texture2D = struct {
    width: i32,
    height: i32,
};
pub const Image = struct {};
pub const Rectangle = struct { x: f32 = 0, y: f32 = 0, width: f32 = 0, height: f32 = 0 };
pub const Vector2 = extern struct { x: f32 = 0, y: f32 = 0 };
pub const Vector3 = extern struct { x: f32 = 0, y: f32 = 0, z: f32 = 0 };
pub const Color = struct {
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

pub fn InitWindow(width: i32, height: i32, title: [*c]const u8) void {
    log.debug("{s}({d}, {d}, {s})", .{ @src().fn_name, width, height, title });
}

pub fn CloseWindow() void {
    log.debug("{s}()", .{
        @src().fn_name,
    });
}

pub fn SetConfigFlags(flags: u32) void {
    log.debug("{s}({X:8})", .{ @src().fn_name, flags });
}

pub fn SetTargetFPS(fps: i32) void {
    log.debug("{s}({d})", .{ @src().fn_name, fps });
}

pub fn LoadWaveFromMemory(fileType: [*c]const u8, fileData: [*c]const u8, dataSize: i32) Wave {
    log.debug("{s}({s}, <fileData>, {d})", .{ @src().fn_name, fileType, dataSize });
    std.debug.dumpHex(fileData[0..@intCast(@min(dataSize, 16))]);
    return .{};
}

pub fn LoadImageFromMemory(fileType: [*c]const u8, fileData: [*c]const u8, dataSize: i32) Image {
    log.debug("{s}({s}, <fileData>, {d})", .{ @src().fn_name, fileType, dataSize });
    std.debug.dumpHex(fileData[0..@intCast(@min(dataSize, 16))]);
    return .{};
}

pub fn LoadTextureFromImage(image: Image) Texture2D {
    _ = image;
    log.debug("{s}()", .{@src().fn_name});
    return .{
        .width = 8,
        .height = 8,
    };
}

pub fn UnloadImage(image: Image) void {
    log.debug("{s}()", .{@src().fn_name});
    _ = image;
}

pub fn UnloadWave(wave: Wave) void {
    _ = wave;
    log.debug("{s}()", .{@src().fn_name});
}

pub fn IsWaveValid(wave: Wave) bool {
    _ = wave;
    log.debug("{s}()", .{@src().fn_name});
    return true;
}

pub fn IsSoundValid(sound: Sound) bool {
    _ = sound;
    log.debug("{s}()", .{@src().fn_name});
    return true;
}

pub fn LoadSoundFromWave(wave: Wave) Sound {
    _ = wave;
    log.debug("{s}()", .{@src().fn_name});
    return .{};
}

pub fn WindowShouldClose() bool {
    const S = struct {
        var frames: u8 = 100;
    };
    log.debug("{s}()", .{@src().fn_name});

    if (S.frames > 0) {
        S.frames -= 1;
    }

    return S.frames == 0;
}

pub fn GetKeyPressed() Key {
    log.debug("{s}()", .{@src().fn_name});
    return .A;
}

pub fn IsKeyDown(key: Key) bool {
    log.debug("{s}({any})", .{ @src().fn_name, key });
    return false;
}
pub fn IsKeyUp(key: Key) bool {
    log.debug("{s}({any})", .{ @src().fn_name, key });
    return false;
}

pub fn PlaySound(sound: Sound) void {
    _ = sound;
    log.debug("{s}()", .{@src().fn_name});
}

pub fn GetFrameTime() f32 {
    if (false) {
        log.debug("{s}()", .{@src().fn_name});
    }

    return 1 / 60;
}

pub fn GetScreenWidth() i32 {
    log.debug("{s}()", .{@src().fn_name});
    return 1280;
}

pub fn GetScreenHeight() i32 {
    log.debug("{s}()", .{@src().fn_name});
    return 720;
}

pub fn MeasureText(text: [*c]const u8, fontSize: i32) i32 {
    log.debug("{s}({s}, {d})", .{ @src().fn_name, text, fontSize });

    return 1 * fontSize;
}

pub fn DrawText(text: [*c]const u8, posX: i32, posY: i32, fontSize: i32, color: Color) void {
    log.debug("{s}({s}, {d}, {d}, {d}, {any})", .{ @src().fn_name, text, posX, posY, fontSize, color });
}

pub fn ColorLerp(color1: Color, color2: Color, factor: f32) Color {
    log.debug("{s}({any}, {any}, {d})", .{ @src().fn_name, color1, color2, factor });
    return .{};
}

pub fn DrawRectangleV(position: Vector2, size: Vector2, color: Color) void {
    log.debug("{s}({any}, {any}, {any})", .{ @src().fn_name, position, size, color });
}

pub fn GetTime() f64 {
    log.debug("{s}()", .{@src().fn_name});
    return 0;
}

pub fn DrawFPS(posX: i32, posY: i32) void {
    log.debug("{s}({d}, {d})", .{ @src().fn_name, posX, posY });
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
    log.debug("{s}({d}, {d}, {d}, {d}, {any})", .{ @src().fn_name, posX, posY, width, height, color });
}

pub fn DrawTexturePro(texture: Texture2D, source: Rectangle, dest: Rectangle, origin: Vector2, rotation: f32, tint: Color) void {
    log.debug("{s}({any}, {any}, {any}, {any}, {d}, {any})", .{ @src().fn_name, texture, source, dest, origin, rotation, tint });
}

pub fn BeginDrawing() void {
    log.debug("{s}()", .{@src().fn_name});
}

pub fn EndDrawing() void {
    log.debug("{s}()", .{@src().fn_name});
}

pub fn BeginMode2D(camera: Camera2D) void {
    log.debug("{s}({any})", .{ @src().fn_name, camera });
}

pub fn EndMode2D() void {
    log.debug("{s}()", .{@src().fn_name});
}

pub fn ClearBackground(color: Color) void {
    log.debug("{s}({any})", .{ @src().fn_name, color });
}

pub fn ColorToHSV(color: Color) Vector3 {
    log.debug("{s}({any})", .{ @src().fn_name, color });
    return .{};
}

pub fn ColorFromHSV(hue: f32, saturation: f32, value: f32) Color {
    log.debug("{s}({d}, {d}, {d})", .{ @src().fn_name, hue, saturation, value });
    return .{};
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
