const std = @import("std");
const zui = @import("ui.zig");
const rl = @import("raylib");
const freetype = @import("freetype");
const Layout = @import("./libs/layout//layout.zig").Layout;

const Allocator = std.mem.Allocator;

fn forl(ui: *zui, item: u8, index: usize) zui.ViewNode {
    return ui.v(.{
        .class = ui.fmt("w-10 h-20 mx-5 bg-indigo item-{d}-index-{d}", .{ item, index }),
    });
}

const Draw = struct {
    const Self = @This();

    pub fn draw_node(ui: *const zui, fonts: *const RLFonts, node: *const zui.ViewNode) void {
        if (node.layout_id) |layout_id| {
            const rect = ui.layout.get_rect(layout_id);
            const x = @as(f32, @floatFromInt(rect[0]));
            const y = @as(f32, @floatFromInt(rect[1]));
            const width = @as(f32, @floatFromInt(rect[2]));
            const height = @as(f32, @floatFromInt(rect[3]));

            const average = (width + height) / 2;
            const roundness = node.rounding / average;

            const text = std.fmt.allocPrintZ(ui.allocator, "{s}", .{node.text}) catch unreachable;

            if (!std.mem.eql(u8, node.text, "")) {
                const maybe_font = fonts.get(node.font_name);
                // std.log.debug("drawing text on {d} {d} with size {d}", .{ x, y, node.text_size });
                if (maybe_font) |font| {
                    rl.drawTextEx(font, text, rl.Vector2.init(x, y), node.text_size, 0, rl.Color.init(node.text_color[0], node.text_color[1], node.text_color[2], node.text_color[3]));
                } else {
                    rl.drawText(text, @intFromFloat(x), @intFromFloat(y), @intFromFloat(node.text_size), rl.Color.init(node.text_color[0], node.text_color[1], node.text_color[2], node.text_color[3]));
                }
            } else {
                rl.drawRectangleRounded(.{
                    .width = width,
                    .height = height,
                    .x = x,
                    .y = y,
                }, roundness, 10, rl.Color.init(node.bg_color[0], node.bg_color[1], node.bg_color[2], node.bg_color[3]));
            }

            if (node.children) |children| {
                for (children) |*child| {
                    Self.draw_node(ui, fonts, child);
                }
            }
        }
    }
};

// pub fn measure_func(self: *zui, node: *zui.ViewNode, known_width: f32, known_height: f32) Layout.Size {
//     _ = self; // autofix
//     _ = node; // autofix
//     _ = known_width; // autofix
//     _ = known_height; // autofix
// }

const Button = struct {
    const Self = @This();

    pub fn handle_click() void {
        std.debug.print("clicked\n", .{});
    }

    pub fn list(ui: *zui, item: u8, _: usize) zui.ViewNode {
        return ui.v(.{
            .class = "text-16 text-white ",
            .text = ui.fmt("Contents of list item {d}", .{item}),
        });
    }

    pub fn render(ui: *zui) zui.ViewNode {
        return ui.v(.{
            .class = "bg-blue",
            .children = ui.vv(&.{
                // ui.v(.{
                //     .class = "text-24 text-white",
                //     .text = "hello world",
                //     .on_click = handle_click,
                // }),

                ui.v(.{
                    .class = "text-36 text-white",
                    .text = "hello world 2",
                }),

                ui.v(.{
                    .class = "bg-blue ",
                    .children = ui.foreach(u8, list, &.{
                        16,
                        24,
                    }),
                }),
            }),
        });
    }
};

pub const RLFonts = std.StringArrayHashMap(rl.Font);

