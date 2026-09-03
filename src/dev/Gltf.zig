const Gltf = @This();

var cache: std.AutoHashMapUnmanaged(FileCache.FileLocationHandle, Gltf) = .empty;
var arena: std.heap.ArenaAllocator = undefined;

model: Model,
buffers: [][]const u8,

pub fn init(allocator: std.mem.Allocator) !void {
    arena = .init(allocator);
    const MaxEntries = 32 * 1024;
    try cache.ensureTotalCapacity(arena.allocator(), MaxEntries);
}

pub fn deinit() void {
    arena.deinit();
}

fn readStruct(T: type, buffer: []const u8, pos: *usize) *const T {
    defer pos.* += @sizeOf(T);
    return @alignCast(std.mem.bytesAsValue(T, buffer[pos.*..]));
}

fn readSlice(buffer: []const u8, size: usize, pos: *usize) []const u8 {
    defer pos.* += size;
    return @alignCast(buffer[pos.* .. pos.* + size]);
}

fn parse(data: []const u8, allocator: std.mem.Allocator) !Gltf {
    const parsed = try std.json.parseFromSlice(
        Model,
        allocator,
        data,
        .{ .ignore_unknown_fields = true },
    );

    return .{
        .model = parsed.value,
        .buffers = try allocator.alloc([]const u8, parsed.value.buffers.len),
    };
}

pub fn get(file_name: []const u8, file_cache: *FileCache) !Gltf {
    if (file_cache.getHandle(file_name)) |handle| {
        if (cache.get(handle)) |gltf| {
            return gltf;
        } else {
            const loaded = file_cache.get(file_name);

            if (loaded.len == 0) {
                return GltfError.GltfFileNotFound;
            }
            const gltf = try load(loaded, file_cache, arena.allocator());
            cache.putAssumeCapacityNoClobber(handle, gltf);
            return gltf;
        }
    } else {
        const loaded = file_cache.get(file_name);

        if (loaded.len == 0) {
            return GltfError.GltfFileNotFound;
        }
        const gltf = try load(loaded, file_cache, arena.allocator());
        const handle = file_cache.getHandle(file_name).?;
        cache.putAssumeCapacityNoClobber(handle, gltf);
        return gltf;
    }
}

fn load(data: []const u8, file_cache: *FileCache, allocator: std.mem.Allocator) !Gltf {
    switch (detectFormat(data)) {
        .Text => {
            var result = try parse(data, allocator);

            for (result.buffers, 0..) |_, i| {
                result.buffers[i] = file_cache.get(result.model.buffers[i].uri);
            }

            return result;
        },
        .Binary => {
            var pos: usize = 0;

            const header = readStruct(GlbHeader, data, &pos);
            assert(header.length == data.len);
            std.log.debug("header = {any}.", .{header});

            var result_optional: ?Gltf = null;

            while (pos < data.len) {
                const chunk = readStruct(GlbChunk, data, &pos);
                const chunk_payload = readSlice(data, chunk.length, &pos);

                switch (chunk.type) {
                    .Json => {
                        result_optional = try parse(chunk_payload, allocator);
                    },
                    .Bin => {
                        if (result_optional) |*gltf| {
                            gltf.buffers[0] = chunk_payload;
                        }
                    },
                }
            }

            if (result_optional) |*result| {
                for (result.buffers, 0..) |_, i| {
                    if (result.model.buffers[i].uri.len > 0) {
                        result.buffers[i] = file_cache.get(result.model.buffers[i].uri);
                    }
                }
                return result.*;
            } else {
                return GltfError.GlbProblem;
            }
        },
    }
}

fn detectFormat(data: []const u8) Format {
    const header = std.mem.bytesAsValue(GlbHeader, data);
    if (header.magic == 0x46546C67) {
        return .Binary;
    } else {
        return .Text;
    }
}

pub const Format = enum {
    Text,
    Binary,
};

const GlbHeader = extern struct {
    magic: u32,
    version: u32,
    length: u32,

    comptime {
        if (@sizeOf(GlbHeader) != 3 * @sizeOf(u32)) {
            @compileError("GlbHeader size problem!");
        }
    }
};

const GlbChunk = extern struct {
    length: u32,
    type: Type,

    const Type = enum(u32) {
        Json = 0x4E4F534A,
        Bin = 0x004E4942,
    };

    comptime {
        if (@sizeOf(GlbChunk) != 2 * @sizeOf(u32)) {
            @compileError("GlbChunk size problem!");
        }
    }
};

