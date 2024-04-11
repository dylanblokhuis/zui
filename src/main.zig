const std = @import("std");
const rl = @import("raylib");
const freetype = @import("freetype");
const ui = @import("mod/ui.zig");
pub const Checkbox = @import("Checkbox.zig");

const Allocator = std.mem.Allocator;

pub const RLFonts = std.StringArrayHashMap(rl.Texture);

pub fn render(rl_fonts: *const RLFonts, dom: *ui.Dom, node_id: ui.Dom.NodeId, yoga_elements: *ui.YogaElements, options: *const ui.Options, parent_offset: @Vector(2, f32)) void {
    const node = dom.nodes.items[node_id];

    const yoga_node = yoga_elements.get(node_id).?;
    const x = ui.Yoga.YGNodeLayoutGetLeft(yoga_node);
    const y = ui.Yoga.YGNodeLayoutGetTop(yoga_node);
    const width = ui.Yoga.YGNodeLayoutGetWidth(yoga_node);
    const height = ui.Yoga.YGNodeLayoutGetHeight(yoga_node);

    const parent_x_offset = parent_offset[0] + x;
    const parent_y_offset = parent_offset[1] + y;

    if (node.style.background_color[3] != 0) {
        rl.drawRectangleRounded(.{
            .x = parent_x_offset,
            .y = parent_y_offset,
            .width = width,
            .height = height,
        }, node.style.rounding, 10, rl.Color.init(node.style.background_color[0], node.style.background_color[1], node.style.background_color[2], node.style.background_color[3]));
    }

    if (node.attributes.text.len > 0) {
        const maybe_font = rl_fonts.get(node.style.font_name);

        if (maybe_font) |tex| {
            const desc = options.font_name_to_desc.get(node.style.font_name).?;
            const atlas = options.font_manager.atlases.get(desc).?;
            var pos: i32 = 0;
            for (node.attributes.text) |c| {
                const glyph = atlas.glyph_infos[@intCast(c)];
                const text_rect = glyph.glyph_position_in_atlas();

                const src_rect = rl.Rectangle{
                    .width = text_rect[0],
                    .height = text_rect[1],
                    .x = text_rect[2],
                    .y = text_rect[3],
                };

                const corrected_font_size = @as(f32, @floatFromInt(atlas.font_size)) / 1.16;
                const position = rl.Vector2.init(@floatFromInt(pos + glyph.xoff), corrected_font_size - @as(f32, @floatFromInt(glyph.yoff)));

                const local_position = rl.Vector2.init(parent_x_offset + position.x, parent_y_offset + position.y);

                rl.drawTextureRec(tex, src_rect, local_position, rl.Color.init(node.style.color[0], node.style.color[1], node.style.color[2], node.style.color[3]));

                pos += glyph.advance;
            }
        }
    }

    var child = node.first_child;
    while (child) |c| {
        const child_node = dom.nodes.items[c.id];
        render(rl_fonts, dom, c.id, yoga_elements, options, @Vector(2, f32){ parent_x_offset, parent_y_offset });
        child = child_node.next_sibling;
    }
}

