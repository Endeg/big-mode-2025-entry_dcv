const GfxVulkan = @This();

instance: vk.InstanceProxy = undefined,
debug_messenger: vk.DebugUtilsMessengerEXT = undefined,
surface: vk.SurfaceKHR = undefined,
device: vk.DeviceProxy = undefined,

queue: struct {
    graphics: vk.Queue,
    present: vk.Queue,
} = undefined,

memory_properties: vk.PhysicalDeviceMemoryProperties = undefined,
swap_chain: vk.SwapchainKHR = undefined,
swap_chain_extent: vk.Extent2D = undefined,
swap_chain_images: [2]vk.Image = undefined,
swap_chain_image_views: [2]vk.ImageView = undefined,
swap_chain_format: vk.Format = undefined,

intermediate: struct {
    vkb: vk.BaseWrapper,
    vki: vk.InstanceWrapper,
    device_wrapper: vk.DeviceWrapper,
} = undefined,

const Self = @This();

const RequiredLayers = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
};

pub fn init(self: *Self, arena: std.mem.Allocator, window: *glfw.Window) !void {
    self.intermediate.vkb = vk.BaseWrapper.load(glfw.getInstanceProcAddress);

    const available_layers = (try self.intermediate.vkb.enumerateInstanceLayerPropertiesAlloc(arena));

    if (false) {
        for (available_layers, 0..) |layer, i| {
            const impl_ver: vk.Version = @bitCast(layer.implementation_version);
            const spec_ver: vk.Version = @bitCast(layer.spec_version);
            log.debug("{d: >2}. {s}: {s} (versions - impl {d}.{d}.{d}.{d}, spec {d}.{d}.{d}.{d}).", .{ i, layer.layer_name, layer.description, impl_ver.variant, impl_ver.major, impl_ver.minor, impl_ver.patch, spec_ver.variant, spec_ver.major, spec_ver.minor, spec_ver.patch });
        }
    }

    var layer_map: std.StringHashMapUnmanaged(void) = .empty;
    try layer_map.ensureTotalCapacity(arena, @intCast(available_layers.len));
    for (available_layers) |layer| {
        layer_map.putAssumeCapacity(try arena.dupe(u8, std.mem.sliceTo(&layer.layer_name, 0)), void{});
    }

    inline for (RequiredLayers) |requied_layer| {
        if (!layer_map.contains(std.mem.span(requied_layer))) {
            log.err("Missing required layer: {s}!", .{requied_layer});
            unreachable;
        }
    }

    var extension_names: std.ArrayListUnmanaged([*:0]const u8) = .empty;
    const glfw_exts = try glfw.getRequiredInstanceExtensions();
    try extension_names.ensureTotalCapacity(arena, glfw_exts.len + 3);

    extension_names.appendAssumeCapacity(vk.extensions.ext_debug_utils.name);
    if (builtin.os.tag == .macos) {
        // the following extensions are to support vulkan in mac os
        // see https://github.com/glfw/glfw/issues/2335
        extension_names.appendAssumeCapacity(vk.extensions.khr_portability_enumeration.name);
        extension_names.appendAssumeCapacity(vk.extensions
            .khr_get_physical_device_properties_2.name);
    }
    extension_names.appendSliceAssumeCapacity(glfw_exts);

    for (extension_names.items) |requested_extension| {
        log.debug("Requested extension: `{s}`.", .{requested_extension});
    }

    const debug_messenger_info: vk.DebugUtilsMessengerCreateInfoEXT = .{
        .message_severity = .{
            // .verbose_bit_ext = true,
            // .info_bit_ext = true,
            .warning_bit_ext = true,
            .error_bit_ext = true,
        },
        .message_type = .{
            .general_bit_ext = true,
            .validation_bit_ext = true,
            .performance_bit_ext = true,
        },
        .pfn_user_callback = &debugUtilsMessengerCallback,
        .p_user_data = null,
    };

    {
        // Making instance handle visible only in this scope
        const instance = try self.intermediate.vkb.createInstance(&.{
            .p_application_info = &.{
                .p_application_name = "CaptainVolt",
                .application_version = vk.makeApiVersion(0, 0, 0, 0).toU32(),
                .p_engine_name = "CaptainVolt",
                .engine_version = vk.makeApiVersion(0, 0, 0, 0).toU32(),
                .api_version = vk.API_VERSION_1_3.toU32(),
            },
            .enabled_layer_count = RequiredLayers.len,
            .pp_enabled_layer_names = @ptrCast(&RequiredLayers),
            .enabled_extension_count = @intCast(extension_names.items.len),
            .pp_enabled_extension_names = extension_names.items.ptr,
            .flags = .{
                // enumerate_portability_bit_khr to support vulkan in mac os
                // see https://github.com/glfw/glfw/issues/2335
                .enumerate_portability_bit_khr = builtin.os.tag == .macos,
            },
            .p_next = &debug_messenger_info,
        }, null);

        self.intermediate.vki = vk.InstanceWrapper.load(instance, self.intermediate.vkb.dispatch.vkGetInstanceProcAddr.?);
        self.instance = vk.InstanceProxy.init(instance, &self.intermediate.vki);

        self.debug_messenger = try self.instance.createDebugUtilsMessengerEXT(&debug_messenger_info, null);

        try glfw.createWindowSurface(instance, window, null, &self.surface);
    }

    const physical_devices = try self.instance.enumeratePhysicalDevicesAlloc(arena);

    for (physical_devices, 0..) |physical_device, i| {
        const device_properties = self.instance.getPhysicalDeviceProperties(physical_device);

        log.debug(
            "{d: >1}. {s} - {s}.",
            .{ i, @tagName(device_properties.device_type), device_properties.device_name },
        );
    }

    assert(physical_devices.len == 1); // TODO: Proper device select
    const physical_device = physical_devices[0];
    const candidate_device_properties = self.instance.getPhysicalDeviceProperties(physical_device);
    _ = candidate_device_properties; // autofix

    const queue_families = try self.instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(physical_device, arena);

    var graphics_queue_index: u32 = undefined;
    var present_queue_index: u32 = undefined;

    graphics_queue_index, present_queue_index = blk: {
        var found_graphics_queue_handle: ?u32 = null;
        var found_present_queue_handle: ?u32 = null;

        for (queue_families, 0..) |queue_family, i| {
            const queue_family_index: u32 = @intCast(i);
            if (found_graphics_queue_handle == null and queue_family.queue_flags.graphics_bit) {
                found_graphics_queue_handle = queue_family_index;
            }
            if (found_present_queue_handle == null and (try self.instance.getPhysicalDeviceSurfaceSupportKHR(physical_device, @intCast(i), self.surface)) == .true) {
                found_present_queue_handle = queue_family_index;
            }
        }

        break :blk .{ found_graphics_queue_handle.?, found_present_queue_handle.? };
    };

    log.debug("Queue indices graphics/queue: {d}/{d}.", .{ graphics_queue_index, present_queue_index });

    {
        const priority = [_]f32{1};
        _ = priority; // autofix
        const qci = [_]vk.DeviceQueueCreateInfo{
            .{
                .queue_family_index = graphics_queue_index,
                .queue_count = 1,
                .p_queue_priorities = &.{1},
            },
            .{
                .queue_family_index = present_queue_index,
                .queue_count = 1,
                .p_queue_priorities = &.{1},
            },
        };

        const queue_count: u32 = if (graphics_queue_index == present_queue_index) 1 else 2;

        const RequiredDeviceExtensions = [_][*:0]const u8{vk.extensions.khr_swapchain.name};

        const device = try self.instance.createDevice(physical_device, &.{
            .queue_create_info_count = queue_count,
            .p_queue_create_infos = &qci,
            .enabled_extension_count = RequiredDeviceExtensions.len,
            .pp_enabled_extension_names = @ptrCast(&RequiredDeviceExtensions),
            .enabled_layer_count = RequiredLayers.len,
            .pp_enabled_layer_names = @ptrCast(&RequiredLayers),
        }, null);

        self.intermediate.device_wrapper = vk.DeviceWrapper.load(device, self.instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
        self.device = vk.DeviceProxy.init(device, &self.intermediate.device_wrapper);
    }

    self.queue.graphics = self.device.getDeviceQueue(graphics_queue_index, 0);
    self.queue.present = self.device.getDeviceQueue(present_queue_index, 0);

    log.debug("queue handles: {any}.", .{self.queue});

    self.memory_properties = self.instance.getPhysicalDeviceMemoryProperties(physical_device);

    {
        const surface_capabilities = try self.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, self.surface);
        log.debug("surface_capabilities.current_extent = {any}.", .{surface_capabilities.current_extent});
        log.debug("surface_capabilities.min_image_extent = {any}.", .{surface_capabilities.min_image_extent});
        log.debug("surface_capabilities.max_image_extent = {any}.", .{surface_capabilities.max_image_extent});

        log.debug("swap chain image counts min/max= {d}/{d}.", .{
            surface_capabilities.min_image_count,
            surface_capabilities.max_image_count,
        });

        if (surface_capabilities.current_extent.width != 0xFFFFFFFF) {
            self.swap_chain_extent = surface_capabilities.current_extent;
        } else {
            self.swap_chain_extent = blk: {
                var w: c_int = undefined;
                var h: c_int = undefined;
                w, h = window.getFramebufferSize();
                break :blk .{ .width = @intCast(w), .height = @intCast(h) };
            };
            self.swap_chain_extent.width = std.math.clamp(
                self.swap_chain_extent.width,
                surface_capabilities.min_image_extent.width,
                surface_capabilities.max_image_extent.width,
            );
            self.swap_chain_extent.height = std.math.clamp(
                self.swap_chain_extent.height,
                surface_capabilities.min_image_extent.height,
                surface_capabilities.max_image_extent.height,
            );
        }

        log.debug("swap_extent = {any}.", .{self.swap_chain_extent});

        const surface_formats = try self.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(physical_device, self.surface, arena);
        log.debug("surface_formats:", .{});
        var format_ok: bool = false;
        for (surface_formats, 0..) |surface_format, i| {
            log.debug("{d: >1}. {any}.", .{ i, surface_format });
            if (!format_ok and surface_format.format == .b8g8r8a8_srgb and surface_format.color_space == .srgb_nonlinear_khr) {
                format_ok = true;
            }
        }
        assert(format_ok);

        const present_modes = try self.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(physical_device, self.surface, arena);
        log.debug("present_modes:", .{});
        var present_mode_ok: bool = false;
        for (present_modes, 0..) |present_mode, i| {
            log.debug("{d: >1}. {any}.", .{ i, present_mode });
            if (!present_mode_ok and present_mode == .fifo_khr) {
                present_mode_ok = true;
            }
        }
        assert(present_mode_ok);

        const target_swap_chain_format: vk.Format = .b8g8r8a8_srgb;

        self.swap_chain = try self.device.createSwapchainKHR(&.{
            .surface = self.surface,
            .min_image_count = surface_capabilities.min_image_count,
            .image_format = target_swap_chain_format,
            .image_color_space = .srgb_nonlinear_khr,
            .image_extent = self.swap_chain_extent,
            .image_array_layers = 1,
            .image_usage = .{ .color_attachment_bit = true },
            .pre_transform = surface_capabilities.current_transform,
            .composite_alpha = .{ .opaque_bit_khr = true },
            .clipped = .true,
            .present_mode = .fifo_khr,
            .old_swapchain = .null_handle,
            // TODO: Queue families sure is the chore to setup!
            .image_sharing_mode = if (self.queue.graphics == self.queue.present) .exclusive else .concurrent,
            .queue_family_index_count = if (self.queue.graphics == self.queue.present) 0 else 2,
            .p_queue_family_indices = if (self.queue.graphics == self.queue.present) null else &.{ 0, 0 },
        }, null);

        const swap_chain_images = try self.device.getSwapchainImagesAllocKHR(self.swap_chain, arena);
        assert(swap_chain_images.len == self.swap_chain_images.len);
        std.mem.copyForwards(vk.Image, self.swap_chain_images[0..], swap_chain_images);
        self.swap_chain_format = target_swap_chain_format;
        for (self.swap_chain_images, 0..) |img, i| {
            self.swap_chain_image_views[i] = try self.device.createImageView(&.{
                // .flags = ?,
                .image = img,
                .view_type = .@"2d",
                .format = target_swap_chain_format,
                .components = .{
                    .r = .identity,
                    .g = .identity,
                    .b = .identity,
                    .a = .identity,
                },
                .subresource_range = .{
                    .aspect_mask = .{ .color_bit = true },
                    .base_mip_level = 0,
                    .level_count = 1,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
            }, null);
        }
    }
}

pub fn deinit(self: *Self) void {
    for (self.swap_chain_image_views) |img_view| {
        self.device.destroyImageView(img_view, null);
    }
    self.device.destroySwapchainKHR(self.swap_chain, null);
    self.device.destroyDevice(null);
    self.instance.destroySurfaceKHR(self.surface, null);
    self.instance.destroyDebugUtilsMessengerEXT(self.debug_messenger, null);
    self.instance.destroyInstance(null);
}

fn debugUtilsMessengerCallback(severity: vk.DebugUtilsMessageSeverityFlagsEXT, msg_type: vk.DebugUtilsMessageTypeFlagsEXT, callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, _: ?*anyopaque) callconv(.c) vk.Bool32 {
    const log_level: ?log.Level = if (severity.verbose_bit_ext) .debug else if (severity.info_bit_ext) .info else if (severity.warning_bit_ext) .warn else if (severity.error_bit_ext) .err else null;

    const type_str = if (msg_type.general_bit_ext) "general" else if (msg_type.validation_bit_ext) "validation" else if (msg_type.performance_bit_ext) "performance" else if (msg_type.device_address_binding_bit_ext) "device addr" else "unknown";

    const message: [*c]const u8 = if (callback_data) |cb_data| cb_data.p_message else "NO MESSAGE!";

    if (log_level) |level| {
        switch (level) {
            .debug => log.debug("[{s}] {s}.", .{ type_str, message }),
            .info => log.info("[{s}] {s}.", .{ type_str, message }),
            .warn => log.warn("[{s}] {s}.", .{ type_str, message }),
            .err => log.err("[{s}] {s}.", .{ type_str, message }),
        }
    } else {
        log.info("[unknown][{s}] {s}.", .{ type_str, message });
    }

    return .false;
}

const std = @import("std");
const assert = std.debug.assert;
const log = std.log;

const glfw = @import("zglfw");
const vk = @import("vulkan");

const builtin = @import("builtin");
