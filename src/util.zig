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
