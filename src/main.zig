const std = @import("std");
const glfw = @import("mach-glfw");
const zui = @import("ui.zig");
const gl = @import("zgl");
const c = @cImport({
    @cInclude("blend2d/blend2d.h");
});

const Allocator = std.mem.Allocator;

fn glGetProcAddress(p: glfw.GLProc, proc: [:0]const u8) ?gl.binding.FunctionPointer {
    _ = p;
    return glfw.getProcAddress(proc);
}

/// Default GLFW error handling callback
fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}\n", .{ error_code, description });
}

fn forl(ui: *zui, item: u8, index: usize) zui.ViewNode {
    return zui.ViewNode{
        .class = ui.fmt("item-{d}-index-{d}", .{ item, index }),
    };
}

pub fn main() !void {
    glfw.setErrorCallback(errorCallback);
    if (!glfw.init(.{})) {
        std.log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    }
    defer glfw.terminate();
    const window = glfw.Window.create(640, 480, "mach-glfw + zig-opengl", null, null, .{
        .opengl_profile = .opengl_core_profile,
        .context_version_major = 4,
        .context_version_minor = 0,
    }) orelse {
        std.log.err("failed to create GLFW window: {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    };
    defer window.destroy();
    glfw.makeContextCurrent(window);

    const proc: glfw.GLProc = undefined;
    try gl.loadExtensions(proc, glGetProcAddress);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // Wait for the user to close the window.
    while (!window.shouldClose()) {
        glfw.pollEvents();

        var ui = try zui.init(arena.allocator());

        const tree = ui.v(.{
            .class = "w-100 h-100 bg-red-600",
            .child = ui.vv(&.{
                ui.v(.{
                    .class = "p-4",
                }),
                ui.v(.{
                    .class = "p-10",
                    .child = ui.foreach(u8, forl, &.{
                        4,
                        2,
                    }),
                }),
                ui.v(.{
                    .class = ui.fmt("bg-{s}", .{"red-600"}),
                }),
            }),
        });

        // gl.clearColor(1, 1, 1, 1);
        // gl.clear(.{
        //     .color = true,
        //     .depth = true,
        //     .stencil = false,
        // });
        const texture_id = gl.genTexture();
        gl.bindTexture(texture_id, .@"2d");

        gl.textureParameter(texture_id, gl.TextureParameter.min_filter, .linear);
        gl.textureParameter(texture_id, gl.TextureParameter.mag_filter, .linear);
        gl.textureParameter(texture_id, gl.TextureParameter.wrap_s, .clamp_to_edge);
        gl.textureParameter(texture_id, gl.TextureParameter.wrap_t, .clamp_to_edge);

        const data = render(tree);
        if (data) |img| {
            std.log.debug("{any}", .{img.pixelData});
            gl.textureImage2D(.@"2d", 0, .rgba8, 480, 480, .rgba, .unsigned_byte, @ptrCast(img.pixelData));
        }

        const vao = gl.genVertexArray();
        const vbo = gl.genBuffer();
        const ebo = gl.genBuffer();

        gl.bindVertexArray(vao);

        const vertices = [_]f32{
            // positions   // texCoords
            -1.0, 1.0, 0.0, 0.0, 1.0, // top let
            -1.0, -1.0, 0.0, 0.0, 0.0, // bottom let
            1.0, -1.0, 0.0, 1.0, 0.0, // bottom right
            1.0, 1.0, 0.0, 1.0, 1.0, // top right
        };

        const indices = [_]u32{
            0, 1, 2, // first triangle
            0, 2, 3, // second triangle
        };

        gl.bindBuffer(vbo, .array_buffer);
        gl.bufferData(.array_buffer, f32, &vertices, .static_draw);

        gl.bindBuffer(ebo, .element_array_buffer);
        gl.bufferData(.element_array_buffer, u32, &indices, .static_draw);

        gl.vertexAttribPointer(0, 3, .float, false, 5 * @sizeOf(f32), 0);
        gl.enableVertexAttribArray(0);

        gl.vertexAttribPointer(1, 2, .float, false, 5 * @sizeOf(f32), 3 * @sizeOf(f32));
        gl.enableVertexAttribArray(1);

        _ = arena.reset(.retain_capacity);
        window.swapBuffers();
    }

    // const PrintTree = struct {
    //     const Self = @This();

    //     pub fn print_tree(node: *const zui.ViewNode, depth: u8) void {
    //         for (0..depth) |_| {
    //             std.debug.print("  ", .{});
    //         }
    //         std.debug.print("{s}\n", .{node.class});

    //         if (node.children == null) {
    //             return;
    //         }

    //         // const children = &node.children.?;
    //         for (node.children.?) |*child| {
    //             Self.print_tree(child, depth + 1);
    //         }
    //     }
    // };

    // PrintTree.print_tree(&tree, 0);

    // arena size
    // std.debug.print("bytes in arena: {d}\n", .{arena.queryCapacity()});
}

/// does the gl calls for the given node and its children
pub fn render(root_node: zui.ViewNode) ?c.BLImageData {
    _ = root_node; // autofix

    std.log.debug("{d:.4}", .{5.0});

    var img: c.BLImageCore = undefined;
    var ctx: c.BLContextCore = undefined;

    var result = c.blImageInitAs(&img, 480, 480, c.BL_FORMAT_PRGB32);
    if (result != c.BL_SUCCESS) {
        std.log.err("Failed to initialize image: {any}\n", .{result});
        return null;
    }

    result = c.blContextInitAs(&ctx, &img, null);
    if (result != c.BL_SUCCESS) {
        _ = c.blImageDestroy(&img);
        std.log.err("Failed to initialize context: {any}\n", .{result});
        return null;
    }

    _ = c.blContextClearAll(&ctx);

    // do some drawing

    var round_rect = c.BLRoundRect{
        .x = 500,
        .y = 195,
        .w = 270,
        .h = 270,
        .rx = 20,
        .ry = 20,
    };
    _ = c.blContextFillGeometry(&ctx, c.BL_GEOMETRY_TYPE_ROUND_RECT, &round_rect);

    var image_data: c.BLImageData = undefined;
    _ = c.blImageGetData(&img, &image_data);

    _ = c.blContextEnd(&ctx);
    _ = c.blImageDestroy(&img);

    return image_data;

    // write the image to a file

    // var codec: c.BLImageCodecCore = undefined;
    // result = c.blImageCodecInitByName(&codec, "PNG", c.SIZE_MAX, null);

    // _ = c.blImageWriteToFile(&img, "output.png", null);

}

// const Style = struct {
//     layout: enum {
//         // vstack
//         rows,
//         // hstack
//         columns,
//     },
//     padding: f16 = 0.0,
//     border: f16 = 0.0,
// };

// const Point = struct {
//     x: f32,
//     y: f32,
// };

// const Rect = struct {
//     width: f32,
//     height: f32,
// };

// const Border = struct {
//     left: f16,
//     right: f16,
//     top: f16,
//     bottom: f16,
// };

// const ComputedLayout = struct {
//     order: u8,
//     location: Point,
//     size: Rect,
//     content_size: Rect,
//     border: Border,
//     padding: Border,
// };

// const Node = struct {
//     style: Style,
//     children: std.ArrayListUnmanaged(LayoutTree.Index),
//     layout: ?ComputedLayout,
// };

// const LayoutTree = struct {
//     const Index = GenArena(Node).Index;

//     allocator: std.mem.Allocator,

//     nodes: GenArena(Node),
//     parents: std.ArrayListUnmanaged(?Index),

//     pub fn init(allocator: std.mem.Allocator) LayoutTree {
//         std.log.debug("{any}", .{@sizeOf(ComputedLayout)});
//         return LayoutTree{
//             .allocator = allocator,
//             .nodes = GenArena(Node).init(allocator),
//             .parents = std.ArrayListUnmanaged(?Index){},
//         };
//     }

//     pub fn new_leaf(self: *LayoutTree, style: Style) !Index {
//         const id = try self.nodes.append(Node{
//             .style = style,
//             .children = std.ArrayListUnmanaged(LayoutTree.Index){},
//             .layout = null,
//         });
//         // try self.children.append(std.ArrayList(Index).init(self.allocator));
//         try self.parents.append(self.allocator, null);

//         return id;
//     }

//     pub fn add_child(self: *LayoutTree, parent: Index, child: Index) !void {
//         self.parents.items[child.index] = parent;
//         var node = self.nodes.get(parent) orelse {
//             return error.NodeNotFound;
//         };
//         try node.children.append(self.allocator, child);
//         try self.nodes.mutate(parent, node);
//     }

//     pub fn compute_layout(self: *LayoutTree) !void {
//         var iterator = self.nodes.iterator();
//         while (iterator.next()) |index| {
//             const node = self.nodes.get(index) orelse {
//                 return error.NodeNotFound;
//             };
//             _ = node; // autofix

//             // const parent = self.parents.items[index];
//             // const parent_layout = parent != null
//             //     ? self.nodes.get(parent).layout
//             //     : null;

//             // const layout = self.compute_layout_for_node(node, parent_layout);
//             // try self.nodes.mutate(index, node);
//         }
//     }
// };
