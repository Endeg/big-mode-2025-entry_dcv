pub fn readEntireFileAlloc(
    directory: []const u8,
    file_name: []const u8,
    allocator: std.mem.Allocator,
    io: std.Io,
) ![]const u8 {
    log.debug("[File] {s}/{s} loading...", .{ directory, file_name });

    var d = try std.Io.Dir.cwd().openDir(io, directory, .{});
    defer d.close(io);
    var f = try d.openFile(io, file_name, .{});
    defer f.close(io);
    const file_size: usize = @intCast((try f.stat(io)).size);
    var buffer: [16]u8 = undefined;
    var r = f.reader(io, buffer[0..]);
    const file_data = try r.interface.readAlloc(allocator, file_size);
    log.debug("[File] {s}/{s} loaded, size {d} bytes.", .{ directory, file_name, file_data.len });
    return file_data;
}

pub const FileWatcher = struct {
    f: std.Io.File,
    check_frequency: f32,
    next_check_in: f32 = 0,
    modification_time: std.Io.Timestamp,

    const Self = @This();

    pub fn init(directory: []const u8, file_name: []const u8, check_frequency: f32, io: std.Io) !Self {
        var d = try std.Io.Dir.cwd().openDir(io, directory, .{});
        defer d.close(io);

        var f = try d.openFile(io, file_name, .{});

        return .{
            .f = f,
            .check_frequency = check_frequency,
            .modification_time = (try f.stat(io)).mtime,
        };
    }

    pub fn deinit(self: *Self, io: std.Io) void {
        self.f.close(io);
    }

    pub fn wasModified(self: *Self, dt: f32, io: std.Io) bool {
        self.next_check_in += dt;
        if (self.next_check_in >= self.check_frequency) {
            self.next_check_in -= self.check_frequency;
            if (self.f.stat(io)) |s| {
                if (s.mtime.toMilliseconds() != self.modification_time.toMilliseconds()) {
                    self.modification_time = s.mtime;
                    return true;
                }
            } else |err| {
                log.err("Problem checking file {any} stats: {any}!", .{ self.f, err });
            }
        }
        return false;
    }
};

pub fn loggerFunction(tag: [*c]const u8, log_level: u32, log_item: u32, maybe_message: [*c]const u8, line_nr: u32, maybe_filename: [*c]const u8, user_data: ?*anyopaque) callconv(.c) void {
    _ = user_data; // autofix

    const Level = enum(u32) {
        panic = 0,
        @"error" = 1,
        warning = 2,
        _,
    };

    const level: Level = @fromBackingInt(log_level);

    if (maybe_message) |message| {
        if (maybe_filename) |filename| {
            switch (level) {
                .panic => log.err("panic! [id:{d}] [{s}] {s}:{d} {s}", .{ log_item, tag, filename, line_nr, message }),
                .@"error" => log.err("[id:{d}] [{s}] {s}:{d} {s}", .{ log_item, tag, filename, line_nr, message }),
                .warning => log.warn("[id:{d}] [{s}] {s}:{d} {s}", .{ log_item, tag, filename, line_nr, message }),
                else => log.info("[id:{d}] [{s}] {s}:{d} {s}", .{ log_item, tag, filename, line_nr, message }),
            }
        } else {
            switch (level) {
                .panic => log.err("panic! [id:{d}] [{s}] {s}", .{ log_item, tag, message }),
                .@"error" => log.err("[id:{d}] [{s}] {s}", .{ log_item, tag, message }),
                .warning => log.warn("[id:{d}] [{s}] {s}", .{ log_item, tag, message }),
                else => log.info("[id:{d}] [{s}] {s}", .{ log_item, tag, message }),
            }
        }
    } else {
        switch (level) {
            .panic => log.err("panic! [id:{d}] [{s}] no message", .{ log_item, tag }),
            .@"error" => log.err("[id:{d}] [{s}] no message", .{ log_item, tag }),
            .warning => log.warn("[id:{d}] [{s}] no message", .{ log_item, tag }),
            else => log.info("[id:{d}] [{s}] no message", .{ log_item, tag }),
        }
    }
}

const std = @import("std");
const assert = std.debug.assert;
const log = std.log;
