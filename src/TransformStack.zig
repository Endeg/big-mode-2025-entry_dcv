const TransformStack = @This();

ms: [MaxModelMatrices]Mat3 = undefined,
ms_count: u8 = 0,
vp: Mat3 = .identity,
mvp: Mat3 = .identity,

pub fn reset(self: *TransformStack, vp: Mat3) void {
    self.* = .{ .vp = vp };
    self.updateModelViewProjection();
}

pub fn push(self: *TransformStack, m: Mat3) void {
    assert(self.ms_count < self.ms.len);
    if (self.ms_count == 0) {
        self.ms[self.ms_count] = m;
    } else {
        self.ms[self.ms_count] = self.ms[self.ms_count - 1].times(m);
    }
    self.ms_count += 1;
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
        self.mvp = self.vp.times(self.ms[self.ms_count - 1]);
    }
}

const MaxModelMatrices = 16;

const Vec3 = @Vector(3, f32);

const std = @import("std");
const assert = std.debug.assert;
const log = std.log;

const la = @import("mr_geom");
const Mat3 = la.Mat3;