fn getIndices(self: Gltf, accessor_index: AccessorIndex) MeshPrimitive.Indices {
    const index_accessor = self.model.accessors[@intFromEnum(accessor_index)];

    assert(index_accessor.type == .SCALAR);
    assert(index_accessor.componentType == .U16 or index_accessor.componentType == .U32);

    const index_buffer_view = self.model.bufferViews[@intFromEnum(index_accessor.bufferView)];
    if (index_buffer_view.target) |target| {
        assert(target == .ElementArrayBuffer);
    }

    const buffer = self.buffers[@intFromEnum(index_buffer_view.buffer)];

    const data = buffer[index_buffer_view.byteOffset .. index_buffer_view.byteOffset + index_buffer_view.byteLength];

    const indices: MeshPrimitive.Indices = switch (index_accessor.componentType) {
        .U16 => MeshPrimitive.Indices{ .u16 = @alignCast(std.mem.bytesAsSlice(u16, data)) },
        .U32 => MeshPrimitive.Indices{ .u32 = @alignCast(std.mem.bytesAsSlice(u32, data)) },
        else => {
            std.log.err("Wrong component type for index: {s}!", .{@tagName(index_accessor.componentType)});
            unreachable;
        },
    };

    switch (indices) {
        .u16 => |ind| assert(ind.len == index_accessor.count),
        .u32 => |ind| assert(ind.len == index_accessor.count),
    }

    return indices;
}

const AttributeInfo = struct {
    T: type,
    AccessorType: Model.Accessor.Type,
};

const AttributeTypes = std.EnumArray(Model.Mesh.Primitive.Attribute, AttributeInfo).init(.{
    .POSITION = AttributeInfo{ .T = rl.Vector3, .AccessorType = .VEC3 },
    .NORMAL = AttributeInfo{ .T = rl.Vector3, .AccessorType = .VEC3 },
    .TEXCOORD_0 = AttributeInfo{ .T = rl.Vector2, .AccessorType = .VEC2 },
    .COLOR_0 = AttributeInfo{ .T = rl.Vector4, .AccessorType = .VEC4 },
});

fn getAttribute(self: Gltf, comptime attribute: Model.Mesh.Primitive.Attribute, accessor_index: AccessorIndex) []const AttributeTypes.get(attribute).T {
    const attr_accessor = self.model.accessors[@intFromEnum(accessor_index)];
    assert(attr_accessor.type == AttributeTypes.get(attribute).AccessorType);
    assert(attr_accessor.componentType == .F32);

    const buffer_view = self.model.bufferViews[@intFromEnum(attr_accessor.bufferView)];
    if (buffer_view.target) |target| {
        assert(target == .ArrayBuffer);
    }

    const buffer = self.buffers[@intFromEnum(buffer_view.buffer)];

    const data = buffer[buffer_view.byteOffset .. buffer_view.byteOffset + buffer_view.byteLength];

    const typed_data: []const AttributeTypes.get(attribute).T = @alignCast(std.mem.bytesAsSlice(AttributeTypes.get(attribute).T, data));
    assert(typed_data.len == attr_accessor.count);
    return typed_data;
}

pub fn meshPrimitive(self: Gltf, mesh_index: MeshIndex, primitive_index: PrimitiveIndex) MeshPrimitive {
    const mesh = self.model.meshes[@intFromEnum(mesh_index)];
    const primitive = mesh.primitives[@intFromEnum(primitive_index)];

    return .{
        .indices = self.getIndices(primitive.indices),
        .position = if (primitive.attributes.POSITION) |pos| self.getAttribute(.POSITION, pos) else null,
        .normal = if (primitive.attributes.NORMAL) |norm| self.getAttribute(.NORMAL, norm) else null,
        .texcoord_0 = if (primitive.attributes.TEXCOORD_0) |uv_0| self.getAttribute(.TEXCOORD_0, uv_0) else null,
        .color_0 = if (primitive.attributes.COLOR_0) |color_0| self.getAttribute(.COLOR_0, color_0) else null,
    };
}

const MeshPrimitive = struct {
    indices: Indices,
    position: ?[]const rl.Vector3,
    normal: ?[]const rl.Vector3,
    texcoord_0: ?[]const rl.Vector2,
    color_0: ?[]const rl.Vector4,

    const Indices = union(Tag) {
        u16: []const u16,
        u32: []const u32,

        const Tag = enum { u16, u32 };

        pub fn get(self: Indices, index: usize) u32 {
            return switch (self) {
                .u16 => |ind| ind[index],
                .u32 => |ind| ind[index],
            };
        }

        pub fn count(self: Indices) u32 {
            return switch (self) {
                .u16 => |ind| @intCast(ind.len),
                .u32 => |ind| @intCast(ind.len),
            };
        }
    };
};

const MeshIndex = enum(usize) { _ };
const PrimitiveIndex = enum(usize) { _ };
const AccessorIndex = enum(usize) { _ };
const BufferViewIndex = enum(usize) { _ };
const BufferIndex = enum(usize) { _ };

