const TransformStack = @This();

ms: [MaxModelMatrices]mat3 = undefined,
ms_count: u8 = 0,
vp: mat3 = la.Mat3Identity,
mvp: mat3 = la.Mat3Identity,

pub fn reset(self: *TransformStack, vp: mat3) void {
    self.* = .{ .vp = vp };
    self.updateModelViewProjection();
}

pub fn push(self: *TransformStack, m: mat3) void {
    assert(self.ms_count < self.ms.len);
    self.ms[self.ms_count] = m;
    self.updateModelViewProjection();
}

pub fn pop(self: *TransformStack) void {
    assert(self.ms_count > 0);
    self.ms_count -= 1;
    self.updateModelViewProjection();
}

fn updateModelViewProjection(self: *TransformStack) void {
    if (self.ms_count == 0) {
        self.mvp = self.vp;
    } else {
        self.mvp = la.mul(self.ms[self.ms_count - 1], self.vp);
    }
}

const MaxModelMatrices = 16;

const std = @import("std");
const assert = std.debug.assert;
const log = std.log;

const la = @import("linalg.zig");
const vec3 = la.vec3;
const mat3 = la.mat3;
