const std = @import("std");
const assert = std.debug.assert;
const log = std.log;

const c = @import("c.zig");

const util = @import("util.zig");

//TODO: GPA allocator: dupeZ/free - possible bug

// TODO: Audio assets - load/play
// TODO: Main loop:
//         + 1. read input;
//         + 2. update game;
//         - 3. render (could not be necessary?)
// TODO: Main game loop:
//         1. Pick battery by walking to it
//         2. Can't shoot while holding battery, when shoot - drops the battery.
//        +3. Shooting by holding IJKL.
//        >4. There's enemies. To simplify:
//              - semi-randomly walking to the player
//              - some can shoot
//         5. When all batteries collected - walk to the rocket, and go to next level.
// TODO: Juice:
//         1. Hop animation while walking.
//         2. Screen shake.
//         3. Audio.
//         4. Some fancy effects.
//         5. Blaster animation, use cooldown timer.
//         6. Trees, bushes and roads to have background.
// TODO: Gamepad support

const EntityManager = @import("entity.zig").EntityManager;
const GigaEntity = @import("entity.zig").GigaEntity;

const Json = struct {
    const Sprite = struct {
        image: []const u8,
        size: ?c.Vector2 = null,
        origin: c.Vector2,
    };
};

const Sprite = struct {
    texture: TextureManager.Handle,
    source: c.Rectangle,
    size: c.Vector2,
    origin: c.Vector2,
};