pub fn main() !void {
    rl.setConfigFlags(.flag_msaa_4x_hint);
    rl.setConfigFlags(.flag_window_resizable);
    rl.initWindow(1280, 720, "some-game");
    rl.setWindowMonitor(0);
    // rl.setTargetFPS(24);

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
    try options.loadFont(std.heap.c_allocator, "default", .{
        .path = "./assets/Inter-Bold.ttf",
        .size = 24,
    });

    var rl_fonts = RLFonts.init(std.heap.c_allocator);
    {
        var iter = options.font_name_to_desc.iterator();
        while (iter.next()) |item| {
            const desc = item.value_ptr;
            const atlas = options.font_manager.atlases.get(desc.*).?;
            const tex = rl.loadTextureFromImage(rl.Image{
                .data = atlas.data.ptr,
                .width = @intCast(atlas.width),
                .height = @intCast(atlas.height),
                .format = .pixelformat_uncompressed_gray_alpha,
                .mipmaps = 1,
            });
            try rl_fonts.put(item.key_ptr.*, tex);
        }
    }

    var first_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var second_arena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var prev_dom: ?ui.Dom = null;
    var prev_root_node: ?ui.Dom.NodeId = null;

    var current_arena = &first_arena;
    var is_first_arena = true;

    var hooks_storage = ui.Dom.Persistent{
        .allocator = std.heap.c_allocator,
    };

    // ui2.example();

    // // Wait for the user to close the window.
    while (!rl.windowShouldClose()) {
        _ = current_arena.reset(.retain_capacity);
        const allocator = current_arena.allocator();

        rl.beginDrawing();
        rl.clearBackground(rl.Color.white);

        var dom = ui.Dom.init(allocator, &hooks_storage, &options);

        const root = dom.tree(dom.view(.{
            .class = "flex flex-col p-10",

            .children = &.{
                dom.text("bg-blue", dom.fmt("{d}", .{rl.getFPS()})),
                dom.text("text-white bg-blue", dom.fmt("Yoga elements: {d}", .{yoga_elements.count()})),
                // dom.view(.{
                //     .class = "bg-blue",
                //     .children = &.{
                //         dom.view(.{
                //             .class = "w-400 h-200 bg-red",
                //         }),
                //         dom.text("font-default", "Henk!"),
                //     },
                // }),

                dom.c(&Checkbox{}),
            },
        }));

        // dom.print_tree(root, 0);

        const yg_root_node = doYoga(&dom, root, &yoga_elements);
        ui.CalculateLayout(yg_root_node, @floatFromInt(rl.getScreenWidth()), @floatFromInt(rl.getScreenHeight()), ui.LayoutDirectionLTR);

        if (rl.isMouseButtonPressed(.mouse_button_left)) {
            dom.handle_event(&yoga_elements, .{ 0, 0 }, root, .{
                .click = .{
                    .x = @floatFromInt(rl.getMouseX()),
                    .y = @floatFromInt(rl.getMouseY()),
                },
            });
        }

        render(&rl_fonts, &dom, root, &yoga_elements, &options, @Vector(2, f32){ 0, 0 });

        prev_dom = dom;
        prev_root_node = root;
        if (is_first_arena) {
            is_first_arena = false;
            current_arena = &second_arena;
        } else {
            is_first_arena = true;
            current_arena = &first_arena;
        }

        rl.endDrawing();
    }
}

pub fn doYoga(dom: *ui.Dom, node_id: ui.Dom.NodeId, yoga_elements: *ui.YogaElements) ui.Yoga.YGNodeRef {
    const node = dom.nodes.items[node_id];

    const yg_node = if (yoga_elements.get(node_id)) |yg| blk: {
        break :blk yg;
    } else blk: {
        const yg_node = ui.Yoga.YGNodeNew();
        yoga_elements.put(node_id, yg_node) catch unreachable;
        break :blk yg_node;
    };

    var classes = std.mem.splitSequence(u8, node.attributes.class, " ");
    while (classes.next()) |class| {
        node.applyStyle(dom.options, class);
        // TODO: we need to reset the node here if the class was different last frame
        ui.applyLayoutStyle(yg_node, dom.options, class, node.attributes.text);
    }

    var child = node.first_child;
    var index: usize = 0;
    while (child) |c| {
        const c_yg_node = doYoga(dom, c.id, yoga_elements);

        const parent_node = ui.Yoga.YGNodeGetParent(c_yg_node);
        if (parent_node == null) {
            ui.Yoga.YGNodeInsertChild(yg_node, c_yg_node, index);
        } else if (parent_node != yg_node) {
            ui.Yoga.YGNodeRemoveChild(parent_node, c_yg_node);
            ui.Yoga.YGNodeInsertChild(yg_node, c_yg_node, index);
        }

        child = dom.nodes.items[c.id].next_sibling;
        index += 1;
    }

    return yg_node;
}
