const std = @import("std");
const assert = std.debug.assert;
const log = std.log;

const c = @import("c.zig");

const util = @import("util.zig");

const GlobalConfig = @import("GlobalConfig.zig");

//TODO: GPA allocator: dupeZ/free - possible bug

// TODO: Audio assets - load/play
// TODO: Main game loop:
//         1. Shoot dudes.
//         2. Don't let the dudes overwhelm you.
//        >3. Pick up batteries to "charge" you.
//            TODO: Make pickable batteries and charge meter that changes how awesome you can shoot.
//         4. When charge is low - shoot less, high - shoot more, maybe even with spread shoot.
//         5. Try to have fun.
// TODO: GUI - health, batteries, also change damage system to number of hits.
// TODO: Spawn enemies around you not in random places. Keep count to decide if more needs to be spawn.
// TODO: Juice:
//        +1. Hop animation while walking.
//         2. Screen shake.
//        +3. Audio.
//         4. Some fancy effects.
//         5. Blaster animation, use cooldown timer.
//         6. Trees, bushes and roads to have background.
// TODO: Gamepad support

const EntityManager = @import("entity.zig").EntityManager;
const GigaEntity = @import("entity.zig").GigaEntity;

const SpriteManager = @import("SpriteManager.zig");
const Sprite = SpriteManager.Sprite;
const SpriteHandle = SpriteManager.SpriteHandle;

const AudioManager = @import("AudioManager.zig");

const GPA = std.heap.GeneralPurposeAllocator(.{});

