const std = @import("std");
const zui = @import("ui.zig");
const rl = @import("raylib");

const Allocator = std.mem.Allocator;

fn forl(ui: *zui, item: u8, index: usize) zui.ViewNode {
    return zui.ViewNode{
        .class = ui.fmt("w-10 h-20 bg-indigo item-{d}-index-{d}", .{ item, index }),
    };
}

pub fn main() !void {
    const screenWidth = 1280;
    const screenHeight = 720;

    rl.setConfigFlags(.flag_msaa_4x_hint);
    rl.initWindow(screenWidth, screenHeight, "some-game");
    rl.setWindowMonitor(0);
    rl.setTargetFPS(0);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var ui = try zui.init(arena.allocator());

    // const data = render(tree, screenWidth, screenHeight).?;

    // std.log.debug("{any}", .{data.len});

    // // rl.updateTexture(texture: Texture2D, pixels: *const anyopaque)

    // const image = rl.loadImageFromMemory(".png", data);
    // const texture = rl.loadTextureFromImage(image);

    // Wait for the user to close the window.
    while (!rl.windowShouldClose()) {
        var tree = ui.v(.{
            .class = "w-150 h-150 bg-red col",
            // make this always be an array
            .children = ui.vv(&.{
                ui.v(.{
                    .class = "p-4 w-50 rounded-100 h-40 bg-yellow",
                }),
                ui.v(.{
                    .class = "p-10 w-40 h-40 bg-green",
                    .children = ui.foreach(u8, forl, &.{
                        4,
                        2,
                    }),
                }),
                ui.v(.{
                    .class = ui.fmt("bg-{s} w-50 h-50", .{"blue"}),
                }),
            }),
        });

        ui.compute_layout(&tree, screenWidth, screenHeight);

        rl.beginDrawing();
        rl.clearBackground(rl.Color.black);

        rl.drawFPS(screenWidth - 100, screenHeight - 30);

        {
            const Draw = struct {
                const Self = @This();

                pub fn draw_node(node: *const zui.ViewNode) void {
                    if (node.computed_layout) |layout| {
                        const average = (layout.width + layout.height) / 2;
                        const roundness = node.rounding / average;

                        rl.drawRectangleRounded(.{
                            .width = layout.width,
                            .height = layout.height,
                            .x = layout.x,
                            .y = layout.y,
                        }, roundness, 10, rl.Color.init(node.bg_color[0], node.bg_color[1], node.bg_color[2], node.bg_color[3]));
                    }

                    if (node.children == null) {
                        return;
                    }

                    for (node.children.?) |*child| {
                        Self.draw_node(child);
                    }
                }
            };

            Draw.draw_node(&tree);
        }

        rl.endDrawing();
        _ = arena.reset(.retain_capacity);
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
