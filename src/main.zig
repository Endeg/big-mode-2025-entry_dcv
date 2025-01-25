const std = @import("std");
const assert = std.debug.assert;
const log = std.log;

const c = @import("c.zig");

const util = @import("util.zig");

//TODO: GPA allocator: dupeZ/free - possible bug

// TODO: Audio assets - load/play
// TODO: json config with hot-reloading
// TODO: Main loop:
//         + 1. read input;
//         + 2. update game;
//         + 3. render
// TODO: Main game loop:
//         1. Pick battery by walking to it
//         2. Can't shoot while holding battery, when shoot - drops the battery.
//         3. Shooting by holding IJKL.
//         4. There's enemies. To simplify:
//              - semi-randomly walking to the player
//              - some can shoot
//         5. When all batteries collected - walk to the rocket, and go to next level.
// TODO: Juice:
//         1. Hop animation while walking.
//         2. Screen shake.
//         3. Audio.
//         4. Some fancy effects.
// TODO: Gamepad support

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

const GigaEntity = struct {
    handle: EntityManager.Handle = undefined,
    flags: Flags = undefined,

    position: c.Vector2 = undefined,
    acceleration: c.Vector2 = undefined,
    velocity: c.Vector2 = undefined,

    sprite_handle: SpriteManager.Handle = undefined,
    tint: c.Color = undefined,

    const Class = enum(u1) {
        Player,
        Battery,
    };

    const Flags = packed struct(u8) {
        class: Class,
        moving: bool = false,
        visual: bool = false,
        pad: u5 = 0,
    };

    const Self = @This();

    pub fn player(position: c.Vector2, sprite_handle: SpriteManager.Handle) Self {
        return .{
            .flags = .{ .class = .Player, .moving = true, .visual = true },
            .position = position,
            .acceleration = c.Vector2{},
            .velocity = c.Vector2{},
            .sprite_handle = sprite_handle,
            .tint = c.GREEN,
        };
    }

    pub fn battery(position: c.Vector2, sprite_handle: SpriteManager.Handle) Self {
        return .{
            .flags = .{ .class = .Battery, .moving = true, .visual = true },
            .position = position,
            .acceleration = c.Vector2{},
            .velocity = c.Vector2{},
            .sprite_handle = sprite_handle,
            .tint = c.VIOLET,
        };
    }
};

