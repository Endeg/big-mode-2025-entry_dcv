const Gui = @This();

const StyleNormal = rl.BLACK;
const StyleHover = rl.BLUE;
const StyleClicked = rl.RED;

const FontSize = 20;
const DefaultFontSize = 10;
const RowHeight = FontSize + 1;
const Spacing = FontSize / DefaultFontSize;

font: rl.Font,
input: Input = .{},
layout_state: LayoutState = .{},
controls: std.MultiArrayList(Control),
fba: std.heap.FixedBufferAllocator,

const MaxControls = 8 * 1024;
const FixedBufferSize = 8 * 1024 * 1024;

//TODO: Контроль layout'а.

pub fn init(allocator: std.mem.Allocator) !Gui {
    const fixed_buffer = try allocator.alloc(u8, FixedBufferSize);

    var controls = std.MultiArrayList(Control).empty;
    try controls.ensureTotalCapacity(allocator, MaxControls);

    return .{
        .font = rl.GetFontDefault(),
        .controls = controls,
        .fba = std.heap.FixedBufferAllocator.init(fixed_buffer),
    };
}

pub fn deinit(self: *Gui, allocator: std.mem.Allocator) void {
    self.controls.deinit(allocator);
    allocator.free(self.fba.buffer);
}

pub fn resetAndProcessInput(self: *Gui) void {
    self.layout_state = .{};
    self.fba.reset();
    self.controls.clearRetainingCapacity();
    self.input.mouse_click = rl.IsMouseButtonPressed(.Left);
    self.input.mouse_position = rl.GetMousePosition();
    self.input.screen_width = rl.GetScreenWidth();
    self.input.screen_height = rl.GetScreenHeight();
}

pub fn render(self: Gui) void {
    for (0..self.controls.len) |i| {
        const rect = self.controls.items(.rect)[i];
        const info = self.controls.items(.info)[i];

        const color = switch (self.mouseInteraction(rect)) {
            .None => StyleNormal,
            .Hovered => StyleHover,
            .Clicked => StyleClicked,
        };

        switch (info) {
            .Label => |text| rl.DrawTextEx(self.font, text.ptr, .{ .x = rect.x, .y = rect.y }, FontSize, Spacing, color),
        }
    }
}

pub fn label(self: *Gui, text: []const u8) void {
    const allocator = self.fba.allocator();

    const text_z = allocator.dupeZ(u8, text) catch |err| {
        log.err("Can't allocate null-terminated text for label: {!}!", .{err});
        return;
    };

    const text_size = rl.MeasureTextEx(self.font, text_z, FontSize, Spacing);

    self.controls.appendAssumeCapacity(.{
        .rect = .{
            .x = 2,
            .y = @floatFromInt(self.layout_state.y),
            .width = text_size.x,
            .height = text_size.y,
        },
        .info = .{ .Label = text_z },
    });

    self.layout_state.y += RowHeight;
}

fn mouseInteraction(
    self: Gui,
    control_rect: rl.Rectangle,
) MouseInteractionState {
    if (rl.CheckCollisionPointRec(self.input.mouse_position, control_rect)) {
        if (self.input.mouse_click) {
            return .Clicked;
        } else {
            return .Hovered;
        }
    } else {
        return .None;
    }
}

const Input = struct {
    mouse_position: rl.Vector2 = .{},
    mouse_click: bool = false,
    screen_width: i32 = 0,
    screen_height: i32 = 0,
};

const MouseInteractionState = enum {
    None,
    Hovered,
    Clicked,
};

const Control = struct {
    rect: rl.Rectangle,
    info: Info,

    const Info = union(Tag) {
        Label: []const u8,
        const Tag = enum(u8) {
            Label,
        };
    };
};

const LayoutState = struct {
    y: i32 = 0,
};

const std = @import("std");
const log = std.log;
const assert = std.debug.assert;

const rl = @import("../raylib.zig");
