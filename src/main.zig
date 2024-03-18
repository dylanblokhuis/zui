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

            // const text = std.fmt.allocPrintZ(ui.allocator, "{s}", .{node.text}) catch unreachable;

            if (!std.mem.eql(u8, node.text, "")) {
                const maybe_font = fonts.get(node.font_name);

                if (maybe_font) |tex| {
                    const desc = ui.font_name_to_desc.get(node.font_name).?;
                    const atlas = ui.fonts.atlases.get(desc).?;
                    var pos: i32 = 0;
                    for (node.text) |c| {
                        const glyph = atlas.glyph_infos[@intCast(c)];
                        const text_rect = glyph.glyph_position_in_atlas();

                        const src_rect = rl.Rectangle{
                            .width = text_rect[0],
                            .height = text_rect[1],
                            .x = text_rect[2],
                            .y = text_rect[3],
                        };

                        const corrected_font_size = as_f32(atlas.font_size) / 1.5;
                        const position = rl.Vector2.init(@floatFromInt(pos + glyph.xoff), corrected_font_size - as_f32(glyph.yoff));

                        const local_position = rl.Vector2.init(x + position.x, y + position.y);

                        rl.drawTextureRec(tex, src_rect, local_position, rl.Color.init(node.text_color[0], node.text_color[1], node.text_color[2], node.text_color[3]));

                        pos += glyph.advance;
                    }
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

const Button = struct {
    number: u8 = 0,
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
            .class = "bg-blue col",
            .children = ui.vv(&.{
                ui.v(.{
                    .class = "text-24 text-white m-10",
                    .text = "Click me!",
                    .on_click = handle_click,
                }),

                ui.v(.{
                    .class = "text-36 text-white",
                    .text = "hello world 2",
                }),

                ui.v(.{
                    .class = "bg-blue col",
                    .children = ui.foreach(u8, list, &.{
                        16,
                        24,
                    }),
                }),
            }),
        });
    }
};

pub const RLFonts = std.StringArrayHashMap(rl.Texture);

pub fn main() !void {
    const screenWidth = 1280;
    const screenHeight = 720;

    rl.setConfigFlags(.flag_msaa_4x_hint);
    // rl.setConfigFlags(.flag_window_highdpi);
    rl.initWindow(screenWidth, screenHeight, "some-game");
    rl.setWindowMonitor(0);
    rl.setTargetFPS(0);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var ui = try zui.init(arena.allocator());

    try ui.load_font("default", .{
        .path = "./assets/Inter-Regular.ttf",
        .size = 16,
    });

    try ui.load_font("bold", .{
        .path = "./assets/Inter-Bold.ttf",
        .size = 16,
    });

    var rl_fonts = RLFonts.init(arena.allocator());
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

    var tree = ui.v(.{
        .class = "bg-red items-start col",
        .children = ui.vv(&.{
            Button.render(&ui),
        }),
    });

    ui.compute_layout(&tree);

    // Wait for the user to close the window.
    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        rl.clearBackground(rl.Color.black);

        if (rl.isMouseButtonPressed(.mouse_button_left)) {
            const pos = rl.getMousePosition();
            ui.send_click_event(@Vector(2, f32){ pos.x, pos.y });
        }

        Draw.draw_node(&ui, &rl_fonts, &tree);

        rl.endDrawing();
    }

    _ = arena.reset(.retain_capacity);
}

inline fn as_f32(x: anytype) f32 {
    return @as(f32, @floatFromInt(x));
}

inline fn as_u32(x: anytype) u32 {
    return @as(u32, @intCast(x));
}

inline fn as_i32(x: anytype) i32 {
    return @as(i32, @intCast(x));
}