const Model = struct {
    scene: usize,
    scenes: []Scene = &.{},
    nodes: []Node = &.{},
    animations: []Animation = &.{},
    meshes: []Mesh = &.{},
    accessors: []Accessor = &.{},
    bufferViews: []BufferView = &.{},
    buffers: []Buffer = &.{},
    textures: []Texture = &.{},
    images: []Image = &.{},
    samplers: []TextureSampler = &.{},
    materials: []Material = &.{},

    const Scene = struct {
        name: []const u8 = &.{},
        nodes: []usize = &.{},
    };

    pub const Node = struct {
        name: []const u8 = &.{},
        mesh: ?MeshIndex = null,
        children: []usize = &.{},
        matrix: ?[4 * 4]f32 = null,
        translation: ?[3]f32 = null,
        rotation: ?[4]f32 = null,
        scale: ?[3]f32 = null,
    };

    const Animation = struct {
        name: []const u8 = &.{},
        channels: []Channel = &.{},
        samplers: []AnimationSampler = &.{},

        const Channel = struct {
            sampler: usize,
            target: Target,

            const Target = struct {
                node: usize,
                path: PathType,

                const PathType = enum {
                    translation,
                    rotation,
                    scale,
                };
            };
        };

        const AnimationSampler = struct {
            input: usize,
            interpolation: InterpolationType,
            output: usize,
            const InterpolationType = enum {
                LINEAR,
                STEP,
            };
        };
    };

    pub const Mesh = struct {
        name: []const u8,
        primitives: []Primitive = &.{},

        pub const Primitive = struct {
            attributes: Attributes,
            indices: AccessorIndex,
            mode: Mode = .Triangles,
            material: ?usize = null,

            const Attribute = std.meta.FieldEnum(Attributes);

            pub const Attributes = struct {
                POSITION: ?AccessorIndex = null,
                NORMAL: ?AccessorIndex = null,
                TEXCOORD_0: ?AccessorIndex = null,
                COLOR_0: ?AccessorIndex = null,
            };

            const Mode = enum(u8) {
                Points = 0,
                Lines = 1,
                LineLoop = 2,
                LineStrip = 3,
                Triangles = 4,
                TriangleStrip = 5,
                TriangleFan = 6,
            };
        };
    };

    pub const Accessor = struct {
        bufferView: BufferViewIndex,
        componentType: ComponentType,
        count: usize,
        type: Type,

        pub const ComponentType = enum(u16) {
            S8 = 5120,
            U8 = 5121,
            S16 = 5122,
            U16 = 5123,
            U32 = 5125,
            F32 = 5126,
        };
        pub const Type = enum { SCALAR, VEC2, VEC3, VEC4, MAT2, MAT3, MAT4 };
    };

    const BufferView = struct {
        buffer: BufferIndex,
        byteLength: usize,
        byteOffset: usize,
        target: ?Target = null,

        pub const Target = enum(u16) {
            ArrayBuffer = 34962,
            ElementArrayBuffer = 34963,
        };
    };

    const Buffer = struct {
        byteLength: usize,
        uri: []const u8 = &.{},
    };

    const Texture = struct {
        sampler: usize,
        source: usize,
    };

    const Image = struct {
        mimeType: ?[]const u8 = null,
        uri: ?[]const u8 = null,
        bufferView: ?usize = null,

        const ImageFormat = enum { Png, Jpeg };

        const MimeTypeToImageFormat = std.StaticStringMap(ImageFormat).initComptime(.{
            .{ "image/png", .Png },
            .{ "image/jpeg", .Jpeg },
        });

        const ImageFormatHeaders = mapImageFormatHeaders();

        fn mapImageFormatHeaders() std.EnumArray(ImageFormat, []const u8) {
            var result = std.EnumArray(ImageFormat, []const u8).initFill(&.{});
            result.set(.Png, &.{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A });
            result.set(.Jpeg, &.{ 0xFF, 0xD8, 0xFF });
            return result;
        }
    };

    const TextureSampler = struct {
        const MagFilter = enum(u16) {
            Nearest = 9728,
            Linear = 9729,
        };
        const MinFilter = enum(u16) {
            Nearest = 9728,
            Linear = 9729,
            NearestMipmapNearest = 9984,
            LinearMipmapNearest = 9985,
            NearestMipmapLinear = 9986,
            LinearMipmapLinear = 9987,
        };
    };

    const Material = struct {
        pbrMetallicRoughness: PbrMetallicRoughness,
        normalTexture: ?MaterialTexture = null,
        emissiveFactor: ?[3]f32 = null,

        const PbrMetallicRoughness = struct {
            baseColorFactor: ?[4]f32 = null,
            baseColorTexture: ?MaterialTexture = null,
            metallicFactor: ?f32 = null,
            roughnessFactor: ?f32 = null,
            metallicRoughnessTexture: ?MaterialTexture = null,
        };

        const MaterialTexture = struct {
            index: usize,
            texCoord: ?usize = null,
            scale: ?f32 = null,
        };
    };
};

const GltfError = error{
    GlbProblem,
    GltfFileNotFound,
};

const std = @import("std");
const assert = std.debug.assert;

const rl = @import("../raylib_stub.zig");

const FileCache = @import("FileCache.zig");
