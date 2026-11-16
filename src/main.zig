//TODO: GPA allocator: dupeZ/free - possible bug

// TODO: Main game loop:
//         1. Shoot dudes.
//         2. Don't let the dudes overwhelm you.
//        +3. Pick up batteries to "charge" you.
//        +4. When charge is low - shoot less, high - shoot more, maybe even with spread shoot.
//         5. Try to have fun.
// TODO: Juice:
//        +1. Hop animation while walking.
//         2. Screen shake.
//        +3. Audio.
//         4. Some fancy effects.
//         5. Blaster animation, use cooldown timer.
//        +6. Trees, bushes and roads to have background.
// TODO: Gamepad support

// Raylib -> Sokol migration
// @todo: Proper transformations (pos -> NDC) and correct vertical orientation using matrices
// @done: Linear algebra - vectors and matrices
// @todo: More elaborate pipeline for immediate 2d vertices matrix stack, etc.
// @todo: Audio
// @todo: Index buffer in immediate render to use 4 vertices per quad
// @todo: Text rendering
// @todo: Asset system: pack all sprites and glyphs into a single texture (dev build - pack at startup, release build - pack at build time)
// @todo: Cleanup: remove `raylib_stub.zig`, separate platform, asset loader and game code
// @todo: Timing and fixed step of 1/60 sec

fn drawSprite(
    sprite: *const Sprite,
    position: rl.Vector2,
    rotation: f32,
    tint: rl.Color,
) void {
    rl.DrawTexturePro(
        sprite.texture,
        sprite.source,
        .{ .x = position.x, .y = position.y, .width = sprite.size.x, .height = sprite.size.y },
        .{ .x = sprite.origin.x * sprite.size.x, .y = sprite.origin.y * sprite.size.y },
        rotation,
        tint,
    );
}

