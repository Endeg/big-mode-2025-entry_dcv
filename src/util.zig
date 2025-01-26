const std = @import("std");
const assert = std.debug.assert;
const log = std.log;

pub fn readEntireFileAlloc(
    directory: []const u8,
    file_name: []const u8,
    allocator: std.mem.Allocator,
) ![]const u8 {
    log.debug("[File] {s}/{s} loading...", .{ directory, file_name });
    var d = try std.fs.cwd().openDir(directory, .{});
    defer d.close();
    var f = try d.openFile(file_name, .{});
    defer f.close();
    const file_size: usize = @intCast((try f.stat()).size);
    const file_data = try f.readToEndAlloc(allocator, file_size);
    log.debug("[File] {s}/{s} loaded, size {d} bytes.", .{ directory, file_name, file_data.len });
    return file_data;
}

pub const FileWatcher = struct {
    f: std.fs.File,
    check_frequency: f32,
    next_check_in: f32 = 0,
    modification_time: i128,

    const Self = @This();

    pub fn init(directory: []const u8, file_name: []const u8, check_frequency: f32) !Self {
        var d = try std.fs.cwd().openDir(directory, .{});
        defer d.close();

        var f = try d.openFile(file_name, .{});

        return .{
            .f = f,
            .check_frequency = check_frequency,
            .modification_time = (try f.stat()).mtime,
        };
    }

    pub fn deinit(self: *Self) void {
        self.f.close();
    }

    pub fn wasModified(self: *Self, dt: f32) bool {
        self.next_check_in += dt;
        if (self.next_check_in >= self.check_frequency) {
            self.next_check_in -= self.check_frequency;
            if (self.f.stat()) |s| {
                if (s.mtime != self.modification_time) {
                    self.modification_time = s.mtime;
                    return true;
                }
            } else |err| {
                log.err("Problem checking file {any} stats: {!}!", .{ self.f, err });
            }
        }
        return false;
    }
};
