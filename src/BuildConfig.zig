const BuildConfig = @This();

pub const Config: BuildConfig = @import("config.zon");

asset_directories: []const []const u8 = &.{},
asset_extensions: []const []const u8 = &.{},
