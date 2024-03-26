const std = @import("std");
const rl = @import("raylib");
const freetype = @import("freetype");
// const mod_ui = @import("mod/ui.zig");
const ui = @import("mod/ui2.zig");

const Allocator = std.mem.Allocator;

pub const RLFonts = std.StringArrayHashMap(rl.Texture);

pub fn render(rl_fonts: *const RLFonts, dom: *ui.Dom, node_id: ui.Dom.NodeId, yoga_elements: *ui.YogaElements, options: *const ui.Options, depth: u32) void {
    const node = dom.nodes.items[node_id];

    if (node.style.background_color[3] != 0) {
        const yoga_node = yoga_elements.get(node_id).?;
        const x = ui.Yoga.YGNodeLayoutGetLeft(yoga_node);
        const y = ui.Yoga.YGNodeLayoutGetTop(yoga_node);
        const width = ui.Yoga.YGNodeLayoutGetWidth(yoga_node);
        const height = ui.Yoga.YGNodeLayoutGetHeight(yoga_node);

        rl.drawRectangleRounded(.{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        }, node.style.rounding, 10, rl.Color.init(node.style.background_color[0], node.style.background_color[1], node.style.background_color[2], node.style.background_color[3]));
    }

    var child = node.first_child;
    while (child != ui.Dom.InvalidNodeId) {
        const child_node = dom.nodes.items[child];
        render(rl_fonts, dom, child, yoga_elements, options, depth + 1);
        child = child_node.next_sibling;
    }
}
//     // std.debug.print("{d} {s}\n", .{ depth, node.data.class });

//     // no need to draw rectangles with 0 alpha
//     if (node.style.background_color[3] != 0) {
//         rl.drawRectangleRounded(.{
//             .x = node.layout.rect[0],
//             .y = node.layout.rect[1],
//             .width = node.layout.rect[2],
//             .height = node.layout.rect[3],
//         }, node.style.rounding, 10, rl.Color.init(node.style.background_color[0], node.style.background_color[1], node.style.background_color[2], node.style.background_color[3]));
//     }

//     if (!std.mem.eql(u8, node.data.text, "")) {
//         const maybe_font = rl_fonts.get(node.style.font_name);

//         if (maybe_font) |tex| {
//             const desc = ui.font_name_to_desc.get(node.style.font_name).?;
//             const atlas = ui.fonts.atlases.get(desc).?;
//             var pos: i32 = 0;
//             for (node.data.text) |c| {
//                 const glyph = atlas.glyph_infos[@intCast(c)];
//                 const text_rect = glyph.glyph_position_in_atlas();

//                 const src_rect = rl.Rectangle{
//                     .width = text_rect[0],
//                     .height = text_rect[1],
//                     .x = text_rect[2],
//                     .y = text_rect[3],
//                 };

//                 const corrected_font_size = @as(f32, @floatFromInt(atlas.font_size)) / 1.16;
//                 const position = rl.Vector2.init(@floatFromInt(pos + glyph.xoff), corrected_font_size - @as(f32, @floatFromInt(glyph.yoff)));

//                 const local_position = rl.Vector2.init(node.layout.rect[0] + position.x, node.layout.rect[1] + position.y);

//                 rl.drawTextureRec(tex, src_rect, local_position, rl.Color.init(node.style.color[0], node.style.color[1], node.style.color[2], node.style.color[3]));

//                 pos += glyph.advance;
//             }
//         }
//     }

//     var maybe_child = node.first_child;
//     while (maybe_child) |child| {
//         render(rl_fonts, ui, child, depth + 1);
//         maybe_child = child.next_sibling;
//     }
// }

