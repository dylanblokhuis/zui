const std = @import("std");
const zui = @import("ui.zig");
const rl = @import("raylib");
const Layout = @import("./libs/layout//layout.zig").Layout;

const Allocator = std.mem.Allocator;

fn forl(ui: *zui, item: u8, index: usize) zui.ViewNode {
    return ui.v(.{
        .class = ui.fmt("w-10 h-20 bg-indigo item-{d}-index-{d}", .{ item, index }),
    });
}

const Draw = struct {
    const Self = @This();

    pub fn draw_node(ui: *const zui, fonts: *const RLFonts, node: *const zui.ViewNode) void {
        // if (node.layout_id) |layout_id| {
        const rect = ui.layout.get_rect(node.layout_id);
        const x = @as(f32, @floatFromInt(rect[0]));
        const y = @as(f32, @floatFromInt(rect[1]));
        const width = @as(f32, @floatFromInt(rect[2]));
        const height = @as(f32, @floatFromInt(rect[3]));

        const average = (width + height) / 2;
        const roundness = node.rounding / average;

        const text = std.fmt.allocPrintZ(ui.allocator, "{s}", .{node.text}) catch unreachable;

        if (!std.mem.eql(u8, node.text, "")) {
            const maybe_font = fonts.get(node.font_name);
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
};

const RLFonts = std.StringArrayHashMap(rl.Font);

pub fn main() !void {
    const screenWidth = 1280;
    const screenHeight = 720;

    // var layout = try Layout.init();

    // const root = layout.create_leaf();
    // const child = layout.create_leaf();

    // layout.set_size_xy(root, 100, 100);
    // layout.set_size_xy(child, 90, 80);
    // layout.set_margins_ltrb(root, 10, 10, 10, 10);

    // layout.set_contain(root, Layout.CONTAIN_ROW | Layout.CONTAIN_FLEX | Layout.CONTAIN_MIDDLE);

    // layout.add_child(root, child);
    // layout.run();

    // std.log.debug("root {any}", .{layout.get_rect(root)});
    // std.log.debug("child {any}", .{layout.get_rect(child)});

    // _ = layout; // autofix

    rl.setConfigFlags(.flag_msaa_4x_hint);
    rl.initWindow(screenWidth, screenHeight, "some-game");
    rl.setWindowMonitor(0);
    rl.setTargetFPS(0);
    // const font = rl.loadFont("Inter-VariableFont_slnt,wght.ttf");
    // rl.loadfont
    // defer font.unload();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var ui = try zui.init(arena.allocator());

    try ui.fonts.put("default", "./assets/Inter-Regular.ttf");
    try ui.fonts.put("bold", "./assets/Inter-Bold.ttf");

    var rl_fonts = RLFonts.init(std.heap.c_allocator);
    defer rl_fonts.deinit();

    var iter = ui.fonts.iterator();
    while (iter.next()) |name| {
        const font_name_zeroed = std.fmt.allocPrintZ(arena.allocator(), "{s}", .{name.value_ptr.*}) catch unreachable;
        try rl_fonts.put(name.key_ptr.*, rl.loadFont(font_name_zeroed));
    }

    var tree = ui.v(.{
        .class = "w-250 h-500 bg-red col",

        // make this always be an array
        .children = ui.vv(&.{
            ui.v(.{
                .class = "w-100 rounded-100 h-100 bg-yellow",
                // .children = ui.vv(&.{
                //     ui.v(.{
                //         .class = "w-50 h-50 bg-blue",
                //     }),
                // }),
            }),
            ui.v(.{
                .class = "w-40 h-40 bg-green",
                // .children = ui.foreach(u8, forl, &.{
                //     4,
                //     2,
                // }),
            }),
            ui.v(.{
                .class = ui.fmt("bg-{s} w-50 h-50", .{"blue"}),
            }),
            // ui.v(.{
            //     .class = "text-16",
            //     .text = "hello world",
            // }),
            // ui.v(.{
            //     .class = "text-16 font-bold",
            //     .text = "hello world",
            // }),
        }),
    });

    // Wait for the user to close the window.
    while (!rl.windowShouldClose()) {
        ui.compute_layout(&tree);

        rl.beginDrawing();
        rl.clearBackground(rl.Color.black);

        rl.drawFPS(screenWidth - 100, screenHeight - 30);

        Draw.draw_node(&ui, &rl_fonts, &tree);

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
