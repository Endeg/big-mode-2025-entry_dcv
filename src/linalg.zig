pub const vec2 = @Vector(2, f32);
pub const mat2 = [2]vec2;

pub const vec3 = @Vector(3, f32);
pub const mat3 = [3]vec3;

pub fn dot(a: anytype, b: @TypeOf(a)) VectorElement(@TypeOf(a)) {
    const res = @reduce(.Add, a * b);
    if (false) log.err("dot {any} * {any} = {any}", .{ a, b, res });
    return res;
}

pub fn transform(v: anytype, m: anytype) @TypeOf(v) {
    vectorAndMatrixCompatible(v, m);

    const length = @typeInfo(@TypeOf(v)).vector.len;

    var result: @TypeOf(v) = undefined;

    inline for (0..length) |i| {
        result[i] = dot(v, m[i]);
    }

    return result;
}

pub fn mul(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    assertMatrix(a);

    const T = @TypeOf(a);
    const VT = @typeInfo(@TypeOf(a)).array.child;

    var result: T = undefined;
    inline for (0..a.len) |r| {
        const v_b = b[r];
        inline for (0..a.len) |c| {
            const v_a: VT = @splat(a[r][c]);
            result[r][c] = dot(v_a, v_b);
        }
    }
    return result;
}

fn vectorAndMatrixCompatible(v: anytype, m: anytype) void {
    const VectorMetadata = @typeInfo(@TypeOf(v)).vector;
    const VT = VectorMetadata.child;
    const MT = @typeInfo(@typeInfo(@TypeOf(m)).array.child).vector.child;
    const length = VectorMetadata.len;

    assert(VT == MT);
    assert(length == m.len);
    assert(length == @typeInfo(@typeInfo(@TypeOf(m)).array.child).vector.len);
}

fn assertMatrix(a: anytype) void {
    const Rows = @typeInfo(@TypeOf(a)).array;
    const Columns = @typeInfo(Rows.child).vector;
    assert(Rows.len == Columns.len);
}

fn VectorElement(T: type) type {
    return @typeInfo(T).vector.child;
}

test "mat2 identity" {
    const expectEqual = std.testing.expectEqual;

    var prng: std.Random.DefaultPrng = .init(@intCast(std.testing.random_seed));
    const rng = prng.random();

    const v: vec2 = .{
        rng.float(f32),
        rng.float(f32),
    };

    const m: mat2 = .{
        .{ 1, 0 },
        .{ 0, 1 },
    };

    const res = transform(v, m);
    try expectEqual(v, res);
}

test "mat3 identity" {
    const expectEqual = std.testing.expectEqual;

    var prng: std.Random.DefaultPrng = .init(@intCast(std.testing.random_seed));
    const rng = prng.random();

    const v: vec3 = .{
        rng.float(f32),
        rng.float(f32),
        rng.float(f32),
    };

    const m: mat3 = .{
        .{ 1, 0, 0 },
        .{ 0, 1, 0 },
        .{ 0, 0, 1 },
    };

    const res = transform(v, m);
    try expectEqual(v, res);
}

test "mat3 translate" {
    const expectEqual = std.testing.expectEqual;

    // var prng: std.Random.DefaultPrng = .init(@intCast(std.testing.random_seed));
    // const rng = prng.random();

    const v: vec3 = .{ 3, 6, 1 };

    const m: mat3 = .{
        .{ 1, 0, 7 },
        .{ 0, 1, 4 },
        .{ 0, 0, 1 },
    };

    const expected: vec3 = .{ 10, 10, 1 };

    const res = transform(v, m);
    try expectEqual(expected, res);
}

const std = @import("std");
const assert = std.debug.assert;
const log = std.log;
