const GlobalConfig = @This();

const std = @import("std");
const assert = std.debug.assert;
const log = std.log;

const util = @import("util.zig");

camera_lerp_value: f32 = 0.05,
player_acc_magnitude: f32 = 200,
general_radius: f32 = 8,
general_center_from_bottom: f32 = 8,
player_damping: f32 = 0.8,
player_max_velocity: f32 = 100,
player_mass: f32 = 150,
player_shoot_cooldown: f32 = 0.4,
player_blaster_distance: f32 = 7,
player_shoot_start_distance: f32 = 17,
player_shoot_hands_height: f32 = 6,
player_projectile_acceleration_magnitude: f32 = 700,
player_projectile_damping: f32 = 1,
player_projectile_max_velocity: f32 = 800,
player_projectile_ttl: f32 = 0.8,
player_hop_distance: f32 = 20,
player_hop_amp: f32 = 4,
projectile_radius: f32 = 2,
enemy_loiter_time: f32 = 3,
enemy_aggression_distance: f32 = 200,
enemy_damping: f32 = 0.9,
enemy_acc_magnitude: f32 = 100,
enemy_max_velocity: f32 = 90,
enemy_mass: f32 = 300,
enemy_pursuit_dispersal: f32 = 50,
enemy_hop_distance: f32 = 20,
enemy_hop_amp: f32 = 4,
damage_inertia_factor: f32 = 0.5,
iframes: f32 = 2,
damage_animation_speed: f32 = 10,

pub fn load(directory: []const u8, file_name: []const u8, allocator: std.mem.Allocator) ?GlobalConfig {
    const config_json_content = util.readEntireFileAlloc(directory, file_name, allocator) catch |err| {
        log.err("Problem reading config file ({!})!", .{err});
        return null;
    };
    defer allocator.free(config_json_content);

    const parse_result = std.json.parseFromSlice(GlobalConfig, allocator, config_json_content, .{
        .ignore_unknown_fields = true,
    });

    if (parse_result) |parsed| {
        defer parsed.deinit();
        return parsed.value;
    } else |err| {
        log.err("Problem parsing config file ({!})!", .{err});
    }
    return null;
}