const GameManager = struct {
    state: State = .StartScreen,
    respawn_time: f32 = 0,
    enemies_count: u32 = 0,
    target_enemies_count: u32 = 50,
    base_enemy_health: i8 = 3,
    score: u32 = 0,
    guy_award_score: u32 = 0,
    battery_count: u32 = 0,
    max_batteries_count: u32 = 50,
    battery_spawn_time: f32 = BatterySpawnTimeout,
    game_prng: std.Random.DefaultPrng = undefined,
    guys_count: u32 = 5,
    rng: std.Random = undefined,
    player_handle: EntityManager.Handle = undefined,

    //TODO: High-score on game-over screen

    const Self = @This();

    const State = enum {
        StartScreen,
        Playing,
        RespawnScreen,
        ReadyToRespawn,
        GameOver,
    };

    const BatterySpawnTimeout: f32 = 2;
    const BatterySpawnCount = 10;

    const GuyAwardScore = 200;

    pub fn reset(self: *Self) void {
        const now_ms = std.Io.Clock.now(std.Io.Clock.real, io).toMilliseconds();
        self.* = Self{};
        self.game_prng = std.Random.DefaultPrng.init(@intCast(now_ms));
        self.rng = self.game_prng.random();
        self.state = .Playing;

        entity_manager.clear();
        self.player_handle = entity_manager.createEntity(GigaEntity.player(.{ .x = 0, .y = 0 }));
        audio_manager.play(.NewGame);
    }

    pub fn playerFell(self: *Self) void {
        if (self.guys_count == 0) {
            audio_manager.play(.GameOver);
            self.state = .GameOver;
        } else {
            audio_manager.play(.PlayerFell);
            self.respawn_time = 3;
            self.state = .RespawnScreen;
            if (self.guys_count > 0) {
                self.guys_count -= 1;
            }
        }
    }

    pub fn respawnPlayer(self: *Self) void {
        self.player_handle = entity_manager.createEntity(GigaEntity.player(.{ .x = 0, .y = 0 }));
        self.state = .Playing;
        audio_manager.play(.Respawn);
    }

    pub fn update(
        self: *Self,
        input: Input,
    ) void {
        if (self.state == .RespawnScreen) {
            self.respawn_time = @max(self.respawn_time - input.dt, 0);
            if (self.respawn_time <= 0) {
                self.state = .ReadyToRespawn;
            }
        } else if (self.state == .Playing) {
            if (self.score > 100) {
                self.target_enemies_count = 150;
            } else if (self.score > 200) {
                self.target_enemies_count = 300;
            } else if (self.score > 400) {
                self.target_enemies_count = 600;
            } else if (self.score > 600) {
                self.target_enemies_count = 800;
            } else if (self.score > 800) {
                self.target_enemies_count = 1000;
            }

            if (self.enemies_count < self.target_enemies_count) {
                self.spawnSupostat(self.player_handle);
            }

            self.battery_spawn_time = @max(self.battery_spawn_time - input.dt, 0);
            if (self.battery_spawn_time <= 0) {
                self.battery_spawn_time = BatterySpawnTimeout;

                self.spawnBattery(self.player_handle);
            }
        }
    }

    pub fn spawnSupostat(
        self: *Self,
        player_handle: EntityManager.Handle,
    ) void {
        if (entity_manager.entityField(player_handle, .position)) |player_position| {
            const DistanceMin: f32 = 300;
            const DistanceMax: f32 = DistanceMin + 120;

            const radius = (self.rng.float(f32) * (DistanceMax - DistanceMin) + DistanceMin);
            const angle = std.math.degreesToRadians(self.rng.float(f32) * 360);

            const final_position = rl.Vector2Add(player_position.*, rl.Vector2Scale(rl.Vector2Rotate(.{ .y = -1 }, angle), radius));

            self.enemies_count += 1;
            //TODO: Scale enemy health
            _ = entity_manager.createEntity(GigaEntity.supostat(final_position, game_manager.rng, game_manager.base_enemy_health));
        }
    }

    pub fn supostatFell(self: *Self) void {
        self.score += 1;
        if (self.enemies_count > 0) {
            self.enemies_count -= 1;
        }

        if (self.score > hi_score) {
            hi_score = self.score;
        }

        self.guy_award_score += 1;
        if (self.guy_award_score >= GuyAwardScore) {
            self.guy_award_score = 0;
            self.guys_count += 1;
        }
    }

    pub fn spawnBattery(
        self: *Self,
        player_handle: EntityManager.Handle,
    ) void {
        if (entity_manager.entityField(player_handle, .position)) |player_position| {
            if (self.battery_count < self.max_batteries_count) {
                const DistanceMin: f32 = 70;
                const DistanceMax: f32 = DistanceMin + 50;

                const radius = (self.rng.float(f32) * (DistanceMax - DistanceMin) + DistanceMin);
                const angle = std.math.degreesToRadians(self.rng.float(f32) * 360);

                var final_position = rl.Vector2Add(player_position.*, rl.Vector2Scale(rl.Vector2Rotate(.{ .y = -1 }, angle), radius));
                final_position = rl.Vector2Clamp(
                    final_position,
                    .{ .x = -ArenaWidth * 0.8 * 0.5, .y = -ArenaHeight * 0.8 * 0.5 },
                    .{ .x = ArenaWidth * 0.8 * 0.5, .y = ArenaHeight * 0.8 * 0.5 },
                );

                self.battery_count += 1;
                _ = entity_manager.createEntity(GigaEntity.battery(final_position));
            }
        }
    }

    pub fn batteryPickedUp(self: *Self) void {
        audio_manager.play(.Pickup);
        if (self.battery_count > 0) {
            self.battery_count -= 1;
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
    position: *rl.Vector2,
    acceleration: *rl.Vector2,
    velocity: *rl.Vector2,
    input: Input,
    entity_physics_config: EntityPhysicsConfig,
) !void {
    if (rl.Vector2Length(velocity.*) > 0 and rl.Vector2Length(acceleration.*) > 0) {
        // Decrease velocity if direction was changed
        const vel_norm = rl.Vector2Normalize(velocity.*);
        const acc_norm = rl.Vector2Normalize(acceleration.*);
        const dot_product = rl.Vector2DotProduct(vel_norm, acc_norm);
        if (dot_product < 0) {
            velocity.* = rl.Vector2Subtract(velocity.*, rl.Vector2Scale(velocity.*, (1 - entity_physics_config.damping) * @abs(dot_product) * input.dt / entity_physics_config.mass));
        }
    }
    if (BuggyPhysicsIntegration) {
        const vt = rl.Vector2Scale(velocity.*, input.dt);
        const at = rl.Vector2Scale(acceleration.*, input.dt * input.dt * 0.5);
        velocity.* = rl.Vector2Add(velocity.*, rl.Vector2Add(vt, at));
    } else {
        velocity.* = rl.Vector2Add(velocity.*, rl.Vector2Scale(acceleration.*, input.dt));
    }

    if (rl.Vector2Length(acceleration.*) == 0) {
        velocity.* = rl.Vector2Scale(velocity.*, entity_physics_config.damping);
    }

    velocity.* = rl.Vector2ClampValue(velocity.*, 0, entity_physics_config.max_velocity);

    position.* = rl.Vector2Add(position.*, rl.Vector2Scale(velocity.*, input.dt));
}

const BuggyPhysicsIntegration = false;

pub fn determineDirection(up: bool, down: bool, left: bool, right: bool) rl.Vector2 {
    var result = rl.Vector2{};
    if (left) result.x = -1;
    if (right) result.x = 1;
    if (up) result.y = -1;
    if (down) result.y = 1;
    return rl.Vector2Normalize(result);
}

fn update(
    input: Input,
    player_position: ?rl.Vector2,
) !void {
    var i: usize = 0;
    while (i < entity_manager.entities.len) : (i += 1) {
        const flags = entity_manager.entities.items(.flags);
        const position = entity_manager.entities.items(.position);
        const acceleration = entity_manager.entities.items(.acceleration);
        const velocity = entity_manager.entities.items(.velocity);
        const shoot_info = entity_manager.entities.items(.shoot_info);
        const ttl = entity_manager.entities.items(.ttl);
        const enemy_behavior = entity_manager.entities.items(.enemy_behavior);
        const damage_animation = entity_manager.entities.items(.damage_animation);
        const iframes = entity_manager.entities.items(.iframes);
        const hop_value = entity_manager.entities.items(.hop_value);
        const above_ground_value = entity_manager.entities.items(.above_ground_value);
        const energy = entity_manager.entities.items(.energy);

        //TODO: Proper units: e.g. 16px - 1 meter or something.

        //TODO: Start extracting to functions.

        if (flags[i].class == .Player) {
            acceleration[i] = determineDirection(input.up, input.down, input.left, input.right);

            acceleration[i] = rl.Vector2Scale(rl.Vector2Normalize(acceleration[i]), config.player_acc_magnitude);
            frame_messages.appendAssumeCapacity(try std.fmt.allocPrintSentinel(
                frame_allocator,
                "player.acceleration = {d:.4}, {d:.4}.",
                .{ acceleration[i].x, acceleration[i].y },
                0,
            ));
            frame_messages.appendAssumeCapacity(try std.fmt.allocPrintSentinel(
                frame_allocator,
                "player.velocity = {d:.4}, {d:.4}.",
                .{ velocity[i].x, velocity[i].y },
                0,
            ));
        } else if (flags[i].class == .Projectile) {
            ttl[i] = @max(ttl[i] - input.dt, 0);
            if (ttl[i] == 0) {
                flags[i].alive = false;
            }
        } else if (flags[i].class == .Supostat) {
            enemy_behavior[i].mode = .Loiter;
            var player_position_for_pursuit: rl.Vector2 = .{};
            if (player_position) |provided_player_position| {
                if (rl.Vector2Distance(provided_player_position, position[i]) <= config.enemy_aggression_distance) {
                    enemy_behavior[i].mode = .Pursuit;
                    player_position_for_pursuit = provided_player_position;
                }
            }

            switch (enemy_behavior[i].mode) {
                .Loiter => {
                    enemy_behavior[i].time_to_next -= input.dt;

                    if (enemy_behavior[i].time_to_next <= 0) {
                        enemy_behavior[i].time_to_next = game_manager.rng.float(f32) * config.enemy_loiter_time;
                        enemy_behavior[i].commit_to_direction.x = ((game_manager.rng.floatExp(f32) * 2) - 1);
                        enemy_behavior[i].commit_to_direction.y = ((game_manager.rng.floatExp(f32) * 2) - 1);
                    }
                },
                .Pursuit => {
                    enemy_behavior[i].commit_to_direction = .{};

                    const actual_target_position = rl.Vector2{
                        .x = player_position_for_pursuit.x + (game_manager.rng.floatExp(f32) * config.enemy_pursuit_dispersal) - config.enemy_pursuit_dispersal * 0.5,
                        .y = player_position_for_pursuit.y + (game_manager.rng.floatExp(f32) * config.enemy_pursuit_dispersal) - config.enemy_pursuit_dispersal * 0.5,
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

            enemy_behavior[i].commit_to_direction = rl.Vector2Normalize(enemy_behavior[i].commit_to_direction);
            acceleration[i] = enemy_behavior[i].commit_to_direction;
            acceleration[i] = rl.Vector2Scale(rl.Vector2Normalize(acceleration[i]), config.enemy_acc_magnitude);
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
                position[i] = rl.Vector2Clamp(
                    position[i],
                    .{ .x = -ArenaWidth * 0.5, .y = -ArenaHeight * 0.5 },
                    .{ .x = ArenaWidth * 0.5, .y = ArenaHeight * 0.5 },
                );

                const frame_distance = rl.Vector2Distance(initial_position, position[i]);

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
                shoot_info[i].cooldown = @max(shoot_info[i].cooldown - input.dt, 0);
            }

            const is_shooting = input.shoot_up or input.shoot_down or input.shoot_left or input.shoot_right;
            if (is_shooting and shoot_info[i].cooldown <= 0) {
                const shoot_direction = determineDirection(
                    input.shoot_up,
                    input.shoot_down,
                    input.shoot_left,
                    input.shoot_right,
                );

                const shoot_start_position = rl.Vector2Add(
                    rl.Vector2{ .x = 0, .y = -config.player_shoot_hands_height },
                    rl.Vector2Add(
                        position[i],
                        rl.Vector2Scale(shoot_direction, config.player_shoot_start_distance),
                    ),
                );

                _ = entity_manager.createEntity(GigaEntity.projectile(
                    shoot_start_position,
                    rl.Vector2Scale(shoot_direction, config.player_projectile_acceleration_magnitude),
                    config.player_projectile_ttl,
                ));
                audio_manager.play(.Pew);

                var cooldown_factor: f32 = 1;

                if (energy[i] == 0) {
                    cooldown_factor = 8;
                } else if (energy[i] < 20) {
                    cooldown_factor = 5;
                } else if (energy[i] < 40) {
                    cooldown_factor = 3;
                } else if (energy[i] < 60) {
                    cooldown_factor = 1.7;
                } else if (energy[i] < 80) {
                    cooldown_factor = 1.2;
                }

                shoot_info[i].cooldown = config.player_shoot_cooldown * cooldown_factor;
                energy[i] = std.math.clamp(energy[i] - config.shoot_energy_cost, 0, GigaEntity.MaxEnergy);
            }

            frame_messages.appendAssumeCapacity(try std.fmt.allocPrintSentinel(
                frame_allocator,
                "player.shoot_cooldown = {d:.4}.",
                .{shoot_info[i].cooldown},
                0,
            ));
        }

        if (damage_animation[i] > 0) {
            damage_animation[i] = @max(damage_animation[i] - input.dt * config.damage_animation_speed, 0);
        }

        if (iframes[i] > 0) {
            iframes[i] = @max(iframes[i] - input.dt, 0);
        }

        if (flags[i].class == .Player) {
            frame_messages.appendAssumeCapacity(try std.fmt.allocPrintSentinel(
                frame_allocator,
                "player.iframes = {d:.4}.",
                .{iframes[i]},
                0,
            ));
        }
    }

    i = 0;
    while (i < entity_manager.entities.len) : (i += 1) {
        const flags = entity_manager.entities.items(.flags);
        const position = entity_manager.entities.items(.position);
        const velocity = entity_manager.entities.items(.velocity);
        const health = entity_manager.entities.items(.health);
        const damage_animation = entity_manager.entities.items(.damage_animation);
        const iframes = entity_manager.entities.items(.iframes);
        const above_ground_value = entity_manager.entities.items(.above_ground_value);
        const energy = entity_manager.entities.items(.energy);
        var j: usize = 0;
        while (j < entity_manager.entities.len) : (j += 1) {
            if (i != j and flags[i].alive and flags[i].collideable) {
                if (flags[i].class == .Player and flags[j].class == .Battery and flags[j].alive) {
                    const real_position_p = rl.Vector2Add(rl.Vector2Add(position[i], .{ .y = -above_ground_value[i] }), .{ .y = -config.general_center_from_bottom });
                    const real_position_b = rl.Vector2Add(position[j], .{ .y = -config.general_center_from_bottom });
                    if (DebugMode) {
                        rl.DrawCircleV(real_position_p, config.general_radius, rl.GOLD);
                        rl.DrawCircleV(real_position_b, config.general_radius, rl.YELLOW);
                    }
                    if (rl.Vector2Distance(real_position_p, real_position_b) <= config.general_radius * 2) {
                        game_manager.batteryPickedUp();

                        energy[i] = std.math.clamp(energy[i] + config.battery_energy_amount, 0, GigaEntity.MaxEnergy);
                        flags[j].alive = false;
                        //TODO: Pickup animation
                    }
                }
                if (flags[i].class == .Projectile and flags[j].class == .Supostat) {
                    const real_position_b = rl.Vector2Add(rl.Vector2Add(position[j], .{ .y = -above_ground_value[j] }), .{ .y = -config.general_center_from_bottom });
                    if (DebugMode) {
                        rl.DrawCircleV(real_position_b, config.general_radius, rl.GOLD);
                        rl.DrawCircleV(position[i], config.projectile_radius, rl.YELLOW);
                    }
                    if (rl.Vector2Distance(position[i], real_position_b) <= config.general_radius + config.projectile_radius) {
                        audio_manager.playOneOf(game_manager.rng, &.{ .Damage0, .Damage1, .Damage2, .Damage3, .Damage4 });
                        health[j] -= 1;
                        flags[i].alive = false;
                        damage_animation[j] = 1;

                        velocity[j] = rl.Vector2Add(velocity[j], rl.Vector2Scale(velocity[i], config.damage_inertia_factor));

                        //TODO: Some particles

                        if (health[j] <= 0) {
                            flags[j].alive = false;
                            audio_manager.playOneOf(game_manager.rng, &.{ .EnemyFell0, .EnemyFell1, .EnemyFell2 });
                            game_manager.supostatFell();
                            //TODO: Death animation
                        }
                    }
                } else if (flags[i].class == .Supostat and flags[j].class == .Player) {
                    const real_position_s = rl.Vector2Add(rl.Vector2Add(position[i], .{ .y = -above_ground_value[i] }), .{ .y = -config.general_center_from_bottom });
                    const real_position_p = rl.Vector2Add(rl.Vector2Add(position[j], .{ .y = -above_ground_value[j] }), .{ .y = -config.general_center_from_bottom });

                    if (rl.Vector2Distance(real_position_s, real_position_p) <= config.general_radius * 2) {
                        if (iframes[j] <= 0) {
                            velocity[j] = rl.Vector2Add(velocity[j], rl.Vector2Scale(velocity[i], config.damage_inertia_factor * 0.2));
                            audio_manager.playOneOf(game_manager.rng, &.{ .DamageFromSupostat0, .DamageFromSupostat1, .DamageFromSupostat2, .DamageFromSupostat3 });
                            health[j] -= 1;
                            damage_animation[j] = 1;
                            iframes[j] = config.iframes;

                            //TODO: Some particles

                            if (health[j] <= 0) {
                                flags[j].alive = false;

                                game_manager.playerFell();
                                //TODO: Death animation
                            }
                        }
                    }
                }
            }
        }
    }
}

pub const ArenaWidth = 100 * 16;
pub const ArenaHeight = 100 * 16;

fn render(input: Input) void {
    rl.DrawRectangle(-ArenaWidth * 0.5, -ArenaHeight * 0.5, 1, ArenaHeight, rl.GRAY);
    rl.DrawRectangle(ArenaWidth * 0.5, -ArenaHeight * 0.5, 1, ArenaHeight, rl.GRAY);

    rl.DrawRectangle(-ArenaWidth * 0.5, -ArenaHeight * 0.5, ArenaWidth, 1, rl.GRAY);
    rl.DrawRectangle(-ArenaWidth * 0.5, ArenaHeight * 0.5, ArenaWidth + 1, 1, rl.GRAY);

    {
        var frame_prng = std.Random.DefaultPrng.init(0x69);
        var frame_rng = frame_prng.random();

        var x: f32 = -ArenaWidth * 0.5;
        while (x < ArenaWidth * 0.5) : (x += 16) {
            var y: f32 = -ArenaWidth * 0.5;
            while (y < ArenaWidth * 0.5) : (y += 16) {
                if (frame_rng.int(u16) < config.decor_magic) {
                    const DecorSprites = [_]SpriteHandle{ .Decor0, .Decor1 };
                    const decor_index = frame_rng.uintLessThan(usize, DecorSprites.len);

                    var hsv = rl.ColorToHSV(rl.GREEN);
                    hsv.y = frame_rng.float(f32) * 0.5 + 0.25;
                    hsv.z = frame_rng.float(f32) * 0.5 + 0.25;
                    const final_color = rl.ColorFromHSV(hsv.x, hsv.y, hsv.z);

                    drawSprite(
                        sprite_manager.get(DecorSprites[decor_index]),
                        .{ .x = x + frame_rng.floatExp(f32) * 8 - 4, .y = y + frame_rng.floatExp(f32) * 8 - 4 },
                        0,
                        final_color,
                    );
                }
            }
        }
    }

    inline for (@typeInfo(GigaEntity.Layer).@"enum".field_values) |layer_field_value| {
        const current_layer: GigaEntity.Layer = @fromBackingInt(@intCast(layer_field_value));
        var i: usize = 0;
        while (i < entity_manager.entities.len) : (i += 1) {
            const flags = entity_manager.entities.items(.flags);
            const position = entity_manager.entities.items(.position);
            const tint = entity_manager.entities.items(.tint);
            const damage_animation = entity_manager.entities.items(.damage_animation);
            const layer = entity_manager.entities.items(.layer);
            const above_ground_value = entity_manager.entities.items(.above_ground_value);
            const iframes = entity_manager.entities.items(.iframes);
            if (flags[i].visual and current_layer == layer[i]) {
                if (flags[i].class == .Player) {
                    if (iframes[i] > 0) {
                        iframe_blink = !iframe_blink;
                    } else {
                        iframe_blink = true;
                    }

                    if (iframe_blink) {
                        const final_position = rl.Vector2Add(position[i], .{ .y = -above_ground_value[i] });
                        const player_sprite = sprite_manager.get(.Player);
                        {
                            const final_tint = rl.ColorLerp(tint[i], rl.WHITE, damage_animation[i]);
                            drawSprite(player_sprite, final_position, 0, final_tint);
                        }
                        const blaster_sprite = sprite_manager.get(.Blaster);

                        const is_shooting = input.shoot_up or input.shoot_down or input.shoot_left or input.shoot_right;
                        if (is_shooting) {
                            const shoot_direction = determineDirection(
                                input.shoot_up,
                                input.shoot_down,
                                input.shoot_left,
                                input.shoot_right,
                            );

                            const blaster_position = rl.Vector2Add(
                                rl.Vector2{ .x = 0, .y = -config.player_shoot_hands_height },
                                rl.Vector2Add(
                                    final_position,
                                    rl.Vector2Scale(shoot_direction, config.player_blaster_distance),
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

                            // frame_messages.appendAssumeCapacity(try std.fmt.allocPrintSentinel(
                            //     frame_allocator,
                            //     "player.blaster_angle = {d:.4}.",
                            //     .{angle},
                            // ));
                            {
                                const final_tint = rl.ColorLerp(rl.DARKGREEN, rl.WHITE, damage_animation[i]);
                                drawSprite(blaster_sprite, blaster_position, angle, final_tint);
                            }
                        }
                    }
                } else if (flags[i].class == .Battery) {
                    const battery_sprite = sprite_manager.get(.Battery);
                    drawSprite(battery_sprite, position[i], 0, tint[i]);
                } else if (flags[i].class == .Projectile) {
                    const projectile_sprite = sprite_manager.get(.Projectile);
                    drawSprite(projectile_sprite, position[i], 0, tint[i]);
                } else if (flags[i].class == .Supostat) {
                    const final_position = rl.Vector2Add(position[i], .{ .y = -above_ground_value[i] });
                    const final_tint = rl.ColorLerp(tint[i], rl.WHITE, damage_animation[i]);
                    const monster_sprite = sprite_manager.get(.Enemy0);
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

fn drawBatteryIcon(zoomed_screen_width: f32, energy: f32) void {
    const pad: f32 = 4;
    const width_px: f32 = 16;
    const height_px: f32 = 8;

    const low_energy: f32 = 10;

    const max_energy_px = width_px - 4;

    const energy_px: f32 = @trunc((max_energy_px * energy) / GigaEntity.MaxEnergy);

    const pos = rl.Vector2{ .x = zoomed_screen_width - width_px - pad, .y = pad };

    const color = if (energy >= low_energy) rl.WHITE else rl.RED;

    rl.DrawRectangleV(
        .{ .x = pos.x, .y = pos.y + 1 },
        .{ .x = 1, .y = height_px - 2 },
        color,
    );
    rl.DrawRectangleV(
        .{ .x = pos.x + width_px - 1, .y = pos.y + 1 },
        .{ .x = 1, .y = height_px - 2 },
        color,
    );
    rl.DrawRectangleV(
        .{ .x = pos.x + 1, .y = pos.y },
        .{ .x = width_px - 2, .y = 1 },
        color,
    );
    rl.DrawRectangleV(
        .{ .x = pos.x + 1, .y = pos.y + height_px - 1 },
        .{ .x = width_px - 2, .y = 1 },
        color,
    );
    rl.DrawRectangleV(
        .{ .x = pos.x + 2, .y = pos.y + 2 },
        .{ .x = energy_px, .y = height_px - 4 },
        color,
    );
}

const Release = BuildMode == .fast or BuildMode == .safe;

var game_manager = GameManager{};

// init_cb: ?*const fn () callconv(.c) void = null,
// frame_cb: ?*const fn () callconv(.c) void = null,
// cleanup_cb: ?*const fn () callconv(.c) void = null,
// event_cb: ?*const fn ([*c]const Event) callconv(.c) void = null,

var config_watcher: util.FileWatcher = undefined;
var audio_manager: AudioManager = undefined;
var sprite_manager: SpriteManager = undefined;
var entity_manager: EntityManager = undefined;
var config: GlobalConfig = .{};
var frame_messages: std.ArrayList([]const u8) = .empty;
var frame_memory: [1 * 1024 * 1024]u8 = undefined;
var frame_fba: std.heap.FixedBufferAllocator = undefined;
var frame_arena: std.heap.ArenaAllocator = undefined;
var frame_allocator: std.mem.Allocator = undefined;

var camera_position = rl.Vector2{};

fn initMaybe() !void {
    if (GlobalConfig.load(".", "config.json", gpa, io)) |loaded_config| {
        config = loaded_config;
    }

    rl.SetConfigFlags(rl.FLAG_WINDOW_RESIZABLE);

    rl.InitWindow(1280, 720, "The Discharge of Captain Volt");

    defer rl.CloseWindow();

    rl.SetTargetFPS(60);

    config_watcher = try util.FileWatcher.init(".", "config.json", 0.5, io);

    sprite_manager = try SpriteManager.init(gpa);
    audio_manager = AudioManager.init();

    entity_manager = try EntityManager.init(gpa);

    if (false) {
        var entities_to_spawn: i32 = 100;
        while (entities_to_spawn >= 0) : (entities_to_spawn -= 1) {
            const Distribution = 200;
            if (game_manager.rng.boolean() and game_manager.rng.boolean()) {
                _ = entity_manager.createEntity(GigaEntity.battery(
                    .{
                        .x = game_manager.rng.floatNorm(f32) * Distribution - Distribution * 0.5,
                        .y = game_manager.rng.floatNorm(f32) * Distribution - Distribution * 0.5,
                    },
                ));
            } else {
                _ = entity_manager.createEntity(GigaEntity.supostat(.{
                    .x = game_manager.rng.floatNorm(f32) * Distribution - Distribution * 0.5,
                    .y = game_manager.rng.floatNorm(f32) * Distribution - Distribution * 0.5,
                }, game_manager.rng));
            }
        }
    }

    frame_messages = try std.ArrayList([]const u8).initCapacity(gpa, 1024);

    frame_fba = std.heap.FixedBufferAllocator.init(frame_memory[0..]);
    frame_arena = std.heap.ArenaAllocator.init(frame_fba.allocator());
    frame_allocator = frame_arena.allocator();

    hi_score = loadHiScore(gpa);
}

fn frameMaybe() !void {
    frame_messages.clearRetainingCapacity();
    _ = frame_arena.reset(.retain_capacity);

    if (game_manager.state == .GameOver) {
        if (rl.GetKeyPressed() != .none) {
            game_manager.reset();
        }
    } else if (game_manager.state == .StartScreen) {
        if (rl.GetKeyPressed() != .none) {
            game_manager.reset();
        }
    }

    const input = Input{
        .dt = rl.GetFrameTime(),
        .up = rl.IsKeyDown(.W),
        .down = rl.IsKeyDown(.S),
        .left = rl.IsKeyDown(.A),
        .right = rl.IsKeyDown(.D),
        .shoot_up = rl.IsKeyDown(.I) or rl.IsKeyDown(.UP),
        .shoot_down = rl.IsKeyDown(.K) or rl.IsKeyDown(.DOWN),
        .shoot_left = rl.IsKeyDown(.J) or rl.IsKeyDown(.LEFT),
        .shoot_right = rl.IsKeyDown(.L) or rl.IsKeyDown(.RIGHT),
    };

    if (!Release) {
        if (config_watcher.wasModified(input.dt, io)) {
            log.debug("Config was changed, reloading...", .{});
            if (GlobalConfig.load(".", "config.json", frame_allocator, io)) |loaded_config| {
                //TODO: Print updated values
                config = loaded_config;
            } else {
                log.err("Config was not updated!", .{});
            }
        }
    }

    const screen_width: f32 = @floatFromInt(rl.GetScreenWidth());
    const screen_height: f32 = @floatFromInt(rl.GetScreenHeight());

    var player_position_for_pursuit: ?rl.Vector2 = null;
    if (entity_manager.entityField(game_manager.player_handle, .position)) |player_position| {
        camera_position = rl.Vector2Lerp(camera_position, player_position.*, config.camera_lerp_value);
        player_position_for_pursuit = player_position.*;
    }

    const Zoom = 3;

    const camera = rl.Camera2D{
        .offset = .{ .x = screen_width * 0.5, .y = screen_height * 0.5 },
        .rotation = 0,
        .target = camera_position,
        .zoom = Zoom,
    };

    rl.BeginDrawing();
    defer rl.EndDrawing();

    rl.BeginMode2D(camera);

    rl.ClearBackground(rl.BLACK);

    game_manager.update(input);

    try update(input, player_position_for_pursuit);
    cleanupEntities(&entity_manager);
    render(input);

    frame_messages.appendAssumeCapacity(try std.fmt.allocPrintSentinel(
        frame_allocator,
        "entities.count = {d}.",
        .{entity_manager.entities.len},
        0,
    ));

    if (false) {
        // true - to see cool graph
        rl.DrawLine(0, 0, 500, 0, rl.RED);
        rl.DrawLine(0, 0, 0, -500, rl.GREEN);

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

            rl.DrawLineV(.{ .x = t, .y = -prev_value }, .{ .x = t, .y = -value }, rl.GOLD);

            prev_value = value;
        }
    }

    rl.EndMode2D();

    const gui_camera = rl.Camera2D{
        .zoom = Zoom,
    };

    rl.BeginMode2D(gui_camera);

    const zoomed_screen_width = screen_width / Zoom;
    const zoomed_screen_height = screen_height / Zoom;
    switch (game_manager.state) {
        .RespawnScreen => {
            const font_size = 20;
            const padding = 8;
            const full_text_height = font_size * 2 + 8;

            //TODO: Animate this screen
            {
                const text: [*c]const u8 = "Dudes overwhelmed you!";

                const width: f32 = @floatFromInt(rl.MeasureText(text, font_size));
                rl.DrawText(
                    text,
                    @intFromFloat((zoomed_screen_width - width) * 0.5),
                    @intFromFloat((zoomed_screen_height - full_text_height) * 0.5),
                    font_size,
                    rl.RAYWHITE,
                );
            }
            {
                const text = try std.fmt.allocPrintSentinel(
                    frame_allocator,
                    "Respawn in = {d:.0}...",
                    .{game_manager.respawn_time},
                    0,
                );
                const width: f32 = @floatFromInt(rl.MeasureText(text, font_size));
                rl.DrawText(
                    text.ptr,
                    @intFromFloat((zoomed_screen_width - width) * 0.5),
                    @intFromFloat((zoomed_screen_height - full_text_height) * 0.5 + padding + font_size),
                    font_size,
                    rl.RAYWHITE,
                );
            }
        },
        .Playing => {
            if (entity_manager.entityField(game_manager.player_handle, .health)) |player_health| {
                var i: i8 = 0;
                var pos = rl.Vector2{ .x = 2, .y = 2 };
                while (i < player_health.*) : (i += 1) {
                    const sprite = sprite_manager.get(.Heart);
                    drawSprite(sprite, pos, 0, rl.RED);
                    pos.x += sprite.size.x;
                }
            }
            {
                var i: i8 = 0;
                var pos = rl.Vector2{ .x = 2, .y = zoomed_screen_height - 16 - 2 };
                while (i < game_manager.guys_count) : (i += 1) {
                    const sprite = sprite_manager.get(.Helmet);
                    drawSprite(sprite, pos, 0, rl.LIME);
                    pos.x += sprite.size.x;
                }
            }

            if (entity_manager.entityField(game_manager.player_handle, .energy)) |player_energy| {
                drawBatteryIcon(zoomed_screen_width, player_energy.*);
            }

            {
                const score_font_size = 16;
                const padding = 4;
                const text = try std.fmt.allocPrintSentinel(
                    frame_allocator,
                    "{d}",
                    .{game_manager.score},
                    0,
                );
                const width: f32 = @floatFromInt(rl.MeasureText(text, score_font_size));
                rl.DrawText(
                    text.ptr,
                    @intFromFloat((zoomed_screen_width - width) * 0.5),
                    @intFromFloat(padding),
                    score_font_size,
                    rl.RAYWHITE,
                );
            }
        },
        .GameOver => {
            try generalScreenWithBlinkingPrompt(
                zoomed_screen_width,
                zoomed_screen_height,
                "Discharged.",
                "Press any key to try again!",
                60,
            );
        },
        .StartScreen => {
            try generalScreenWithBlinkingPrompt(
                zoomed_screen_width,
                zoomed_screen_height,
                "The Discharge of Captain Volt",
                "Press any key to try again!",
                27,
            );
        },
        else => {},
    }

    rl.EndMode2D();

    if (!Release) {
        rl.DrawFPS(2, 2);
    }

    if (DebugMode) {
        for (frame_messages.items, 0..) |frame_message, i| {
            const index: c_int = @intCast(i);
            rl.DrawText(frame_message.ptr, 2, 20 * (index + 1), 18, rl.RAYWHITE);
        }
    }

    if (game_manager.state == .ReadyToRespawn) {
        game_manager.respawnPlayer();
    }
}

fn cleanupMaybe() !void {
    saveHiScore() catch |err| {
        log.err(
            "{s} was not saved because of [{any}], but it was probably not OK.",
            .{ HiScoreFile, err },
        );
    };
    frame_messages.deinit(gpa);
    entity_manager.deinit();
}

const SokolState = struct {
    shader: sg.Shader,
    fallback_image: sg.Image,
    pipeline: sg.Pipeline,
    test_triangle: sg.Buffer,
    fallback_image_view: sg.View,
    sampler: sg.Sampler,
    immediate_render: ImmediateRender,
};

pub var sokol_state: SokolState = undefined;

fn onInit() callconv(.c) void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = util.loggerFunction },
    });

    sokol_state.shader = sg.makeShader(shader_sprite2d.sprite2dShaderDesc(sg.queryBackend()));

    sokol_state.fallback_image = sg.makeImage(.{
        .width = 4,
        .height = 4,
        .data = sg.asRange(&[4 * 4]u32{
            0xFFFFFFFF, 0xFF000000, 0xFFFFFFFF, 0xFF000000,
            0xFF000000, 0xFFFFFFFF, 0xFF000000, 0xFFFFFFFF,
            0xFFFFFFFF, 0xFF000000, 0xFFFFFFFF, 0xFF000000,
            0xFF000000, 0xFFFFFFFF, 0xFF000000, 0xFFFFFFFF,
        }),
    });

    sokol_state.pipeline = sg.makePipeline(.{
        .shader = sokol_state.shader,
        .layout = init: {
            var l: sg.VertexLayoutState = .{};
            l.attrs[shader_sprite2d.ATTR_sprite2d_pos].format = .FLOAT2;
            l.attrs[shader_sprite2d.ATTR_sprite2d_color0].format = .UBYTE4N;
            l.attrs[shader_sprite2d.ATTR_sprite2d_texcoord0].format = .USHORT2N;
            break :init l;
        },
        // .index_type = .UINT16,
        // .depth = .{
        //     .compare = .LESS_EQUAL,
        //     .write_enabled = true,
        // },
        //.cull_mode = .BACK,
    });

    sokol_state.test_triangle = sg.makeBuffer(.{
        .data = sg.asRange(&[_]Vertex{
            // zig fmt: off
            .{ .x =    0, .y =  0.5, .color = 0xFF0000FF, .u = 0x0000,  .v = 0xFFFF },
            .{ .x =  0.5, .y = -0.5, .color = 0xFF00FF00, .u = 0xFFFF,  .v = 0x0000 },
            .{ .x = -0.5, .y = -0.5, .color = 0xFFFF0000, .u = 0x0000,  .v = 0x0000 },
            // zig fmt: on
        }),
    });

    sokol_state.fallback_image_view = sg.makeView(.{
        .texture = .{
            .image = sokol_state.fallback_image,
        },
    });
    sokol_state.sampler = sg.makeSampler(.{ .mag_filter = .NEAREST });

    sokol_state.immediate_render = .init();

    initMaybe() catch |err| @panic(@errorName(err));
}

const Vertex = extern struct { x: f32, y: f32, color: u32, u: u16, v: u16 };

fn onFrame() callconv(.c) void {
    frameMaybe() catch |err| @panic(@errorName(err));

    var pass_action: sg.PassAction = .{};
    pass_action.colors[0].load_action = .CLEAR;
    pass_action.colors[0].clear_value = .{
        .r = 0.2,
        .g = 0.2,
        .b = 0.2,
        .a = 1,
    };

    if (false) {
        var it = sprite_manager.textures.iterator();

        var i: f32 = 0;
        while (it.next()) |texture_entry| : (i += 1) {
            const texture = texture_entry.value.*;

            const q: Quad = .{
                .pos = .{ i * 70 + 6, 6 },
                .size = .{ 64, 64 },
                .origin = .{ 0, 0 },
                .screen_size = ScreenSize,
                .color = @bitCast(rl.RED),
            };
            sokol_state.immediate_render.pushQuad(q.toVertices(), texture.view);
        }
    }

    sg.beginPass(.{
        .action = pass_action,
        .swapchain = sglue.swapchain(),
    });

    sokol_state.immediate_render.draw(sokol_state.sampler, sokol_state.pipeline);

    // sg.applyPipeline(sokol_state.pipeline);
    // sg.applyBindings(bind);
    // //sg.applyUniforms(shd.UB_vs_params, sg.asRange(&vs_params));
    // sg.draw(0, 3, 1);
    sg.endPass();
    sg.commit();

    //io.sleep(.fromMilliseconds(@divFloor(1000, 60)), std.Io.Clock.real) catch |err| @panic(@errorName(err));
}

fn onCleanup() callconv(.c) void {
    cleanupMaybe() catch |err| @panic(@errorName(err));
    sg.shutdown();
}

fn onEvent(event: [*c]const sapp.Event) callconv(.c) void {
    _ = event; // autofix
}

var gpa: std.mem.Allocator = undefined;
var io: std.Io = undefined;

const ImmediateRender = struct {
    buffer: sg.Buffer,

    vertices: Vertices = undefined,
    draw_calls: [0xFFFF]DrawCall = undefined,

    current_draw_call: DrawCall = .{
        .base_element = 0,
        .num_elements = 0,
        .texture_view = .{},
    },

    vertex_index: u16 = 0,
    draw_call_index: u16 = 0,

    const Self = @This();

    const Vertices = [0xFFFF]Vertex;

    pub fn init() Self {
        return .{
            .buffer = sg.makeBuffer(.{
                .size = @sizeOf(Vertices),
                .usage = .{ .vertex_buffer = true, .write_transient = true },
            }),
        };
    }

    pub fn pushQuad(
        self: *Self,
        vs: [4]Vertex, // TODO: Can be compacted
        texture_view: sg.View,
    ) void {
        if (texture_view.id != self.current_draw_call.texture_view.id) {
            self.flush();
            self.current_draw_call.texture_view = texture_view;
        }
        self.pushVertex(vs[0]);
        self.pushVertex(vs[1]);
        self.pushVertex(vs[3]);

        self.pushVertex(vs[1]);
        self.pushVertex(vs[2]);
        self.pushVertex(vs[3]);
    }

    pub fn draw(self: *Self, tmp_sampler: sg.Sampler, tmp_pipeline: sg.Pipeline) void {
        self.flush();

        if (self.draw_call_index == 0) {
            return;
        }

        if (false) {
            for (self.draw_calls[0..5], 0..) |draw_call, i| {
                log.debug("{d} - base: {d}, num: {d}.", .{ i, draw_call.base_element, draw_call.num_elements });
            }
            assert(false);
        }

        sg.writeBufferTransient(.{
            .src = .{ .data = sg.asRange(self.vertices[0..self.vertex_index]) },
            .dst = .{ .buffer = self.buffer },
        });

        var bind: sg.Bindings = .{};
        bind.vertex_buffers[0] = self.buffer;

        sg.applyPipeline(tmp_pipeline);
        for (self.draw_calls[0..self.draw_call_index]) |draw_call| {
            bind.views[shader_sprite2d.VIEW_tex] = draw_call.texture_view;
            bind.samplers[shader_sprite2d.SMP_smp] = tmp_sampler;

            sg.applyBindings(bind);
            sg.draw(draw_call.base_element, draw_call.num_elements, 1);
        }

        self.current_draw_call = .{
            .base_element = 0,
            .num_elements = 0,
            .texture_view = .{},
        };
        self.vertex_index = 0;
        self.draw_call_index = 0;
    }

    fn pushVertex(self: *Self, v: Vertex) void {
        assert(self.vertex_index < self.vertices.len);
        self.vertices[self.vertex_index] = v;
        self.vertex_index += 1;
        self.current_draw_call.num_elements += 1;
    }

    fn flush(self: *Self) void {
        if (self.current_draw_call.num_elements == 0) {
            return;
        }

        const num_elements = self.current_draw_call.num_elements;

        self.draw_calls[self.draw_call_index] = self.current_draw_call;
        self.draw_call_index += 1;

        self.current_draw_call.base_element += num_elements;
        self.current_draw_call.num_elements = 0;
    }

    const DrawCall = struct {
        base_element: u32,
        num_elements: u32,
        texture_view: sg.View,
    };
};

pub const Quad = struct {
    pos: [2]f32,
    size: [2]f32,
    origin: [2]f32,
    // TODO: rotation
    screen_size: [2]f32,
    color: u32,

    const Self = @This();

    // Sprite
    //  .------> x
    //  |
    //  |
    //  |
    // \/ y

    // NDC
    //        /\ 1 y
    //        |
    // -1 --------> 1 x
    //        |
    //        | -1
    //

    fn norm(value: vec2, size: vec2) vec2 {
        const value_v3: vec3 = .{ value[0], value[1], 1 };

        const scale: mat3 = .{
            .{ 4 / size[0], 0, 0 },
            .{ 0, -4 / size[1], 0 },
            .{ 0, 0, 1 },
        };

        const translate: mat3 = .{
            .{ 1, 0, -size[0] / 2 },
            .{ 0, 1, -size[1] / 2 },
            .{ 0, 0, 1 },
        };

        const normalized = la.transform(value_v3, la.mul(translate, scale));
        return .{ normalized[0], normalized[1] };
    }

    pub fn toVertices(self: Self) [4]Vertex {
        const size: vec2 = self.size;

        const origin: vec2 = self.origin;

        var top_left: vec2 = self.pos;
        top_left -= size * origin;

        const bottom_right = norm(top_left + size, self.screen_size);

        top_left = norm(top_left, self.screen_size);

        return .{
            // zig fmt: off
            .{.x =     top_left[0], .y =     top_left[1], .color = self.color, .u = 0x0000, .v = 0x0000 },
            .{.x = bottom_right[0], .y =     top_left[1], .color = self.color, .u = 0xFFFF, .v = 0x0000 },
            .{.x = bottom_right[0], .y = bottom_right[1], .color = self.color, .u = 0xFFFF, .v = 0xFFFF },
            .{.x =     top_left[0], .y = bottom_right[1], .color = self.color, .u = 0x0000, .v = 0xFFFF },
            // zig fmt: on
        };
    }
};

pub const ScreenSize = .{ 1280, 720 };

pub fn main(init: std.process.Init) !void {
    {
        const value_v3: vec3 = .{ 100, 0, 1 };

        const scale: mat3 = .{
            .{ 2 / 320, 0, 1 },
            .{ 0, -2 / 240, -1 },
            .{ 0, 0, 1 },
        };

        // const translate: mat3 = .{
        //     .{ 1, 0, 0 },
        //     .{ 0, 1, 0 },
        //     .{ 0, 0, 1 },
        // };

        log.debug("{any} -> {any}!", .{ value_v3, la.transform(value_v3, scale) });

        // unreachable;
    }

    gpa = init.gpa;
    io = init.io;
    sapp.run(.{
        .init_cb = onInit,
        .frame_cb = onFrame,
        .cleanup_cb = onCleanup,
        .width = ScreenSize[0],
        .height = ScreenSize[1],
        .icon = .{ .sokol_default = true },
        .depth_format = .NONE,
        .window_title = "The Discharge of Captain Volt",
        .logger = .{ .func = util.loggerFunction },
        .win32 = .{ .console_attach = true },
        .swap_interval = 1,
    });
}

fn generalScreenWithBlinkingPrompt(
    zoomed_screen_width: f32,
    zoomed_screen_height: f32,
    top_text: [*c]const u8,
    blinking_text: [*c]const u8,
    top_font_size: c_int,
) !void {
    const padding = 4;
    const top_font_size_f: f32 = @floatFromInt(top_font_size);
    {
        const width: f32 = @floatFromInt(rl.MeasureText(top_text, top_font_size));
        rl.DrawText(
            top_text,
            @intFromFloat((zoomed_screen_width - width) * 0.5),
            @intFromFloat((zoomed_screen_height - top_font_size_f) * 0.5),
            top_font_size,
            rl.RAYWHITE,
        );
    }
    if (@mod(@trunc(rl.GetTime() / 0.6), 2) > 0) {
        const font_size = 20;
        const width: f32 = @floatFromInt(rl.MeasureText(blinking_text, font_size));
        rl.DrawText(
            blinking_text,
            @intFromFloat((zoomed_screen_width - width) * 0.5),
            @intFromFloat((zoomed_screen_height - top_font_size_f) * 0.5 + top_font_size_f + padding),
            font_size,
            rl.RAYWHITE,
        );
    }

    {
        const score_font_size = 16;
        const score_padding = 4;
        const text = try std.fmt.allocPrintSentinel(
            frame_allocator,
            "hi-score {d}",
            .{hi_score},
            0,
        );
        const width: f32 = @floatFromInt(rl.MeasureText(text, score_font_size));
        rl.DrawText(
            text.ptr,
            @intFromFloat((zoomed_screen_width - width) * 0.5),
            @intFromFloat(score_padding),
            score_font_size,
            rl.RAYWHITE,
        );
    }
}

var iframe_blink: bool = true; //TODO: Use c.GetTime

var hi_score: u32 = 0;

const HiScoreFile = "hiscore.dat";

fn loadHiScore(allocator: std.mem.Allocator) u32 {
    const hi_score_data_maybe = util.readEntireFileAlloc(".", HiScoreFile, allocator, io);

    if (hi_score_data_maybe) |hi_score_data| {
        defer allocator.free(hi_score_data);
        if (hi_score_data.len == @sizeOf(u32)) {
            const p = @as(*align(1) const u32, @ptrCast(hi_score_data));
            const result = p.*;
            return result;
        }
    } else |err| {
        log.debug(
            "{s} was not loaded because of [{any}], but it was probably OK.",
            .{ HiScoreFile, err },
        );
    }

    return 0;
}

fn saveHiScore() !void {
    var d = try std.Io.Dir.cwd().openDir(io, ".", .{});
    defer d.close(io);

    var f = try d.createFile(io, HiScoreFile, .{ .truncate = true });
    defer f.close(io);

    var buffer: [8]u8 = undefined;
    var r = f.writer(io, buffer[0..]);

    try r.interface.writeInt(u32, hi_score, .little);
}

const std = @import("std");
const assert = std.debug.assert;
const log = std.log;
const BuildMode = @import("builtin").mode;

const shader_sprite2d = @import("shader_sprite2d");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;

const AudioManager = @import("AudioManager.zig");
const EntityManager = @import("entity.zig").EntityManager;
const GigaEntity = @import("entity.zig").GigaEntity;
const GlobalConfig = @import("GlobalConfig.zig");
const la = @import("linalg.zig");
const vec2 = la.vec2;
const mat2 = la.mat2;
const vec3 = la.vec3;
const mat3 = la.mat3;
const rl = @import("raylib_stub.zig");
const SpriteManager = @import("SpriteManager.zig");
const Sprite = SpriteManager.Sprite;
const SpriteHandle = SpriteManager.SpriteHandle;
const util = @import("util.zig");
