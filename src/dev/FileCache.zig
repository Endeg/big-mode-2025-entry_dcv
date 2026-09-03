const FileCache = @This();

allocator: std.mem.Allocator,
file_locations: std.StringHashMapUnmanaged(FileLocation),
file_names_arena: std.heap.ArenaAllocator,
loaded: std.AutoHashMapUnmanaged(FileLocation.Handle, []const u8),

pub fn init(allocator: std.mem.Allocator) !FileCache {
    var current_handle: usize = 0;

    const MaxEntries = 1024 * 32;

    var file_locations = std.StringHashMapUnmanaged(FileLocation){};
    try file_locations.ensureTotalCapacity(allocator, MaxEntries);

    var loaded = std.AutoHashMapUnmanaged(FileLocation.Handle, []const u8).empty;
    try loaded.ensureTotalCapacity(allocator, MaxEntries);

    var file_names_arena = std.heap.ArenaAllocator.init(allocator);

    inline for (AssetDirectories) |asset_dir| {
        var d = try std.fs.openDirAbsolute(asset_dir, .{ .iterate = true });
        defer d.close();
        var it = d.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .file) {
                inline for (AssetExtensions) |ext| {
                    const entry_ext = entry.name[entry.name.len - ext.len ..];
                    if (std.mem.eql(u8, entry_ext, ext)) {
                        const key = try file_names_arena.allocator().dupe(u8, entry.name);

                        if (file_locations.get(key)) |existing_entry| {
                            std.log.warn(
                                "[dev] Same file name detected for {s}/{s}: already exist as {s}/{s} ({any}).",
                                .{ asset_dir, key, existing_entry.directory_path, existing_entry.file_name, existing_entry.handle },
                            );
                        } else {
                            file_locations.putAssumeCapacityNoClobber(key, .{
                                .directory_path = asset_dir,
                                .file_name = key,
                                .handle = @enumFromInt(current_handle),
                            });
                        }

                        current_handle += 1;
                    }
                }
            }
        }
    }

    std.log.debug("[dev] {d} files detected.", .{file_locations.size});

    return .{
        .allocator = allocator,
        .file_locations = file_locations,
        .file_names_arena = file_names_arena,
        .loaded = loaded,
    };
}

pub fn deinit(self: *FileCache) void {
    {
        var it = self.loaded.valueIterator();
        while (it.next()) |data| {
            self.allocator.free(data.*);
        }
    }
    self.loaded.deinit(self.allocator);
    self.file_locations.deinit(self.allocator);
    self.file_names_arena.deinit();
}

fn loadFileContents(loc: FileLocation, allocator: std.mem.Allocator) ![]const u8 {
    std.log.debug("Trying to load file from {s}/{s}.", .{ loc.directory_path, loc.file_name });
    var d = try std.fs.openDirAbsolute(loc.directory_path, .{});
    defer d.close();

    var f = try d.openFile(loc.file_name, .{});
    defer f.close();

    const stat = try f.stat();

    const target_buffer = try allocator.alloc(u8, @intCast(stat.size));
    const bytes_read = try f.readAll(target_buffer);
    std.debug.assert(bytes_read == target_buffer.len);
    return target_buffer;
}

pub fn get(self: *FileCache, name: []const u8) []const u8 {
    if (self.file_locations.get(name)) |loc| {
        if (self.loaded.get(loc.handle)) |data| {
            return data;
        } else {
            const data = loadFileContents(loc, self.allocator) catch |err| {
                std.log.err(
                    "Problem loading file from {s}/{s}: {any}!",
                    .{ loc.directory_path, loc.file_name, err },
                );
                return &.{};
            };

            if (data.len > 0) {
                self.loaded.putAssumeCapacity(loc.handle, data);
            }
            return data;
        }
    } else {
        std.log.err("File '{s}' was not found!", .{name});
        return &.{};
    }
}

pub fn getHandle(self: *const FileCache, name: []const u8) ?FileLocation.Handle {
    if (self.file_locations.get(name)) |loc| {
        return loc.handle;
    } else {
        return null;
    }
}

const FileLocation = struct {
    directory_path: []const u8,
    file_name: []const u8,
    handle: Handle,

    const Handle = enum(usize) { _ };
};

pub const FileLocationHandle = FileLocation.Handle;

const std = @import("std");
const Config = @import("../BuildConfig.zig").Config;
const AssetDirectories = Config.asset_directories;
const AssetExtensions = Config.asset_extensions;
