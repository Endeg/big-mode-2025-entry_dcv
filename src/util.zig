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

const std = @import("std");
const assert = std.debug.assert;
const log = std.log;