fn drawSprite(
    sprite: *const Sprite,
    position: c.Vector2,
    rotation: f32,
    tint: c.Color,
) void {
    c.DrawTexturePro(
        sprite.texture,
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
    config: GlobalConfig,
    frame_messages: *std.ArrayList([]const u8),
    frame_allocator: std.mem.Allocator,
    rng: std.Random,
    player_position: ?c.Vector2,
    audio_manager: AudioManager,
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
        const hop_value = em.entities.items(.hop_value);
        const above_ground_value = em.entities.items(.above_ground_value);

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
            enemy_behavior[i].mode = .Loiter;
            var player_position_for_pursuit: c.Vector2 = .{};
            if (player_position) |provided_player_position| {
                if (c.Vector2Distance(provided_player_position, position[i]) <= config.enemy_aggression_distance) {
                    enemy_behavior[i].mode = .Pursuit;
                    player_position_for_pursuit = provided_player_position;
                }
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
                        .x = player_position_for_pursuit.x + (rng.floatExp(f32) * config.enemy_pursuit_dispersal) - config.enemy_pursuit_dispersal * 0.5,
                        .y = player_position_for_pursuit.y + (rng.floatExp(f32) * config.enemy_pursuit_dispersal) - config.enemy_pursuit_dispersal * 0.5,
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
                    if (player_position_for_pursuit.y > position[i].y) {
                        enemy_behavior[i].commit_to_direction.y = -1;
                    } else if (player_position_for_pursuit.y < position[i].y) {
                        enemy_behavior[i].commit_to_direction.y = 1;
                    }
                    if (player_position_for_pursuit.x > position[i].x) {
                        enemy_behavior[i].commit_to_direction.x = -1;
                    } else if (player_position_for_pursuit.x < position[i].x) {
                        enemy_behavior[i].commit_to_direction.x = 1;
                    }
                },
            }

            enemy_behavior[i].commit_to_direction = c.Vector2Normalize(enemy_behavior[i].commit_to_direction);
            acceleration[i] = enemy_behavior[i].commit_to_direction;
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

            const hop_max_angle: f32 = std.math.degreesToRadians(180);

            if (flags[i].class == .Player or flags[i].class == .Supostat) {
                position[i] = c.Vector2Clamp(
                    position[i],
                    .{ .x = -ArenaWidth / 2, .y = -ArenaHeight / 2 },
                    .{ .x = ArenaWidth / 2, .y = ArenaHeight / 2 },
                );

                const frame_distance = c.Vector2Distance(initial_position, position[i]);

                const hop_distance: f32 = if (flags[i].class == .Player) config.player_hop_distance else config.enemy_hop_distance;
                const hop_amp: f32 = if (flags[i].class == .Player) config.player_hop_amp else config.enemy_hop_amp;

                hop_value[i] += frame_distance;

                if (hop_value[i] > hop_distance) {
                    hop_value[i] -= hop_distance;
                    if (flags[i].class == .Player) {
                        audio_manager.play(.PlayerStep);
                    }
                }

                const angle_value = (hop_value[i] * hop_max_angle) / hop_distance;

                above_ground_value[i] = @sin(angle_value) * hop_amp;
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
                audio_manager.play(.Pew);

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
        const above_ground_value = em.entities.items(.above_ground_value);
        var j: usize = 0;
        while (j < em.entities.len) : (j += 1) {
            if (i != j and flags[i].alive and flags[i].collideable) {
                if (flags[i].class == .Projectile and flags[j].class == .Supostat) {
                    const real_position_b = c.Vector2Add(c.Vector2Add(position[j], .{ .y = -above_ground_value[j] }), .{ .y = -config.general_center_from_bottom });
                    if (DebugMode) {
                        c.DrawCircleV(real_position_b, config.general_radius, c.GOLD);
                        c.DrawCircleV(position[i], config.projectile_radius, c.YELLOW);
                    }
                    if (c.Vector2Distance(position[i], real_position_b) <= config.general_radius + config.projectile_radius) {
                        audio_manager.playOneOf(rng, &.{ .Damage0, .Damage1, .Damage2, .Damage3, .Damage4 });
                        health[j] -= 1;
                        flags[i].alive = false;
                        damage_animation[j] = 1;
                        velocity[j] = c.Vector2Add(velocity[j], c.Vector2Scale(velocity[i], config.damage_inertia_factor));

                        //TODO: Some particles

                        if (health[j] <= 0) {
                            flags[j].alive = false;
                            audio_manager.playOneOf(rng, &.{ .EnemyFell0, .EnemyFell1, .EnemyFell2 });
                            //TODO: Death animation
                        }
                    }
                } else if (flags[i].class == .Supostat and flags[j].class == .Player) {
                    const real_position_s = c.Vector2Add(c.Vector2Add(position[i], .{ .y = -above_ground_value[i] }), .{ .y = -config.general_center_from_bottom });
                    const real_position_p = c.Vector2Add(c.Vector2Add(position[j], .{ .y = -above_ground_value[j] }), .{ .y = -config.general_center_from_bottom });

                    if (c.Vector2Distance(real_position_s, real_position_p) <= config.general_radius * 2) {
                        //TODO: config.damage_inertia_factor * 0.2 - to config
                        velocity[j] = c.Vector2Add(velocity[j], c.Vector2Scale(velocity[i], config.damage_inertia_factor * 0.2));
                        if (iframes[j] <= 0) {
                            audio_manager.playOneOf(rng, &.{ .DamageFromSupostat0, .DamageFromSupostat1, .DamageFromSupostat2, .DamageFromSupostat3 });
                            health[j] -= 1;
                            damage_animation[j] = 1;
                            iframes[j] = config.iframes;

                            //TODO: Some particles

                            if (health[j] <= 0) {
                                flags[j].alive = false;
                                audio_manager.play(.PlayerFell);
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

const ArenaWidth = 256 * 16;
const ArenaHeight = 256 * 16;

fn render(em: *EntityManager, sm: *SpriteManager, input: Input, config: GlobalConfig) void {
    c.DrawRectangle(-ArenaWidth / 2, -ArenaHeight / 2, 1, ArenaHeight, c.GRAY);
    c.DrawRectangle(ArenaWidth / 2, -ArenaHeight / 2, 1, ArenaHeight, c.GRAY);

    c.DrawRectangle(-ArenaWidth / 2, -ArenaHeight / 2, ArenaWidth, 1, c.GRAY);
    c.DrawRectangle(-ArenaWidth / 2, ArenaHeight / 2, ArenaWidth + 1, 1, c.GRAY);

    {
        var prng = std.Random.DefaultPrng.init(0x69);
        var rng = prng.random();

        var x: f32 = -ArenaWidth / 2;
        while (x < ArenaWidth / 2) : (x += 16) {
            var y: f32 = -ArenaWidth / 2;
            while (y < ArenaWidth / 2) : (y += 16) {
                if (rng.int(u16) < 2000) {
                    const DecorSprites = [_]SpriteHandle{ .Decor0, .Decor1 };
                    const decor_index = rng.uintLessThan(usize, DecorSprites.len);
                    drawSprite(
                        sm.get(DecorSprites[decor_index]),
                        .{ .x = x + rng.floatExp(f32) * 8 - 4, .y = y + rng.floatExp(f32) * 8 - 4 },
                        0,
                        c.GREEN,
                    );
                }
            }
        }

        //TODO: Draw trees/bushes and stuff
    }

    inline for (@typeInfo(GigaEntity.Layer).@"enum".fields) |layer_field| {
        const current_layer: GigaEntity.Layer = @enumFromInt(layer_field.value);
        var i: usize = 0;
        while (i < em.entities.len) : (i += 1) {
            const flags = em.entities.items(.flags);
            const position = em.entities.items(.position);
            const tint = em.entities.items(.tint);
            const damage_animation = em.entities.items(.damage_animation);
            const layer = em.entities.items(.layer);
            const above_ground_value = em.entities.items(.above_ground_value);
            if (flags[i].visual and current_layer == layer[i]) {
                if (flags[i].class == .Player) {
                    const final_position = c.Vector2Add(position[i], .{ .y = -above_ground_value[i] });
                    const player_sprite = sm.get(.Player);
                    {
                        const final_tint = c.ColorLerp(tint[i], c.WHITE, damage_animation[i]);
                        drawSprite(player_sprite, final_position, 0, final_tint);
                    }
                    const blaster_sprite = sm.get(.Blaster);

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
                                final_position,
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
                            drawSprite(blaster_sprite, blaster_position, angle, final_tint);
                        }
                    }
                } else if (flags[i].class == .Battery) {
                    const battery_sprite = sm.get(.Battery);
                    drawSprite(battery_sprite, position[i], 0, tint[i]);
                } else if (flags[i].class == .Projectile) {
                    const projectile_sprite = sm.get(.Projectile);
                    drawSprite(projectile_sprite, position[i], 0, tint[i]);
                } else if (flags[i].class == .Supostat) {
                    const final_position = c.Vector2Add(position[i], .{ .y = -above_ground_value[i] });
                    const final_tint = c.ColorLerp(tint[i], c.WHITE, damage_animation[i]);
                    const monster_sprite = sm.get(.Enemy0);
                    drawSprite(monster_sprite, final_position, 0, final_tint);
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

const DebugMode = false;

pub fn main() !void {
    var gpa = GPA{};

    defer if (gpa.deinit() == .leak) {
        log.err("Oh no! Memory leaks happened!", .{});
    };

    var config: GlobalConfig = .{};
    if (GlobalConfig.load(".", "config.json", gpa.allocator())) |loaded_config| {
        config = loaded_config;
    }

    c.SetConfigFlags(c.FLAG_WINDOW_RESIZABLE);
    c.InitWindow(1280, 720, "The Discharge of Captain Volt");

    defer c.CloseWindow();
    c.InitAudioDevice();
    defer c.CloseAudioDevice();

    c.SetTargetFPS(60);

    var config_watcher = try util.FileWatcher.init(".", "config.json", 0.5);

    const audio_manager = AudioManager.init();
    var sprite_manager = SpriteManager.init();

    var entity_manager = try EntityManager.init(gpa.allocator());
    defer entity_manager.deinit();

    var player_handle = entity_manager.createEntity(GigaEntity.player(.{ .x = 0, .y = 0 }));
    audio_manager.play(.Respawn);

    var prng = std.Random.DefaultPrng.init(0x6969);
    var rng = prng.random();
    if (true) {
        var entities_to_spawn: i32 = 100;
        while (entities_to_spawn >= 0) : (entities_to_spawn -= 1) {
            const Distribution = 200;
            if (rng.boolean() and rng.boolean()) {
                _ = entity_manager.createEntity(GigaEntity.battery(
                    .{
                        .x = rng.floatNorm(f32) * Distribution - Distribution * 0.5,
                        .y = rng.floatNorm(f32) * Distribution - Distribution * 0.5,
                    },
                ));
            } else {
                _ = entity_manager.createEntity(GigaEntity.supostat(.{
                    .x = rng.floatNorm(f32) * Distribution - Distribution * 0.5,
                    .y = rng.floatNorm(f32) * Distribution - Distribution * 0.5,
                }, rng));
            }
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

    c.SetMasterVolume(0.05);

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
            if (GlobalConfig.load(".", "config.json", frame_allocator)) |loaded_config| {
                //TODO: Print updated values
                config = loaded_config;
            } else {
                log.err("Config was not updated!", .{});
            }
        }

        var player_position_for_pursuit: ?c.Vector2 = null;
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
            rng,
            player_position_for_pursuit,
            audio_manager,
        );
        cleanupEntities(&entity_manager);
        render(&entity_manager, &sprite_manager, input, config);

        frame_messages.appendAssumeCapacity(try std.fmt.allocPrintZ(
            frame_allocator,
            "entities.count = {d}.",
            .{entity_manager.entities.len},
        ));

        if (false) {
            // true - to see cool graph
            c.DrawLine(0, 0, 500, 0, c.RED);
            c.DrawLine(0, 0, 0, -500, c.GREEN);

            const hop_distance: f32 = 5;
            const max_angle: f32 = std.math.degreesToRadians(180);
            const hop_amp: f32 = 4;

            var t: f32 = 0;

            var hop_value: f32 = 0;

            const Step: f32 = 0.01;

            var prev_value: f32 = 0;

            while (t < 500) : (t += Step) {
                hop_value += Step;
                if (hop_value > hop_distance) {
                    hop_value -= hop_distance;
                }

                const angle_value = (hop_value * max_angle) / hop_distance;

                const value = @sin(angle_value) * hop_amp;

                c.DrawLineV(.{ .x = t, .y = -prev_value }, .{ .x = t, .y = -value }, c.GOLD);

                prev_value = value;
            }
        }

        c.EndMode2D();

        const gui_camera = c.Camera2D{
            .target = .{},
            .zoom = 3,
        };

        c.BeginMode2D(gui_camera);

        if (game_manager.state == .RespawnScreen) {
            const zoomed_screen_width = screen_width / 3;
            const zoomed_screen_height = screen_height / 3;
            const font_size = 20;
            const padding = 8;
            const vertical_offset = font_size + padding;

            //TODO: Animate this screen

            {
                const text: [*c]const u8 = "Dudes overwhelmed you!";

                const width: f32 = @floatFromInt(c.MeasureText(text, font_size));
                c.DrawText(text, @intFromFloat((zoomed_screen_width - width) / 2), @intFromFloat(zoomed_screen_height / 2 - vertical_offset), font_size, c.RAYWHITE);
            }
            {
                const text = try std.fmt.allocPrintZ(
                    frame_allocator,
                    "Respawn in = {d:.0}...",
                    .{game_manager.respawn_time},
                );
                const width: f32 = @floatFromInt(c.MeasureText(text, font_size));
                c.DrawText(text.ptr, @intFromFloat((zoomed_screen_width - width) / 2), @intFromFloat(zoomed_screen_height / 2 + font_size + padding - vertical_offset), font_size, c.RAYWHITE);
            }
        } else if (game_manager.state == .Playing) {
            if (entity_manager.entityField(player_handle, .health)) |player_health| {
                var i: i8 = 0;
                var pos = c.Vector2{ .x = 2, .y = 2 };
                while (i < player_health.*) : (i += 1) {
                    const sprite = sprite_manager.get(.Heart);
                    drawSprite(sprite_manager.get(.Heart), pos, 0, c.RED);
                    pos.x += sprite.size.x;
                }
            }
        }

        c.EndMode2D();

        c.DrawFPS(2, 2);

        if (DebugMode) {
            for (frame_messages.items, 0..) |frame_message, i| {
                const index: c_int = @intCast(i);
                c.DrawText(frame_message.ptr, 2, 20 * (index + 1), 18, c.RAYWHITE);
            }
        }

        if (game_manager.state == .ReadyToRespawn) {
            log.debug("Spawning new player", .{});
            player_handle = entity_manager.createEntity(GigaEntity.player(.{ .x = 0, .y = 0 }));
            game_manager.state = .Playing;
            audio_manager.play(.Respawn);
        }
    }
}