const TextureManager = struct {
    const ElementsCount = 16;

    textures: std.ArrayListUnmanaged(c.Texture2D),
    texture_file_names: std.StringHashMapUnmanaged(Handle),
    allocator: std.mem.Allocator,

    const Self = @This();

    const Handle = enum(u8) { _ };

    pub fn init(allocator: std.mem.Allocator) !TextureManager {
        var texture_file_names = std.StringHashMapUnmanaged(Handle){};
        try texture_file_names.ensureTotalCapacity(allocator, ElementsCount);

        return .{
            .textures = try std.ArrayListUnmanaged(c.Texture2D).initCapacity(allocator, ElementsCount),
            .texture_file_names = texture_file_names,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var name_iter = self.texture_file_names.keyIterator();
        while (name_iter.next()) |name| {
            self.allocator.free(name.*);
        }

        self.texture_file_names.deinit(self.allocator);
        self.textures.deinit(self.allocator);
    }

    pub fn fetchHandle(self: *Self, file_name: []const u8) !Handle {
        if (self.texture_file_names.get(file_name)) |found_handle| {
            errdefer comptime unreachable;
            return found_handle;
        }

        var i = file_name.len - 1;
        var ext: ?[]const u8 = null;
        while (i > 0) : (i -= 1) {
            if (file_name[i] == '.') {
                ext = file_name[i..];
                break;
            }
        }

        const ext_z = std.mem.zeroes([6]u8);

        log.debug("ext = {?s}", .{ext});
        assert(ext != null);

        if (ext) |actual_ext| {
            std.mem.copyForwards(u8, @constCast(ext_z[0..]), actual_ext);
        }

        const file_data = try util.readEntireFileAlloc("assets", file_name, self.allocator);
        defer self.allocator.free(file_data);

        const image = c.LoadImageFromMemory(&ext_z, file_data.ptr, @intCast(file_data.len));
        defer c.UnloadImage(image);
        log.debug("image = {any}.", .{image});

        const texture = c.LoadTextureFromImage(image);
        log.debug("texture = {any}.", .{texture});

        const result_handle: Handle = @enumFromInt(self.textures.items.len);

        self.textures.appendAssumeCapacity(texture);

        const file_name_dup = try self.allocator.dupe(u8, file_name);
        self.texture_file_names.putAssumeCapacity(file_name_dup, result_handle);

        return result_handle;
    }

    pub fn get(self: *const Self, handle: Handle) *c.Texture2D {
        const index: usize = @intFromEnum(handle);
        assert(index < self.textures.items.len);
        return &self.textures.items[index];
    }
};

const SpriteManager = struct {
    const Error = error{
        malformed_sprites_json,
    };

    texture_manager: *TextureManager,
    sprites: std.ArrayListUnmanaged(Sprite),
    sprite_names: std.StringHashMapUnmanaged(Handle),
    allocator: std.mem.Allocator,

    const Self = @This();

    const ElementsCount = 16;

    const Handle = enum(u8) { _ };

    pub fn init(
        texture_manager: *TextureManager,
        allocator: std.mem.Allocator,
    ) !Self {
        var sprite_names = std.StringHashMapUnmanaged(Handle){};
        try sprite_names.ensureTotalCapacity(allocator, ElementsCount);

        return .{
            .texture_manager = texture_manager,
            .sprite_names = sprite_names,
            .sprites = try std.ArrayListUnmanaged(Sprite).initCapacity(allocator, ElementsCount),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var name_it = self.sprite_names.keyIterator();
        while (name_it.next()) |name| {
            self.allocator.free(name.*);
        }
        self.sprite_names.deinit(self.allocator);
        self.sprites.deinit(self.allocator);
    }

    pub fn loadFromJson(self: *Self, json_data: []const u8) !void {
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json_data, .{});
        defer parsed.deinit();
        var created: usize = 0;
        var updated: usize = 0;
        switch (parsed.value) {
            .object => |sprites_json_value| {
                var iter = sprites_json_value.iterator();

                while (iter.next()) |entry| {
                    const sprite_name = entry.key_ptr.*;
                    const sprite_json_value = entry.value_ptr.*;

                    const parsed_sprite = try std.json.parseFromValue(Json.Sprite, self.allocator, sprite_json_value, .{});
                    defer parsed_sprite.deinit();
                    var sprite: *Sprite = undefined;
                    if (self.sprite_names.get(sprite_name)) |existing_sprite_handle| {
                        sprite = self.get(existing_sprite_handle);
                        updated += 1;
                    } else {
                        const new_sprite_handle: Handle = @enumFromInt(self.sprites.items.len);
                        self.sprites.appendAssumeCapacity(undefined);
                        const sprite_name_dup = try self.allocator.dupe(u8, sprite_name);
                        self.sprite_names.putAssumeCapacity(sprite_name_dup, new_sprite_handle);
                        sprite = self.get(new_sprite_handle);
                        created += 1;
                    }

                    sprite.texture = try self.texture_manager.fetchHandle(parsed_sprite.value.image);
                    const texture = self.texture_manager.get(sprite.texture);
                    log.debug("texture = {any}.", .{texture});
                    sprite.source = .{
                        .x = 0,
                        .y = 0,
                        .width = @floatFromInt(texture.width),
                        .height = @floatFromInt(texture.height),
                    };
                    if (parsed_sprite.value.size) |provided_size| {
                        sprite.size = provided_size;
                    } else {
                        sprite.size = .{
                            .x = @floatFromInt(texture.width),
                            .y = @floatFromInt(texture.height),
                        };
                    }
                    sprite.origin = parsed_sprite.value.origin;
                }
                log.debug("[Sprite Manager] created {d} and updated {d} sprites.", .{ created, updated });
            },
            else => return Error.malformed_sprites_json,
        }
    }

    pub fn get(self: *const Self, handle: Handle) *Sprite {
        const index: usize = @intFromEnum(handle);
        assert(index < self.sprites.items.len);
        return &self.sprites.items[index];
    }

    pub fn find(self: *const Self, name: []const u8) ?Handle {
        if (self.sprite_names.get(name)) |found_sprite_handle| {
            return found_sprite_handle;
        } else {
            return null;
        }
    }
};

const GPA = std.heap.GeneralPurposeAllocator(.{});

fn drawSprite(
    sprite: *const Sprite,
    position: c.Vector2,
    rotation: f32,
    tint: c.Color,
    texture_manager: *const TextureManager,
) void {
    const texture = texture_manager.get(sprite.texture).*;

    c.DrawTexturePro(
        texture,
        sprite.source,
        .{ .x = position.x, .y = position.y, .width = sprite.size.x, .height = sprite.size.y },
        .{ .x = sprite.origin.x * sprite.size.x, .y = sprite.origin.y * sprite.size.y },
        rotation,
        tint,
    );
}

const GameManager = struct {
    state: State = .Playing,
    respawn_time: f32 = 0,

    const Self = @This();

    const State = enum {
        Playing,
        RespawnScreen,
        ReadyToRespawn,
    };

    pub fn startRespawnCounter(self: *Self) void {
        self.respawn_time = 3;
        self.state = .RespawnScreen;
    }

    pub fn update(self: *Self, input: Input) void {
        if (self.state == .RespawnScreen) {
            self.respawn_time = @max(self.respawn_time - input.dt, 0);
            if (self.respawn_time <= 0) {
                self.state = .ReadyToRespawn;
            }
        }
    }
};

const Input = struct {
    dt: f32,
    up: bool = false,
    down: bool = false,
    left: bool = false,
    right: bool = false,
    shoot_up: bool = false,
    shoot_down: bool = false,
    shoot_left: bool = false,
    shoot_right: bool = false,
};

const EntityPhysicsConfig = struct {
    damping: f32,
    max_velocity: f32,
    mass: f32,
};

fn integratePhysics(
    position: *c.Vector2,
    acceleration: *c.Vector2,
    velocity: *c.Vector2,
    input: Input,
    config: EntityPhysicsConfig,
) !void {
    if (c.Vector2Length(velocity.*) > 0 and c.Vector2Length(acceleration.*) > 0) {
        // Decrease velocity if direction was changed
        const vel_norm = c.Vector2Normalize(velocity.*);
        const acc_norm = c.Vector2Normalize(acceleration.*);
        const dot_product = c.Vector2DotProduct(vel_norm, acc_norm);
        if (dot_product < 0) {
            velocity.* = c.Vector2Subtract(velocity.*, c.Vector2Scale(velocity.*, (1 - config.damping) * @abs(dot_product) * input.dt / config.mass));
        }
    }
    if (BuggyPhysicsIntegration) {
        const vt = c.Vector2Scale(velocity.*, input.dt);
        const at = c.Vector2Scale(acceleration.*, input.dt * input.dt * 0.5);
        velocity.* = c.Vector2Add(velocity.*, c.Vector2Add(vt, at));
    } else {
        velocity.* = c.Vector2Add(velocity.*, c.Vector2Scale(acceleration.*, input.dt));
    }

    if (c.Vector2Length(acceleration.*) == 0) {
        velocity.* = c.Vector2Scale(velocity.*, config.damping);
    }

    velocity.* = c.Vector2ClampValue(velocity.*, 0, config.max_velocity);

    position.* = c.Vector2Add(position.*, c.Vector2Scale(velocity.*, input.dt));
}

const Config = struct {
    camera_lerp_value: f32 = 0.05,
    player_acc_magnitude: f32 = 200,
    general_radius: f32 = 8,
    general_center_from_bottom: f32 = 8,
    general_damage: i8 = 30,
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
    projectile_radius: f32 = 2,
    enemy_loiter_time: f32 = 3,
    enemy_aggression_distance: f32 = 200,
    enemy_damping: f32 = 0.9,
    enemy_acc_magnitude: f32 = 100,
    enemy_max_velocity: f32 = 90,
    enemy_mass: f32 = 300,
    enemy_pursuit_dispersal: f32 = 50,
    damage_inertia_factor: f32 = 0.5,
    iframes: f32 = 2,
    damage_animation_speed: f32 = 10,

    const Self = @This();

    pub fn load(directory: []const u8, file_name: []const u8, allocator: std.mem.Allocator) ?Self {
        const config_json_content = util.readEntireFileAlloc(directory, file_name, allocator) catch |err| {
            log.err("Problem reading config file ({!})!", .{err});
            return null;
        };
        defer allocator.free(config_json_content);

        const parse_result = std.json.parseFromSlice(Self, allocator, config_json_content, .{
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
};

const BuggyPhysicsIntegration = false;

pub fn determineDirection(up: bool, down: bool, left: bool, right: bool) c.Vector2 {
    var result = c.Vector2{};
    if (left) result.x = -1;
    if (right) result.x = 1;
    if (up) result.y = -1;
    if (down) result.y = 1;
    return c.Vector2Normalize(result);
}

fn update(
    game_manager: *GameManager,
    em: *EntityManager,
    input: Input,
    config: Config,
    frame_messages: *std.ArrayList([]const u8),
    frame_allocator: std.mem.Allocator,
    rng: *std.Random,
    player_position: c.Vector2,
) !void {
    var i: usize = 0;
    while (i < em.entities.len) : (i += 1) {
        const flags = em.entities.items(.flags);
        const position = em.entities.items(.position);
        const acceleration = em.entities.items(.acceleration);
        const velocity = em.entities.items(.velocity);
        const shoot_info = em.entities.items(.shoot_info);
        const ttl = em.entities.items(.ttl);
        const enemy_behavior = em.entities.items(.enemy_behavior);
        const damage_animation = em.entities.items(.damage_animation);
        const iframes = em.entities.items(.iframes);

        //TODO: Proper units: e.g. 16px - 1 meter or something.

        //TODO: Start extracting to functions.

        if (flags[i].class == .Player) {
            acceleration[i] = determineDirection(input.up, input.down, input.left, input.right);

            acceleration[i] = c.Vector2Scale(c.Vector2Normalize(acceleration[i]), config.player_acc_magnitude);
            frame_messages.appendAssumeCapacity(try std.fmt.allocPrintZ(
                frame_allocator,
                "player.acceleration = {d:.4}, {d:.4}.",
                .{ acceleration[i].x, acceleration[i].y },
            ));
            frame_messages.appendAssumeCapacity(try std.fmt.allocPrintZ(
                frame_allocator,
                "player.velocity = {d:.4}, {d:.4}.",
                .{ velocity[i].x, velocity[i].y },
            ));
        } else if (flags[i].class == .Projectile) {
            ttl[i] = @max(ttl[i] - input.dt, 0);
            if (ttl[i] == 0) {
                flags[i].alive = false;
            }
        } else if (flags[i].class == .Supostat) {
            if (c.Vector2Distance(player_position, position[i]) <= config.enemy_aggression_distance) {
                enemy_behavior[i].mode = .Pursuit;
            } else {
                enemy_behavior[i].mode = .Loiter;
            }

            switch (enemy_behavior[i].mode) {
                .Loiter => {
                    enemy_behavior[i].time_to_next -= input.dt;

                    if (enemy_behavior[i].time_to_next <= 0) {
                        enemy_behavior[i].time_to_next = rng.float(f32) * config.enemy_loiter_time;
                        enemy_behavior[i].commit_to_direction.x = ((rng.floatExp(f32) * 2) - 1);
                        enemy_behavior[i].commit_to_direction.y = ((rng.floatExp(f32) * 2) - 1);
                    }
                },
                .Pursuit => {
                    enemy_behavior[i].commit_to_direction = .{};

                    const actual_target_position = c.Vector2{
                        .x = player_position.x + (rng.floatExp(f32) * config.enemy_pursuit_dispersal) - config.enemy_pursuit_dispersal * 0.5,
                        .y = player_position.y + (rng.floatExp(f32) * config.enemy_pursuit_dispersal) - config.enemy_pursuit_dispersal * 0.5,
                    };

                    if (actual_target_position.y > position[i].y) {
                        enemy_behavior[i].commit_to_direction.y = 1;
                    } else if (actual_target_position.y < position[i].y) {
                        enemy_behavior[i].commit_to_direction.y = -1;
                    }
                    if (actual_target_position.x > position[i].x) {
                        enemy_behavior[i].commit_to_direction.x = 1;
                    } else if (actual_target_position.x < position[i].x) {
                        enemy_behavior[i].commit_to_direction.x = -1;
                    }
                },
                .Avoid => {
                    enemy_behavior[i].commit_to_direction = .{};
                    if (player_position.y > position[i].y) {
                        enemy_behavior[i].commit_to_direction.y = -1;
                    } else if (player_position.y < position[i].y) {
                        enemy_behavior[i].commit_to_direction.y = 1;
                    }
                    if (player_position.x > position[i].x) {
                        enemy_behavior[i].commit_to_direction.x = -1;
                    } else if (player_position.x < position[i].x) {
                        enemy_behavior[i].commit_to_direction.x = 1;
                    }
                },
            }

            enemy_behavior[i].commit_to_direction = c.Vector2Normalize(enemy_behavior[i].commit_to_direction);

            //TODO: Enemy stuff
            acceleration[i] = enemy_behavior[i].commit_to_direction;
            //TODO: Proper config
            acceleration[i] = c.Vector2Scale(c.Vector2Normalize(acceleration[i]), config.enemy_acc_magnitude);
        }

        if (flags[i].moving) {
            const initial_position = position[i];
            const physics_config: EntityPhysicsConfig = switch (flags[i].class) {
                .Player => .{
                    .damping = config.player_damping,
                    .max_velocity = config.player_max_velocity,
                    .mass = config.player_mass,
                },
                .Projectile => .{
                    .damping = config.player_projectile_damping,
                    .max_velocity = config.player_projectile_max_velocity,
                    .mass = 0,
                },
                .Supostat => .{
                    .damping = config.enemy_damping,
                    .max_velocity = config.enemy_max_velocity,
                    .mass = config.enemy_mass,
                },
                else => .{
                    .damping = 0,
                    .max_velocity = 0,
                    .mass = 0,
                },
            };

            try integratePhysics(&position[i], &acceleration[i], &velocity[i], input, physics_config);

            if (flags[i].class == .Player) {
                const frame_distance = c.Vector2Distance(initial_position, position[i]);
                frame_messages.appendAssumeCapacity(try std.fmt.allocPrintZ(
                    frame_allocator,
                    "player.frame_distance = {d:.4}.",
                    .{frame_distance},
                ));
            }
        }

        if (flags[i].class == .Player) {
            if (shoot_info[i].cooldown > 0) {
                shoot_info[i].cooldown = std.math.clamp(shoot_info[i].cooldown - input.dt, 0, config.player_shoot_cooldown);
            }

            const is_shooting = input.shoot_up or input.shoot_down or input.shoot_left or input.shoot_right;
            if (is_shooting and shoot_info[i].cooldown <= 0) {
                const shoot_direction = determineDirection(
                    input.shoot_up,
                    input.shoot_down,
                    input.shoot_left,
                    input.shoot_right,
                );

                const shoot_start_position = c.Vector2Add(
                    c.Vector2{ .x = 0, .y = -config.player_shoot_hands_height },
                    c.Vector2Add(
                        position[i],
                        c.Vector2Scale(shoot_direction, config.player_shoot_start_distance),
                    ),
                );

                _ = em.createEntity(GigaEntity.projectile(
                    shoot_start_position,
                    c.Vector2Scale(shoot_direction, config.player_projectile_acceleration_magnitude),
                    config.player_projectile_ttl,
                ));

                shoot_info[i].cooldown = config.player_shoot_cooldown;
            }
            frame_messages.appendAssumeCapacity(try std.fmt.allocPrintZ(
                frame_allocator,
                "player.shoot_cooldown = {d:.4}.",
                .{shoot_info[i].cooldown},
            ));
        }

        if (damage_animation[i] > 0) {
            damage_animation[i] = @max(damage_animation[i] - input.dt * config.damage_animation_speed, 0);
        }

        if (iframes[i] > 0) {
            iframes[i] = @max(iframes[i] - input.dt, 0);
        }

        if (flags[i].class == .Player) {
            frame_messages.appendAssumeCapacity(
                try std.fmt.allocPrintZ(frame_allocator, "player.iframes = {d:.4}.", .{iframes[i]}),
            );
        }
    }

    i = 0;
    while (i < em.entities.len) : (i += 1) {
        const flags = em.entities.items(.flags);
        const position = em.entities.items(.position);
        const velocity = em.entities.items(.velocity);
        const health = em.entities.items(.health);
        const damage_animation = em.entities.items(.damage_animation);
        const iframes = em.entities.items(.iframes);
        var j: usize = 0;
        while (j < em.entities.len) : (j += 1) {
            if (i != j and flags[i].alive and flags[i].collideable) {
                if (flags[i].class == .Projectile and flags[j].class == .Supostat) {
                    const real_position = c.Vector2Add(position[j], .{ .y = -config.general_center_from_bottom });
                    if (c.Vector2Distance(position[i], real_position) <= config.general_radius + config.projectile_radius) {
                        health[j] -= config.general_damage;
                        flags[i].alive = false;
                        damage_animation[j] = 1;
                        velocity[j] = c.Vector2Add(velocity[j], c.Vector2Scale(velocity[i], config.damage_inertia_factor));

                        //TODO: Some particles

                        if (health[j] <= 0) {
                            flags[j].alive = false;

                            //TODO: Death animation/sound
                        }
                    }
                } else if (flags[i].class == .Supostat and flags[j].class == .Player) {
                    const real_position_s = c.Vector2Add(position[i], .{ .y = -config.general_center_from_bottom });
                    const real_position_p = c.Vector2Add(position[j], .{ .y = -config.general_center_from_bottom });

                    if (c.Vector2Distance(real_position_s, real_position_p) <= config.general_radius * 2) {
                        //TODO: config.damage_inertia_factor * 0.2 - to config
                        velocity[j] = c.Vector2Add(velocity[j], c.Vector2Scale(velocity[i], config.damage_inertia_factor * 0.2));
                        if (iframes[j] <= 0) {
                            health[j] -= config.general_damage;
                            damage_animation[j] = 1;
                            iframes[j] = config.iframes;

                            //TODO: Some particles

                            if (health[j] <= 0) {
                                flags[j].alive = false;
                                game_manager.startRespawnCounter();
                                //TODO: Death animation/sound
                            }
                        }
                    }
                }
            }
        }
    }
}

fn render(em: *EntityManager, sm: *SpriteManager, tm: *TextureManager, input: Input, config: Config) void {
    inline for (@typeInfo(GigaEntity.Layer).@"enum".fields) |layer_field| {
        const current_layer: GigaEntity.Layer = @enumFromInt(layer_field.value);
        var i: usize = 0;
        while (i < em.entities.len) : (i += 1) {
            const flags = em.entities.items(.flags);
            const position = em.entities.items(.position);
            const tint = em.entities.items(.tint);
            const damage_animation = em.entities.items(.damage_animation);
            const layer = em.entities.items(.layer);
            if (flags[i].visual and current_layer == layer[i]) {
                if (flags[i].class == .Player) {
                    const player_sprite = sm.get(player_sprite_handle);
                    {
                        const final_tint = c.ColorLerp(tint[i], c.WHITE, damage_animation[i]);
                        drawSprite(player_sprite, position[i], 0, final_tint, tm);
                    }
                    const blaster_sprite = sm.get(blaster_sprite_handle);

                    const is_shooting = input.shoot_up or input.shoot_down or input.shoot_left or input.shoot_right;
                    if (is_shooting) {
                        const shoot_direction = determineDirection(
                            input.shoot_up,
                            input.shoot_down,
                            input.shoot_left,
                            input.shoot_right,
                        );

                        const blaster_position = c.Vector2Add(
                            c.Vector2{ .x = 0, .y = -config.player_shoot_hands_height },
                            c.Vector2Add(
                                position[i],
                                c.Vector2Scale(shoot_direction, config.player_blaster_distance),
                            ),
                        );

                        // Can't figure out how to get direction vector's angle
                        // and to not waste time, here's the solution.

                        const Angles = [_]f32{
                            0 * 45, //       Right
                            1 * 45, // Down  Right
                            2 * 45, // Down
                            3 * 45, // Down  Left
                            4 * 45, //       Left
                            5 * 45, // Up    Left
                            6 * 45, // Up
                            7 * 45, // Up    Right
                        };

                        var angle_index: usize = 0;

                        if (input.shoot_up and input.shoot_right) {
                            angle_index = 7;
                        } else if (input.shoot_up and input.shoot_left) {
                            angle_index = 5;
                        } else if (input.shoot_down and input.shoot_right) {
                            angle_index = 1;
                        } else if (input.shoot_down and input.shoot_left) {
                            angle_index = 3;
                        } else if (input.shoot_up) {
                            angle_index = 6;
                        } else if (input.shoot_down) {
                            angle_index = 2;
                        } else if (input.shoot_left) {
                            angle_index = 4;
                        } else if (input.shoot_right) {
                            angle_index = 0;
                        }

                        const angle = Angles[angle_index];

                        // frame_messages.appendAssumeCapacity(try std.fmt.allocPrintZ(
                        //     frame_allocator,
                        //     "player.blaster_angle = {d:.4}.",
                        //     .{angle},
                        // ));
                        {
                            const final_tint = c.ColorLerp(c.DARKGREEN, c.WHITE, damage_animation[i]);
                            drawSprite(blaster_sprite, blaster_position, angle, final_tint, tm);
                        }
                    }
                } else if (flags[i].class == .Battery) {
                    const battery_sprite = sm.get(battery_sprite_handle);
                    drawSprite(battery_sprite, position[i], 0, tint[i], tm);
                } else if (flags[i].class == .Projectile) {
                    const projectile_sprite = sm.get(projectile_sprite_handle);
                    drawSprite(projectile_sprite, position[i], 0, tint[i], tm);
                } else if (flags[i].class == .Supostat) {
                    const final_tint = c.ColorLerp(tint[i], c.WHITE, damage_animation[i]);
                    const monster_sprite = sm.get(monster_sprite_handle);
                    drawSprite(monster_sprite, position[i], 0, final_tint, tm);
                }
            }
        }
    }
}

fn cleanupEntities(em: *EntityManager) void {
    var i: usize = 0;
    while (i < em.entities.len) {
        const handle = em.entities.items(.handle);
        const flags = em.entities.items(.flags);
        if (!flags[i].alive) {
            em.removeEntity(handle[i]);
        } else {
            i += 1;
        }
    }
}

var player_sprite_handle: SpriteManager.Handle = undefined;
var battery_sprite_handle: SpriteManager.Handle = undefined;
var projectile_sprite_handle: SpriteManager.Handle = undefined;
var blaster_sprite_handle: SpriteManager.Handle = undefined;
var monster_sprite_handle: SpriteManager.Handle = undefined;

pub fn main() !void {
    var gpa = GPA{};

    defer if (gpa.deinit() == .leak) {
        log.err("Oh no! Memory leaks happened!", .{});
    };

    var config: Config = .{};
    if (Config.load(".", "config.json", gpa.allocator())) |loaded_config| {
        config = loaded_config;
    }

    c.InitWindow(1280, 720, "Unnamed Game Jam Entry");
    c.SetTargetFPS(60);

    var config_watcher = try util.FileWatcher.init(".", "config.json", 0.5);

    var texture_manager = try TextureManager.init(gpa.allocator());
    defer texture_manager.deinit();
    var sprite_manager = try SpriteManager.init(&texture_manager, gpa.allocator());
    defer sprite_manager.deinit();
    {
        const allocator = gpa.allocator();
        const sprites_json_content = try util.readEntireFileAlloc(".", "sprites.json", allocator);
        defer allocator.free(sprites_json_content);
        try sprite_manager.loadFromJson(sprites_json_content);
    }

    var entity_manager = try EntityManager.init(gpa.allocator());
    defer entity_manager.deinit();

    player_sprite_handle = sprite_manager.find("main-guy").?;
    battery_sprite_handle = sprite_manager.find("battery").?;
    projectile_sprite_handle = sprite_manager.find("projectile").?;
    blaster_sprite_handle = sprite_manager.find("blaster").?;
    monster_sprite_handle = sprite_manager.find("enemy0").?;

    var player_handle = entity_manager.createEntity(GigaEntity.player(.{ .x = 0, .y = 0 }));

    var prng = std.Random.DefaultPrng.init(0x6969);
    var rng = prng.random();

    var entities_to_spawn: i32 = 100;
    while (entities_to_spawn >= 0) : (entities_to_spawn -= 1) {
        const Distribution = 500;
        if (rng.boolean() and rng.boolean()) {
            _ = entity_manager.createEntity(GigaEntity.battery(
                .{
                    .x = rng.floatNorm(f32) * Distribution - Distribution * 0.5,
                    .y = rng.floatNorm(f32) * Distribution - Distribution * 0.5,
                },
            ));
        } else {
            _ = entity_manager.createEntity(GigaEntity.supostat(
                .{
                    .x = rng.floatNorm(f32) * Distribution - Distribution * 0.5,
                    .y = rng.floatNorm(f32) * Distribution - Distribution * 0.5,
                },
            ));
        }
    }

    const screen_width: f32 = @floatFromInt(c.GetScreenWidth());
    const screen_height: f32 = @floatFromInt(c.GetScreenHeight());

    var camera = c.Camera2D{
        .offset = .{ .x = screen_width * 0.5, .y = screen_height * 0.5 },
        .rotation = 0,
        .target = .{ .x = 0, .y = 0 },
        .zoom = 3,
    };

    var frame_messages = try std.ArrayList([]const u8).initCapacity(gpa.allocator(), 1024);
    defer frame_messages.deinit();
    const frame_memory = try gpa.allocator().alloc(u8, 1 * 1024 * 1024);
    defer gpa.allocator().free(frame_memory);

    var frame_fba = std.heap.FixedBufferAllocator.init(frame_memory);
    var frame_arena = std.heap.ArenaAllocator.init(frame_fba.allocator());
    const frame_allocator = frame_arena.allocator();

    var game_manager = GameManager{};

    while (!c.WindowShouldClose()) {
        frame_messages.clearRetainingCapacity();
        _ = frame_arena.reset(.retain_capacity);

        const input = Input{
            .dt = c.GetFrameTime(),
            .up = c.IsKeyDown(c.KEY_W),
            .down = c.IsKeyDown(c.KEY_S),
            .left = c.IsKeyDown(c.KEY_A),
            .right = c.IsKeyDown(c.KEY_D),
            .shoot_up = c.IsKeyDown(c.KEY_I) or c.IsKeyDown(c.KEY_UP),
            .shoot_down = c.IsKeyDown(c.KEY_K) or c.IsKeyDown(c.KEY_DOWN),
            .shoot_left = c.IsKeyDown(c.KEY_J) or c.IsKeyDown(c.KEY_LEFT),
            .shoot_right = c.IsKeyDown(c.KEY_L) or c.IsKeyDown(c.KEY_RIGHT),
        };

        if (config_watcher.wasModified(input.dt)) {
            log.debug("Config was changed, reloading...", .{});
            if (Config.load(".", "config.json", frame_allocator)) |loaded_config| {
                config = loaded_config;
            } else {
                log.err("Config was not updated!", .{});
            }
        }

        var player_position_for_pursuit = c.Vector2{};
        if (entity_manager.entityField(player_handle, .position)) |player_position| {
            camera.target = c.Vector2Lerp(camera.target, player_position.*, config.camera_lerp_value);
            player_position_for_pursuit = player_position.*;
        }

        c.BeginDrawing();
        defer c.EndDrawing();

        c.BeginMode2D(camera);

        c.ClearBackground(c.BLACK);

        game_manager.update(input);

        try update(
            &game_manager,
            &entity_manager,
            input,
            config,
            &frame_messages,
            frame_allocator,
            &rng,
            player_position_for_pursuit,
        );
        cleanupEntities(&entity_manager);
        render(&entity_manager, &sprite_manager, &texture_manager, input, config);

        frame_messages.appendAssumeCapacity(try std.fmt.allocPrintZ(
            frame_allocator,
            "entities.count = {d}.",
            .{entity_manager.entities.len},
        ));

        c.EndMode2D();

        if (game_manager.state == .RespawnScreen) {
            //TODO: Animate this screen
            const font_size = 40;
            {
                const text: [*c]const u8 = "Dudes overwhelmed you!";

                const width: f32 = @floatFromInt(c.MeasureText(text, font_size));
                c.DrawText(text, @intFromFloat((screen_width - width) / 2), @intFromFloat(screen_height / 2), font_size, c.RAYWHITE);
            }
            {
                const text = try std.fmt.allocPrintZ(
                    frame_allocator,
                    "Respawn in = {d:.0}...",
                    .{game_manager.respawn_time},
                );
                const width: f32 = @floatFromInt(c.MeasureText(text, font_size));
                c.DrawText(text.ptr, @intFromFloat((screen_width - width) / 2), @intFromFloat(screen_height / 2 + font_size + 8), font_size, c.RAYWHITE);
            }
        }

        c.DrawFPS(2, 2);

        for (frame_messages.items, 0..) |frame_message, i| {
            const index: c_int = @intCast(i);
            c.DrawText(frame_message.ptr, 2, 20 * (index + 1), 18, c.RAYWHITE);
        }

        if (game_manager.state == .ReadyToRespawn) {
            log.debug("Spawning new player", .{});
            player_handle = entity_manager.createEntity(GigaEntity.player(.{ .x = 0, .y = 0 }));
            game_manager.state = .Playing;
        }
    }
}

test "entity manager stuff" {
    const allocator = std.testing.allocator;

    var em = try EntityManager.init(allocator);
    defer em.deinit();

    const DatasetSize = 1000;

    var entity_handles = try std.ArrayList(EntityManager.Handle).initCapacity(allocator, DatasetSize);
    defer entity_handles.deinit();

    var prng = std.Random.DefaultPrng.init(0x69);
    var rng = prng.random();
    var entities_count: usize = DatasetSize;
    while (entities_count > 0) : (entities_count -= 1) {
        const handle = em.createEntity(GigaEntity.player(
            .{ .x = rng.float(f32), .y = rng.float(f32) },
            @enumFromInt(rng.int(u16)),
        ));
        entity_handles.appendAssumeCapacity(handle);
    }

    rng.shuffle(EntityManager.Handle, entity_handles.items);

    for (entity_handles.items) |entity_handle| {
        em.removeEntity(entity_handle);
    }

    try std.testing.expectEqual(0, em.entity_index.count());
    try std.testing.expectEqual(0, em.entities.len);
}
