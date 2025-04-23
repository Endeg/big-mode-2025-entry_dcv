const Editor = @This();

file_cache: *FileCache,
image_file_names: std.ArrayListUnmanaged([]const u8),

fn compareStrings(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs).compare(std.math.CompareOperator.lt);
}

pub fn init(file_cache: *FileCache, allocator: std.mem.Allocator) !Editor {
    var image_file_names = try std.ArrayListUnmanaged([]const u8).initCapacity(allocator, file_cache.file_locations.size);

    {
        const ImageExts = .{ ".png", ".jpg" };

        var it = file_cache.file_locations.keyIterator();
        while (it.next()) |file_name| {
            var is_image = false;
            inline for (ImageExts) |ext| {
                if (std.mem.endsWith(u8, file_name.*, ext)) {
                    is_image = true;
                    break;
                }
            }

            if (is_image) {
                image_file_names.appendAssumeCapacity(file_name.*);
            }
        }
        std.mem.sort([]const u8, image_file_names.items, void{}, compareStrings);
    }

    return .{
        .file_cache = file_cache,
        .image_file_names = image_file_names,
    };
}

const std = @import("std");
const log = std.log;
const assert = std.debug.assert;

const FileCache = @import("FileCache.zig");
