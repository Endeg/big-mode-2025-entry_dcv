const GfxVulkan = @This();

const SimpleVertexBinary = @embedFile("simple.vert.spv");
const SimpleFragmentBinary = @embedFile("simple.frag.spv");

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
swap_chain_framebuffers: [2]vk.Framebuffer = undefined,
swap_chain_image_views: [2]vk.ImageView = undefined,
swap_chain_format: vk.Format = undefined,
vert_shader_module: vk.ShaderModule = undefined,
frag_shader_module: vk.ShaderModule = undefined,
viewport: vk.Viewport = undefined,
scissor: vk.Rect2D = undefined,
pipeline_layout: vk.PipelineLayout = undefined,
render_pass: vk.RenderPass = undefined,
pipeline: vk.Pipeline = undefined,
command_pool: vk.CommandPool = undefined,
command_buffer: vk.CommandBuffer = undefined,
image_available_semaphore: vk.Semaphore = undefined,
render_finished_semaphore: vk.Semaphore = undefined,
in_flight_fence: vk.Fence = undefined,

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
    try extension_names.ensureTotalCapacity(arena, glfw_exts.len + 4);

    extension_names.appendAssumeCapacity(vk.extensions.ext_debug_utils.name);
    if (builtin.os.tag == .macos) {
        // the following extensions are to support vulkan in mac os
        // see https://github.com/glfw/glfw/issues/2335
        extension_names.appendAssumeCapacity(vk.extensions.khr_portability_enumeration.name);
        extension_names.appendAssumeCapacity(vk.extensions.khr_get_physical_device_properties_2.name);
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

        const RequiredDeviceExtensions = [_][*:0]const u8{
            vk.extensions.khr_swapchain.name,

            // TODO: fix error: [validation] vkCreateRenderPass():
            // pCreateInfo->pSubpasses[0].pColorAttachments[0] is VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL
            // (and synchronization2 was not enabled).
            // The Vulkan spec states: If the synchronization2 feature is not enabled, layout must
            // not be VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL_KHR or VK_IMAGE_LAYOUT_READ_ONLY_OPTIMAL_KHR
            // (https://vulkan.lunarg.com/doc/view/1.4.321.1/windows/antora/spec/latest/chapters/renderpass.html#VUID-VkAttachmentReference-synchronization2-06910).
            // Is this the one? Having this extension here doesn't help,
            // perhaps there's something else.
            vk.extensions.khr_synchronization_2.name,
        };

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

    self.vert_shader_module = try self.device.createShaderModule(&.{
        .code_size = SimpleVertexBinary.len,
        .p_code = @ptrCast(@alignCast(&SimpleVertexBinary[0])),
    }, null);

    self.frag_shader_module = try self.device.createShaderModule(&.{
        .code_size = SimpleFragmentBinary.len,
        .p_code = @ptrCast(@alignCast(&SimpleFragmentBinary[0])),
    }, null);

    {
        const vertex_shader_stage_info: vk.PipelineShaderStageCreateInfo = .{
            .stage = .{ .vertex_bit = true },
            .module = self.vert_shader_module,
            .p_name = "main",
        };
        const fragment_shader_stage_info: vk.PipelineShaderStageCreateInfo = .{
            .stage = .{ .fragment_bit = true },
            .module = self.frag_shader_module,
            .p_name = "main",
        };

        const shader_stages = .{ vertex_shader_stage_info, fragment_shader_stage_info };
        const dynamic_states = [_]vk.DynamicState{
            vk.DynamicState.viewport,
            vk.DynamicState.scissor,
        };
        const dynamic_state_info: vk.PipelineDynamicStateCreateInfo = .{
            .dynamic_state_count = dynamic_states.len,
            .p_dynamic_states = @ptrCast(&dynamic_states),
        };

        const vertex_input_info: vk.PipelineVertexInputStateCreateInfo = .{
            .vertex_binding_description_count = 0,
            .p_vertex_binding_descriptions = null,
            .vertex_attribute_description_count = 0,
            .p_vertex_attribute_descriptions = null,
        };

        const input_assembly: vk.PipelineInputAssemblyStateCreateInfo = .{
            .topology = .triangle_list,
            .primitive_restart_enable = .false,
        };

        self.viewport = .{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(self.swap_chain_extent.width),
            .height = @floatFromInt(self.swap_chain_extent.height),
            .min_depth = 0,
            .max_depth = 1,
        };

        self.scissor = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.swap_chain_extent,
        };

        const viewport_state_info: vk.PipelineViewportStateCreateInfo = .{
            .viewport_count = 1,
            .p_viewports = @ptrCast(&self.viewport),
            .scissor_count = 1,
            .p_scissors = @ptrCast(&self.scissor),
        };
        const rasterization_state_info: vk.PipelineRasterizationStateCreateInfo = .{
            .depth_clamp_enable = .false,
            .rasterizer_discard_enable = .false,
            .polygon_mode = .fill,
            .line_width = 1,
            .cull_mode = .{ .back_bit = true },
            .front_face = .clockwise,
            .depth_bias_enable = .false,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
        };

        const multisample_state_info: vk.PipelineMultisampleStateCreateInfo = .{
            .sample_shading_enable = .false,
            .rasterization_samples = .{ .@"1_bit" = true },
            .min_sample_shading = 1,
            .p_sample_mask = null,
            .alpha_to_coverage_enable = .false,
            .alpha_to_one_enable = .false,
        };

        const color_blend_attachment_state: vk.PipelineColorBlendAttachmentState = .{
            .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
            .blend_enable = .false,
            .src_color_blend_factor = .one,
            .dst_color_blend_factor = .zero,
            .color_blend_op = .add,
            .src_alpha_blend_factor = .one,
            .dst_alpha_blend_factor = .zero,
            .alpha_blend_op = .add,

            // Regular blend from alpha-channel
            // .blend_enable = .true,
            // .src_color_blend_factor = .src_alpha,
            // .dst_color_blend_factor = .one_minus_src_alpha,
            // .color_blend_op = .add,
            // .src_alpha_blend_factor = .one,
            // .dst_alpha_blend_factor = .zero,
            // .alpha_blend_op = .add,
        };

        const color_blend_state_info: vk.PipelineColorBlendStateCreateInfo = .{
            .logic_op_enable = .false, //.true,
            .logic_op = .copy,
            .attachment_count = 1,
            .p_attachments = @ptrCast(&color_blend_attachment_state),
            .blend_constants = @splat(0),
        };

        const pipeline_layout_info: vk.PipelineLayoutCreateInfo = .{
            .set_layout_count = 0,
            .p_set_layouts = null,
            .push_constant_range_count = 0,
            .p_push_constant_ranges = null,
        };

        self.pipeline_layout = try self.device.createPipelineLayout(&pipeline_layout_info, null);

        const color_attachment: vk.AttachmentDescription = .{
            .format = self.swap_chain_format,
            .samples = .{ .@"1_bit" = true },
            .load_op = .clear,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .undefined,
            .final_layout = .present_src_khr,
        };

        const color_attachment_ref: vk.AttachmentReference = .{
            .attachment = 0,
            .layout = .color_attachment_optimal, //.attachment_optimal,
        };

        const subpass: vk.SubpassDescription = .{
            .pipeline_bind_point = .graphics,
            .color_attachment_count = 1,
            // From Vulkan Tutorial: The index of the attachment in this array
            // is directly referenced from the fragment shader with the
            // `layout(location = 0)out vec4 outColor` directive!
            .p_color_attachments = @ptrCast(&color_attachment_ref),
        };

        const render_pass_dependency: vk.SubpassDependency = .{
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = 0,
            .src_stage_mask = .{ .color_attachment_output_bit = true },
            .src_access_mask = .{},
            .dst_stage_mask = .{ .color_attachment_output_bit = true },
            .dst_access_mask = .{ .color_attachment_write_bit = true },
        };

        const render_pass_info: vk.RenderPassCreateInfo = .{
            .attachment_count = 1,
            .p_attachments = @ptrCast(&color_attachment),
            .subpass_count = 1,
            .p_subpasses = @ptrCast(&subpass),
            .dependency_count = 1,
            .p_dependencies = &.{render_pass_dependency},
        };

        self.render_pass = try self.device.createRenderPass(&render_pass_info, null);
        const pipeline_info: vk.GraphicsPipelineCreateInfo = .{
            .stage_count = shader_stages.len,
            .p_stages = @ptrCast(&shader_stages),
            .p_vertex_input_state = &vertex_input_info,
            .p_input_assembly_state = &input_assembly,
            .p_viewport_state = &viewport_state_info,
            .p_rasterization_state = &rasterization_state_info,

            .p_multisample_state = &multisample_state_info,
            .p_depth_stencil_state = null,
            .p_color_blend_state = &color_blend_state_info,
            .p_dynamic_state = &dynamic_state_info,
            .layout = self.pipeline_layout,
            .render_pass = self.render_pass,
            .subpass = 0,
            .base_pipeline_handle = .null_handle,
            .base_pipeline_index = -1,
        };

        var target_pipeline_handles: [1]vk.Pipeline = undefined;
        const res = try self.device.createGraphicsPipelines(.null_handle, &.{pipeline_info}, null, target_pipeline_handles[0..]);
        assert(res == .success);
        self.pipeline = target_pipeline_handles[0];
    }

    {
        for (self.swap_chain_image_views, 0..) |_, i| {
            const framebuffer_info: vk.FramebufferCreateInfo = .{
                .render_pass = self.render_pass,
                .attachment_count = 1,
                .p_attachments = @ptrCast(&self.swap_chain_image_views[i]),
                .width = self.swap_chain_extent.width,
                .height = self.swap_chain_extent.height,
                .layers = 1,
            };

            self.swap_chain_framebuffers[i] = try self.device.createFramebuffer(&framebuffer_info, null);
        }
    }
    {
        const command_pool_info: vk.CommandPoolCreateInfo = .{
            .flags = .{ .reset_command_buffer_bit = true },
            .queue_family_index = graphics_queue_index,
        };

        self.command_pool = try self.device.createCommandPool(&command_pool_info, null);
    }

    {
        const command_buffer_info: vk.CommandBufferAllocateInfo = .{
            .command_pool = self.command_pool,
            .level = .primary,
            .command_buffer_count = 1,
        };
        try self.device.allocateCommandBuffers(&command_buffer_info, @ptrCast(&self.command_buffer));
    }

    {
        const semaphore_info: vk.SemaphoreCreateInfo = .{};
        const fence_info: vk.FenceCreateInfo = .{
            .flags = .{ .signaled_bit = true },
        };

        self.image_available_semaphore = try self.device.createSemaphore(&semaphore_info, null);
        self.render_finished_semaphore = try self.device.createSemaphore(&semaphore_info, null);
        self.in_flight_fence = try self.device.createFence(&fence_info, null);
    }
}

