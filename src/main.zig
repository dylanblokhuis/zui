const std = @import("std");
const rl = @import("raylib");
const freetype = @import("freetype");
const mod_ui = @import("mod/ui.zig");

const Allocator = std.mem.Allocator;

pub const RLFonts = std.StringArrayHashMap(rl.Texture);

pub fn render(rl_fonts: *RLFonts, ui: *mod_ui.Ui, node: *const mod_ui.Node, depth: u32) void {
    // std.debug.print("{d} {s}\n", .{ depth, node.data.class });

    // no need to draw rectangles with 0 alpha
    if (node.style.background_color[3] != 0) {
        rl.drawRectangleRounded(.{
            .x = node.layout.rect[0],
            .y = node.layout.rect[1],
            .width = node.layout.rect[2],
            .height = node.layout.rect[3],
        }, node.style.rounding, 10, rl.Color.init(node.style.background_color[0], node.style.background_color[1], node.style.background_color[2], node.style.background_color[3]));
    }

    if (!std.mem.eql(u8, node.data.text, "")) {
        const maybe_font = rl_fonts.get(node.style.font_name);

        if (maybe_font) |tex| {
            const desc = ui.font_name_to_desc.get(node.style.font_name).?;
            const atlas = ui.fonts.atlases.get(desc).?;
            var pos: i32 = 0;
            for (node.data.text) |c| {
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

                const local_position = rl.Vector2.init(node.layout.rect[0] + position.x, node.layout.rect[1] + position.y);

                rl.drawTextureRec(tex, src_rect, local_position, rl.Color.init(node.style.color[0], node.style.color[1], node.style.color[2], node.style.color[3]));

                pos += glyph.advance;
            }
        }
    }

    var maybe_child = node.first_child;
    while (maybe_child) |child| {
        render(rl_fonts, ui, child, depth + 1);
        maybe_child = child.next_sibling;
    }
}

pub fn main() !void {
    const screenWidth = 1280;
    const screenHeight = 720;

    rl.setConfigFlags(.flag_msaa_4x_hint);
    // rl.setConfigFlags(.flag_window_highdpi);
    rl.initWindow(screenWidth, screenHeight, "some-game");
    rl.setWindowMonitor(0);
    rl.setTargetFPS(0);

    var ui = mod_ui.Ui.init(std.heap.c_allocator);

    try ui.style_options.colors.put(ui.allocator, "red", @Vector(4, u8){ 255, 0, 0, 255 });
    try ui.style_options.colors.put(ui.allocator, "green", @Vector(4, u8){ 0, 255, 0, 255 });
    try ui.style_options.colors.put(ui.allocator, "blue", @Vector(4, u8){ 0, 0, 255, 255 });
    try ui.style_options.colors.put(ui.allocator, "white", @Vector(4, u8){ 255, 255, 255, 255 });
    try ui.style_options.colors.put(ui.allocator, "black", @Vector(4, u8){ 0, 0, 0, 255 });
    try ui.style_options.colors.put(ui.allocator, "gray", @Vector(4, u8){ 128, 128, 128, 255 });

    try ui.load_font("default", .{
        .path = "./assets/Inter-Regular.ttf",
        .size = 16,
    });

    try ui.load_font("bold", .{
        .path = "./assets/Inter-Bold.ttf",
        .size = 16,
    });

    var rl_fonts = RLFonts.init(ui.allocator);
    {
        var iter = ui.font_name_to_desc.iterator();
        while (iter.next()) |item| {
            const desc = item.value_ptr;
            const atlas = ui.fonts.atlases.get(desc.*).?;
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

    // // Wait for the user to close the window.
    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        rl.clearBackground(rl.Color.black);

        const fps = rl.getFPS();

        var tree = ui.root(ui.v(.{
            .class = ui.fmt("w-{d} h-{d}", .{ screenWidth, screenHeight }),
            .children = ui.vv(&.{
                ui.v(.{
                    .class = "b-right b-bottom text-white m-10 font-bold",
                    .text = ui.fmt("FPS: {d}", .{fps}),
                }),
                // ui.v(.{
                //     .class = "bg-blue w-200 h-50 rounding-0.5 b-center",
                //     .children = ui.vv(&.{
                //         ui.v(.{
                //             .class = "b-center text-white font-bold",
                //             .text = ui.fmt("FPS: {d}", .{fps}),
                //         }),
                //         // ui.v(.{
                //         //     .class = "behave-left behave-top",
                //         //     .text = "Hello world",
                //         // }),
                //     }),
                // }),
                ui.v(.{
                    .class = "col",
                    .children = ui.vv(&.{
                        ui.c(mod_ui.Button{}),
                        ui.c(mod_ui.Button{ .henkie = 10 }),
                    }),
                }),
            }),
        }));
        ui.compute_layout(&tree);

        const pos = rl.getMousePosition();
        ui.handle_mouse_move_event(&tree, @Vector(2, f32){ pos.x, pos.y });

        if (rl.isMouseButtonPressed(.mouse_button_left)) {
            ui.handle_click_event(&tree, @Vector(2, f32){ pos.x, pos.y });
        }

        ui.compute_layout(&tree);

        render(&rl_fonts, &ui, &tree, 0);

        // we should decouple rendering and the ui layout tbh
        _ = ui.arena.reset(.retain_capacity);

        rl.endDrawing();
    }

    // _ = arena.reset(.retain_capacity);
}