pub fn main() !void {
    const screenWidth = 1280;
    const screenHeight = 720;

    rl.setConfigFlags(.flag_msaa_4x_hint);
    rl.setConfigFlags(.flag_window_highdpi);
    rl.initWindow(screenWidth, screenHeight, "some-game");
    rl.setWindowMonitor(0);
    rl.setTargetFPS(0);
    // const font = rl.loadFont("Inter-VariableFont_slnt,wght.ttf");
    // rl.loadfont
    // defer font.unload();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const lib = try freetype.Library.init();
    defer lib.deinit();

    const face = try lib.createFaceMemory(@embedFile("./Inter-Bold.ttf"), 0);
    try face.setPixelSizes(0, 32);
    try face.loadChar('x', .{ .render = true });
    // try face.loadChar('y', .{ .render = true });

    const GlyphInfo = struct {
        // coords of the glyph in the texture
        x0: u32,
        y0: u32,
        x1: u32,
        y1: u32,
        // left & top bearing
        xoff: i32,
        yoff: i32,
        //
        advance: i32,
    };
    const num_glyphs = 128;
    const glyph_info = try arena.allocator().alloc(GlyphInfo, num_glyphs);
    const max_dim: u32 = @intFromFloat(
        @as(f32, @floatFromInt(1 + (face.size().metrics().height >> 6))) * std.math.ceil(std.math.sqrt(@as(f32, @floatFromInt(num_glyphs)))),
    );

    var tex_width: u32 = 1;
    while (tex_width < max_dim) {
        tex_width <<= 1;
    }

    std.log.debug("{d}", .{tex_width * tex_width});

    const pixels = try arena.allocator().alloc(u8, tex_width * tex_width);
    var pen_x: u32 = 0;
    var pen_y: u32 = 0;

    for (0..num_glyphs) |i| {
        try face.loadChar(@intCast(i), .{ .render = true, .force_autohint = true, .target_light = true });
        const bitmap = face.glyph().bitmap();

        if (pen_x + bitmap.width() >= tex_width) {
            pen_x = 0;
            pen_y += @intCast(((face.size().metrics().height >> 6) + 1));
        }

        if (bitmap.buffer()) |buffer| {
            for (0..bitmap.rows()) |row| {
                for (0..bitmap.width()) |col| {
                    const x = pen_x + col;
                    const y = pen_y + row;
                    const pitch: usize = @intCast(bitmap.pitch());
                    pixels[y * tex_width + x] = buffer[row * pitch + col];
                }
            }
        }

        glyph_info[i] = .{
            .x0 = pen_x,
            .y0 = pen_y,
            .x1 = pen_x + bitmap.width(),
            .y1 = pen_y + bitmap.rows(),

            .xoff = face.glyph().bitmapLeft(),
            .yoff = face.glyph().bitmapTop(),
            .advance = @intCast(face.glyph().advance().x >> 6),
        };
        pen_x += bitmap.width() + 1;
    }

    std.log.debug("{d}", .{tex_width});

    // var bitmap = face.glyph().bitmap();
    // defer bitmap.deinit(lib);

    const fontTex = rl.loadTextureFromImage(rl.Image{
        .data = pixels.ptr,
        .width = @intCast(tex_width),
        .height = @intCast(tex_width),
        .format = .pixelformat_uncompressed_grayscale,
        .mipmaps = 1,
    });
    defer fontTex.unload();

    var ui = try zui.init(arena.allocator());

    try ui.fonts.put("default", "./assets/Inter-Regular.ttf");
    try ui.fonts.put("bold", "./assets/Inter-Bold.ttf");

    var rl_fonts = RLFonts.init(std.heap.c_allocator);
    defer rl_fonts.deinit();

    var iter = ui.fonts.iterator();
    while (iter.next()) |name| {
        const font_name_zeroed = std.fmt.allocPrintZ(arena.allocator(), "{s}", .{name.value_ptr.*}) catch unreachable;

        try rl_fonts.put(name.key_ptr.*, rl.loadFontEx(font_name_zeroed, 256, null));
    }

    var tree = ui.v(.{
        .class = "bg-red items-start row",

        .children = ui.vv(&.{
            // Button.render(&ui),
            ui.v(.{
                .class = "w-100 rounded-100 h-100 bg-yellow",
                .children = ui.vv(&.{
                    ui.v(.{
                        .class = "w-50 h-50 bg-blue",
                    }),
                }),
            }),
            ui.v(.{
                .class = "h-40  bg-green",
                .children = ui.foreach(u8, forl, &.{
                    4,
                    2,
                }),
            }),
            ui.v(.{
                .class = "col bg-yellow",
                .children = ui.vv(&.{
                    ui.v(.{
                        .class = "text-36 text-black",
                        .text = "hello world",
                    }),
                    ui.v(.{
                        .class = "text-18 font-bold text-black",
                        .text = "hello world",
                    }),
                }),
            }),
        }),
    });

    ui.compute_layout(&tree, &rl_fonts);

    // Wait for the user to close the window.
    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        rl.clearBackground(rl.Color.black);

        rl.drawFPS(screenWidth - 100, screenHeight - 30);

        const text_to_render = "HELLo WORLD!";

        var pos: i32 = 0;
        for (text_to_render) |c| {
            const glyph = glyph_info[@intCast(c)];

            const src_rect = rl.Rectangle{
                .width = @floatFromInt(glyph.x1 - glyph.x0),
                .height = @floatFromInt(glyph.y1 - glyph.y0),
                .x = @floatFromInt(glyph.x0),
                .y = @floatFromInt(glyph.y0),
            };

            const position = rl.Vector2.init(
                @floatFromInt(pos + glyph.xoff),
                @as(f32, @floatFromInt(glyph.yoff)),
            );

            // std.log.debug("{any}", .{glyph});
            rl.drawTextureRec(fontTex, src_rect, position, rl.Color.init(255, 255, 255, 255));
            rl.drawRectangleLinesEx(.{
                .width = src_rect.width,
                .height = src_rect.height,
                .x = position.x,
                .y = position.y,
            }, 1, rl.Color.init(255, 255, 255, 255));

            pos += glyph.advance;
        }

        // rl.drawTexture(fontTex, 0, 0, rl.Color.init(255, 255, 255, 255));

        // Draw.draw_node(&ui, &rl_fonts, &tree);

        rl.endDrawing();
    }

    _ = arena.reset(.retain_capacity);

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