pub fn tempFrame(self: *Self) !void {
    const MaxTimeout = 200000000; // std.math.maxInt(u64);
    const wait_for_fences_result = try self.device.waitForFences(&.{self.in_flight_fence}, .true, MaxTimeout);
    log.debug("wait_for_fences_result = {any}", .{wait_for_fences_result});
    assert(wait_for_fences_result == .success);
    try self.device.resetFences(&.{self.in_flight_fence});

    const next_image_result = try self.device.acquireNextImageKHR(
        self.swap_chain,
        MaxTimeout,
        self.image_available_semaphore,
        .null_handle,
    );
    assert(next_image_result.result == .success);

    const image_index = next_image_result.image_index;
    log.debug("image_index = {d}", .{image_index});

    try self.device.resetCommandBuffer(self.command_buffer, .{});

    {
        try self.device.beginCommandBuffer(self.command_buffer, &.{});

        const clear_color: vk.ClearValue = .{
            .color = .{ .float_32 = .{ 0, 0, 0, 1 } },
        };

        const render_pass_info: vk.RenderPassBeginInfo = .{
            .render_pass = self.render_pass,
            .framebuffer = self.swap_chain_framebuffers[image_index],
            .render_area = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = self.swap_chain_extent,
            },
            .clear_value_count = 1,
            .p_clear_values = @ptrCast(&clear_color),
        };

        self.device.cmdBeginRenderPass(self.command_buffer, &render_pass_info, .@"inline");
        self.device.cmdBindPipeline(self.command_buffer, .graphics, self.pipeline);
        self.device.cmdSetViewport(self.command_buffer, 0, &.{self.viewport});
        self.device.cmdSetScissor(self.command_buffer, 0, &.{self.scissor});
        self.device.cmdDraw(self.command_buffer, 3, 1, 0, 0);
        self.device.cmdEndRenderPass(self.command_buffer);

        try self.device.endCommandBuffer(self.command_buffer);
    }

    {
        const submit_info: vk.SubmitInfo = .{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = &.{
                self.image_available_semaphore,
            },
            .p_wait_dst_stage_mask = &.{
                .{ .color_attachment_output_bit = true },
            },
            .command_buffer_count = 1,
            .p_command_buffers = &.{self.command_buffer},
            .signal_semaphore_count = 1,
            .p_signal_semaphores = &.{self.render_finished_semaphore},
        };

        try self.device.queueSubmit(self.queue.graphics, &.{submit_info}, self.in_flight_fence);
    }

    {
        const present_info: vk.PresentInfoKHR = .{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = &.{self.render_finished_semaphore},

            .swapchain_count = 1,
            .p_swapchains = &.{self.swap_chain},
            .p_image_indices = &.{image_index},
        };

        const present_result = try self.device.queuePresentKHR(self.queue.present, &present_info);
        assert(present_result == .success);
    }
}

pub fn deinit(self: *Self) void {
    self.device.deviceWaitIdle() catch |err| {
        log.err("vulkan deviceWaitIdle problem: {s}.", .{@errorName(err)});
        unreachable;
    };

    self.device.destroyFence(self.in_flight_fence, null);
    self.device.destroySemaphore(self.render_finished_semaphore, null);
    self.device.destroySemaphore(self.image_available_semaphore, null);

    self.device.destroyCommandPool(self.command_pool, null);
    for (self.swap_chain_framebuffers) |framebuffer| {
        self.device.destroyFramebuffer(framebuffer, null);
    }

    self.device.destroyPipeline(self.pipeline, null);
    self.device.destroyRenderPass(self.render_pass, null);
    self.device.destroyPipelineLayout(self.pipeline_layout, null);

    self.device.destroyShaderModule(self.frag_shader_module, null);
    self.device.destroyShaderModule(self.vert_shader_module, null);

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
const builtin = @import("builtin");

const glfw = @import("zglfw");
const vk = @import("vulkan");