pub fn main() !void {
    // try mod_ui2.example();
    const screenWidth = 1280;
    const screenHeight = 720;

    rl.setConfigFlags(.flag_msaa_4x_hint);
    // rl.setConfigFlags(.flag_window_highdpi);
    rl.initWindow(screenWidth, screenHeight, "some-game");
    rl.setWindowMonitor(0);
    // rl.setTargetFPS(0);

    // var ui = mod_ui.Ui.init(std.heap.c_allocator);

    // try ui.style_options.colors.put(ui.allocator, "red", @Vector(4, u8){ 255, 0, 0, 255 });
    // try ui.style_options.colors.put(ui.allocator, "green", @Vector(4, u8){ 0, 255, 0, 255 });
    // try ui.style_options.colors.put(ui.allocator, "blue", @Vector(4, u8){ 0, 0, 255, 255 });
    // try ui.style_options.colors.put(ui.allocator, "white", @Vector(4, u8){ 255, 255, 255, 255 });
    // try ui.style_options.colors.put(ui.allocator, "black", @Vector(4, u8){ 0, 0, 0, 255 });
    // try ui.style_options.colors.put(ui.allocator, "gray", @Vector(4, u8){ 128, 128, 128, 255 });

    // try ui.load_font("default", .{
    //     .path = "./assets/Inter-Regular.ttf",
    //     .size = 16,
    // });

    // try ui.load_font("bold", .{
    //     .path = "./assets/Inter-Bold.ttf",
    //     .size = 16,
    // });

    const rl_fonts = RLFonts.init(std.heap.c_allocator);
    // {
    //     var iter = ui.font_name_to_desc.iterator();
    //     while (iter.next()) |item| {
    //         const desc = item.value_ptr;
    //         const atlas = ui.fonts.atlases.get(desc.*).?;
    //         const tex = rl.loadTextureFromImage(rl.Image{
    //             .data = atlas.data.ptr,
    //             .width = @intCast(atlas.width),
    //             .height = @intCast(atlas.height),
    //             .format = .pixelformat_uncompressed_gray_alpha,
    //             .mipmaps = 1,
    //         });
    //         try rl_fonts.put(item.key_ptr.*, tex);
    //     }
    // }

    var yoga_elements = ui.YogaElements.init(std.heap.c_allocator);

    var options = ui.Options.init(std.heap.c_allocator);
    {
        try options.colors.put("red", @Vector(4, u8){ 255, 0, 0, 255 });
        try options.colors.put("green", @Vector(4, u8){ 0, 255, 0, 255 });
        try options.colors.put("blue", @Vector(4, u8){ 0, 0, 255, 255 });
        try options.colors.put("white", @Vector(4, u8){ 255, 255, 255, 255 });
        try options.colors.put("black", @Vector(4, u8){ 0, 0, 0, 255 });
        try options.colors.put("gray", @Vector(4, u8){ 128, 128, 128, 255 });
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    var prev_arena: ?std.heap.ArenaAllocator = null;
    var prev_dom: ?*ui.Dom = null;
    var prev_root_node: ui.Dom.NodeId = ui.Dom.InvalidNodeId;

    // // Wait for the user to close the window.
    while (!rl.windowShouldClose()) {
        _ = arena.reset(.retain_capacity);

        rl.beginDrawing();
        rl.clearBackground(rl.Color.black);

        var dom = ui.Dom.init(arena.allocator(), &options);

        const root = dom.view(.{
            .class = "bg-black p-40",
            .children = &.{
                dom.view(.{
                    .class = "bg-red w-200 h-200",
                    .children = &.{
                        dom.view(.{
                            .class = "bg-white w-100 h-100",
                        }),
                    },
                }),

                dom.view(.{
                    .class = "bg-blue w-200 h-200",
                }),

                dom.view(.{
                    .class = "bg-green w-200 h-200",
                }),
            },
        });

        var mutations = std.ArrayList(ui.Mutation).init(arena.allocator());
        // std.log.info("here!", .{});
        try ui.diff(prev_dom, &dom, prev_root_node, root, &mutations);
        // std.log.info("here!2", .{});

        for (mutations.items) |item| {
            std.debug.print("{}\n", .{item});
            switch (item) {
                ui.Mutation.replace => |data| {
                    _ = try ui.replace(
                        prev_dom,
                        &dom,
                        data.prev,
                        data.next,
                        &yoga_elements,
                        &options,
                    );
                },
                ui.Mutation.updateClass => |update_class| {
                    _ = update_class; // autofix
                },
                ui.Mutation.updateOnClick => |update_onclick| {
                    _ = update_onclick; // autofix
                },
            }
        }

        if (mutations.items.len > 0) {
            ui.CalculateLayout(yoga_elements.get(root).?, screenWidth, screenHeight, ui.LayoutDirectionLTR);
        }

        render(&rl_fonts, &dom, root, &yoga_elements, &options, 0);

        prev_arena = arena;
        prev_dom = &dom;
        prev_root_node = root;

        rl.endDrawing();
    }

    // _ = arena.reset(.retain_capacity);
}
