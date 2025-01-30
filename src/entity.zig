const std = @import("std");
const assert = std.debug.assert;
const log = std.log;

const c = @import("c.zig");

pub const GigaEntity = struct {
    handle: EntityManager.Handle = undefined,
    flags: Flags = undefined,

    position: c.Vector2 = .{},
    acceleration: c.Vector2 = .{},
    velocity: c.Vector2 = .{},
    health: i8 = 5,
    iframes: f32 = 0,

    shoot_info: ShootInfo = .{},
    ttl: f32 = 0,
    enemy_behavior: EnemyBehavior = .{},

    tint: c.Color = undefined,
    damage_animation: f32 = 0,
    layer: Layer = .Sprites,

    hop_value: f32 = 0,
    above_ground_value: f32 = 0,

    const Class = enum(u2) {
        Player,
        Battery,
        Projectile,
        Supostat,
    };

    const Flags = packed struct(u8) {
        class: Class,
        moving: bool = false,
        visual: bool = false,
        collideable: bool = false,
        alive: bool = true,
        pad: u2 = 0,
    };

    const EnemyBehavior = struct {
        time_to_next: f32 = 0.0,
        commit_to_direction: c.Vector2 = .{},
        mode: Mode = .Loiter,

        const Mode = enum {
            Loiter,
            Pursuit,
            Avoid,
        };
    };

    const ShootInfo = struct {
        direction: c.Vector2 = .{},
        cooldown: f32 = 0,
    };

    pub const Layer = enum(u2) {
        //Background,
        Sprites,
        MoreSprites,
        Foreground,
    };

    const Self = @This();

    pub fn player(position: c.Vector2) Self {
        return .{
            .flags = .{
                .class = .Player,
                .moving = true,
                .visual = true,
                .collideable = true,
            },
            .position = position,
            .tint = c.GREEN,
            .layer = .MoreSprites,
        };
    }

    pub fn battery(position: c.Vector2) Self {
        return .{
            .flags = .{
                .class = .Battery,
                .moving = true,
                .visual = true,
                .collideable = true,
            },
            .position = position,
            .tint = c.VIOLET,
        };
    }

    pub fn projectile(position: c.Vector2, acceleration: c.Vector2, ttl: f32) Self {
        return .{
            .flags = .{
                .class = .Projectile,
                .moving = true,
                .visual = true,
                .collideable = true,
            },
            .position = position,
            .acceleration = acceleration,
            .velocity = acceleration,
            .ttl = ttl,
            .tint = c.YELLOW,
            .layer = .MoreSprites,
        };
    }

    pub fn supostat(position: c.Vector2, rng: std.Random) Self {
        const GreenHueStart: f32 = 90 + 30;
        const GreenHueEnd: f32 = 150 - 30;
        const AllHue: f32 = 360;

        var hsv = c.ColorToHSV(c.MAROON);
        hsv.x = if (rng.boolean()) rng.float(f32) * GreenHueStart else GreenHueEnd + (rng.float(f32) * (AllHue - GreenHueEnd));

        const shifted_tint = c.ColorFromHSV(hsv.x, hsv.y, hsv.z);

        return .{
            .flags = .{
                .class = .Supostat,
                .moving = true,
                .visual = true,
                .collideable = true,
            },
            .position = position,
            .tint = shifted_tint,
            .layer = .MoreSprites,
        };
    }
};

pub const EntityManager = struct {
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
