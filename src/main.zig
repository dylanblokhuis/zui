const std = @import("std");
const zui = @import("ui.zig");
const rl = @import("raylib");
const freetype = @import("freetype");
const Layout = @import("./libs/layout//layout.zig").Layout;
const xd = @import("mod/ui.zig");

const Allocator = std.mem.Allocator;

pub const RLFonts = std.StringArrayHashMap(rl.Texture);

pub fn render(node: *const xd.Node, depth: u32) void {
    // std.debug.print("{s} {d}\n", .{ node.data.class, depth });
    rl.drawRectangleRec(.{
        .x = node.layout.rect[0],
        .y = node.layout.rect[1],
        .width = node.layout.rect[2],
        .height = node.layout.rect[3],
    }, rl.Color.init(node.style.background_color[0], node.style.background_color[1], node.style.background_color[2], node.style.background_color[3]));

    var maybe_child = node.first_child;
    while (maybe_child) |child| {
        render(child, depth + 1);
        maybe_child = child.next_sibling;
    }
}

pub fn main() !void {
    const node = try xd.d();

    const screenWidth = 1280;
    const screenHeight = 720;

    // rl.setConfigFlags(.flag_msaa_4x_hint);
    // rl.setConfigFlags(.flag_window_highdpi);
    rl.initWindow(screenWidth, screenHeight, "some-game");
    rl.setWindowMonitor(0);
    rl.setTargetFPS(0);

    // // Wait for the user to close the window.
    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        rl.clearBackground(rl.Color.black);

        // if (rl.isMouseButtonPressed(.mouse_button_left)) {
        //     const pos = rl.getMousePosition();
        //     ui.send_click_event(@Vector(2, f32){ pos.x, pos.y });
        // }

        render(&node, 0);

        // Draw.draw_node(&ui, &rl_fonts, &tree);

        rl.endDrawing();
    }

    // _ = arena.reset(.retain_capacity);
}