const EntityManager = struct {
    entities: EntitySOA,
    entity_index: std.AutoHashMapUnmanaged(Handle, usize),
    allocator: std.mem.Allocator,
    current_entity_counter: u16 = 0,

    const Self = @This();

    const MaxEntities = 16 * 1024;

    const EntitySOA = std.MultiArrayList(GigaEntity);

    const Handle = enum(u16) { _ };

    pub fn init(allocator: std.mem.Allocator) !Self {
        var entities = EntitySOA{};
        try entities.ensureUnusedCapacity(allocator, MaxEntities);

        var entity_index = std.AutoHashMapUnmanaged(Handle, usize){};
        try entity_index.ensureTotalCapacity(allocator, MaxEntities);

        return .{
            .entities = entities,
            .entity_index = entity_index,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.entities.deinit(self.allocator);
        self.entity_index.deinit(self.allocator);
    }

    pub fn createEntity(self: *Self, entity: GigaEntity) Handle {
        assert(self.entities.len == self.entity_index.count());

        const new_handle: Handle = @enumFromInt(self.current_entity_counter);
        defer self.current_entity_counter += 1;

        const entity_row = self.entities.len;

        self.entities.appendAssumeCapacity(entity);
        self.entities.items(.handle)[entity_row] = new_handle;
        self.entity_index.putAssumeCapacityNoClobber(new_handle, entity_row);

        // std.debug.print("[Entity Manager] new {any}.\n", .{new_handle});

        return new_handle;
    }

    pub fn entityField(self: *Self, handle: Handle, comptime field: EntitySOA.Field) ?*std.meta.FieldType(GigaEntity, field) {
        if (self.entity_index.get(handle)) |entity_row| {
            return &self.entities.items(field)[entity_row];
        } else {
            return null;
        }
    }

    pub fn removeEntity(self: *Self, handle: Handle) void {
        assert(self.entities.len == self.entity_index.count());

        if (self.entities.len == 0) {
            return;
        }

        //TODO: fetchRemove
        if (self.entity_index.get(handle)) |entity_row| {
            if (self.entities.len == 1) {
                // std.debug.print(
                //     "[Entity Manager] removing last {d}: {any}.\n",
                //     .{ 0, self.entities.items(.handle)[0] },
                // );
                self.entities.clearRetainingCapacity();
                self.entity_index.clearRetainingCapacity();
            } else {
                const not_last_row = entity_row != self.entities.len - 1;

                if (not_last_row) {
                    const handle_to_move = self.entities.items(.handle)[self.entities.len - 1];

                    // std.debug.print(
                    //     "[Entity Manager] removing {d}: {any}.\n",
                    //     .{ entity_row, self.entities.items(.handle)[entity_row] },
                    // );

                    // std.debug.print(
                    //     "[Entity Manager] moving {d} -> {d}: {any}.\n",
                    //     .{ self.entities.len - 1, entity_row, self.entities.items(.handle)[self.entities.len - 1] },
                    // );

                    self.entities.swapRemove(entity_row);
                    _ = self.entity_index.remove(handle);

                    self.entity_index.putAssumeCapacity(handle_to_move, entity_row);
                } else {
                    self.entities.len -= 1;
                    _ = self.entity_index.remove(handle);
                }
            }
            // std.debug.print(
            //     "[Entity Manager] stats entities {d}, entity index {d}.\n",
            //     .{ self.entities.len, self.entity_index.count() },
            // );
        }
    }
};

const Input = struct {
    dt: f32,
    up: bool = false,
    down: bool = false,
    left: bool = false,
    right: bool = false,
};

pub fn main() !void {
    c.InitWindow(1280, 720, "Unnamed Game Jam Entry");
    c.SetTargetFPS(60);

    var gpa = GPA{};

    var texture_manager = try TextureManager.init(gpa.allocator());
    var sprite_manager = try SpriteManager.init(&texture_manager, gpa.allocator());
    {
        const allocator = gpa.allocator();
        const sprites_json_content = try util.readEntireFileAlloc(".", "sprites.json", allocator);
        defer allocator.free(sprites_json_content);
        try sprite_manager.loadFromJson(sprites_json_content);
    }

    var entity_manager = try EntityManager.init(gpa.allocator());

    const player_sprite_handle = sprite_manager.find("main-guy").?;
    const battery_sprite_handle = sprite_manager.find("battery").?;

    const player_handle = entity_manager.createEntity(GigaEntity.player(.{ .x = 0, .y = 0 }, player_sprite_handle));

    var prng = std.Random.DefaultPrng.init(0x6969);
    var rng = prng.random();

    var batteries_count: i32 = 20;
    while (batteries_count >= 0) : (batteries_count -= 1) {
        //TODO: Battery creation function

        const BatteriseDistribution = 100;

        _ = entity_manager.createEntity(GigaEntity.battery(
            .{
                .x = rng.floatNorm(f32) * BatteriseDistribution - BatteriseDistribution * 0.5,
                .y = rng.floatNorm(f32) * BatteriseDistribution - BatteriseDistribution * 0.5,
            },
            battery_sprite_handle,
        ));
    }

    const screen_width: f32 = @floatFromInt(c.GetScreenWidth());
    const screen_height: f32 = @floatFromInt(c.GetScreenHeight());

    var camera = c.Camera2D{
        .offset = .{ .x = screen_width * 0.5, .y = screen_height * 0.5 },
        .rotation = 0,
        .target = .{ .x = 0, .y = 0 },
        .zoom = 3,
    };

    var frame_messages = try std.ArrayList([]const u8).initCapacity(gpa.allocator(), 128);
    const frame_memory = try gpa.allocator().alloc(u8, 1 * 1024 * 1024);

    var frame_fba = std.heap.FixedBufferAllocator.init(frame_memory);
    var frame_arena = std.heap.ArenaAllocator.init(frame_fba.allocator());
    const frame_allocator = frame_arena.allocator();

    while (!c.WindowShouldClose()) {
        frame_messages.clearRetainingCapacity();
        _ = frame_arena.reset(.retain_capacity);

        const input = Input{
            .dt = c.GetFrameTime(),
            .up = c.IsKeyDown(c.KEY_W),
            .down = c.IsKeyDown(c.KEY_S),
            .left = c.IsKeyDown(c.KEY_A),
            .right = c.IsKeyDown(c.KEY_D),
        };

        if (entity_manager.entityField(player_handle, .position)) |player_position| {
            camera.target = c.Vector2Lerp(camera.target, player_position.*, 0.05);
        }

        c.BeginDrawing();
        defer c.EndDrawing();

        c.BeginMode2D(camera);

        c.ClearBackground(c.BLACK);

        c.DrawLine(0, 700, 1280, 700, c.DARKBROWN);
        {
            var i: usize = 0;
            while (i < entity_manager.entities.len) : (i += 1) {
                const flags = entity_manager.entities.items(.flags);
                const position = entity_manager.entities.items(.position);
                const acceleration = entity_manager.entities.items(.acceleration);
                const velocity = entity_manager.entities.items(.velocity);
                const sprite_handle = entity_manager.entities.items(.sprite_handle);
                const tint = entity_manager.entities.items(.tint);

                //TODO: Move hot-reloaded json config
                const PlayerAccMagnitude: f32 = 200;
                const PlayerDamping: f32 = 0.8;
                const PlayerMaxVelocity: f32 = 100;
                const PlayerMass: f32 = 150;

                //TODO: Proper units: e.g. 16px - 1 meter or something.

                //TODO: Start extracting to functions.

                if (flags[i].class == .Player) {
                    acceleration[i] = .{};

                    if (input.left) {
                        acceleration[i].x = -1;
                    }
                    if (input.right) {
                        acceleration[i].x = 1;
                    }
                    if (input.up) {
                        acceleration[i].y = -1;
                    }
                    if (input.down) {
                        acceleration[i].y = 1;
                    }

                    acceleration[i] = c.Vector2Scale(c.Vector2Normalize(acceleration[i]), PlayerAccMagnitude);
                    //{[argument][specifier]:[fill][alignment][width].[precision]}`
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
                }

                if (flags[i].moving) {
                    if (c.Vector2Length(velocity[i]) > 0 and c.Vector2Length(acceleration[0]) > 0) {
                        // Decrease velocity if direction was changed
                        const vel_norm = c.Vector2Normalize(velocity[i]);
                        const acc_norm = c.Vector2Normalize(acceleration[i]);
                        const dot_product = c.Vector2DotProduct(vel_norm, acc_norm);
                        frame_messages.appendAssumeCapacity(try std.fmt.allocPrintZ(
                            frame_allocator,
                            "player.dot_product = {d:.4}.",
                            .{dot_product},
                        ));
                        if (dot_product < 0) {
                            velocity[i] = c.Vector2Subtract(velocity[i], c.Vector2Scale(velocity[i], (1 - PlayerDamping) * @abs(dot_product) * input.dt / PlayerMass));
                        }
                    }

                    // const vt = c.Vector2Scale(velocity[i], input.dt);
                    // const at = c.Vector2Scale(acceleration[i], input.dt * input.dt * 0.5);
                    // if (flags[i].class == .Player) {
                    //     frame_messages.appendAssumeCapacity(try std.fmt.allocPrintZ(
                    //         frame_allocator,
                    //         "player.vt = {d:.4}, {d:.4}.",
                    //         .{ vt.x, vt.y },
                    //     ));
                    //     frame_messages.appendAssumeCapacity(try std.fmt.allocPrintZ(
                    //         frame_allocator,
                    //         "player.at = {d:.4}, {d:.4}.",
                    //         .{ at.x, at.y },
                    //     ));
                    // }
                    // velocity[i] = c.Vector2Add(velocity[i], c.Vector2Add(vt, at));

                    velocity[i] = c.Vector2Add(velocity[i], c.Vector2Scale(acceleration[i], input.dt));

                    if (c.Vector2Length(acceleration[i]) == 0) {
                        velocity[i] = c.Vector2Scale(velocity[i], PlayerDamping);
                    }

                    velocity[i] = c.Vector2ClampValue(velocity[i], 0, PlayerMaxVelocity);

                    //accelerate and stuff!

                    position[i] = c.Vector2Add(position[i], c.Vector2Scale(velocity[i], input.dt));
                }

                if (flags[i].visual) {
                    const sprite = sprite_manager.get(sprite_handle[i]);
                    drawSprite(sprite, position[i], 0, tint[i], &texture_manager);
                }
            }
        }

        c.EndMode2D();

        c.DrawFPS(2, 2);

        for (frame_messages.items, 0..) |frame_message, i| {
            const index: c_int = @intCast(i);
            c.DrawText(frame_message.ptr, 2, 20 * (index + 1), 18, c.RAYWHITE);
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
