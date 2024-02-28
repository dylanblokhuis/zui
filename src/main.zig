const std = @import("std");
const Allocator = std.mem.Allocator;

/// # remaining stuff
///
/// how to do if statements
const zui = struct {
    allocator: Allocator,

    // nodes: std.MultiArrayList(ViewNode),

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        return Self{
            .allocator = allocator,
            // .nodes = std.MultiArrayList(ViewNode){},
        };
    }

    pub const p = struct {
        class: []const u8,
        on_click: ?*const fn () void = null,
        child: ?ViewNode = null,
    };

    const ViewNode = struct {
        class: []const u8 = "",
        on_click: ?*const fn () void = null,
        children: ?[]const ViewNode = null,
    };

    /// function to make a singular view node
    pub fn v(self: *Self, props: p) ViewNode {
        var children: ?[]ViewNode = null;

        if (props.child != null) {
            children = self.allocator.alloc(ViewNode, 1) catch unreachable;
            if (props.child != null) {
                children.?[0] = props.child.?;
            }
        }

        return ViewNode{
            .class = props.class,
            .on_click = props.on_click,
            .children = children,
        };
    }

    /// function to make an array of view nodes
    pub fn vv(self: *Self, children: []const ViewNode) ViewNode {
        const nodes = self.allocator.alloc(ViewNode, children.len) catch unreachable;
        for (children, 0..) |child, index| {
            nodes[index] = child;
        }

        return ViewNode{
            .children = nodes,
        };
    }

    pub fn foreach(self: *Self, comptime T: type, cb: *const fn (self: *Self, item: T, index: usize) ViewNode, items: []const T) ViewNode {
        var children = self.allocator.alloc(ViewNode, items.len) catch unreachable;
        for (items, 0..) |item, index| {
            children[index] = cb(self, item, index);
        }

        return ViewNode{
            .children = children,
        };
    }

    pub fn fmt(self: *Self, comptime format: []const u8, args: anytype) []u8 {
        return std.fmt.allocPrint(self.allocator, format, args) catch unreachable;
    }
};

// const Hello = struct {
//     pub fn handle_click() void {
//         std.log.debug("clicked", .{});
//     }

//     pub fn render(ui: *zui) []zui.ViewNode {
//         return ui.v(.{
//             .class = "flex flex-wrap",
//             .on_click = handle_click,
//             .children = ui.vv(.{
//                 ui.v(.{
//                     .class = "flex flex-wrap",
//                 }),
//                 // .class = "flex flex-wrap",
//             }),
//         });
//     }
// };

fn forl(ui: *zui, item: u8, index: usize) zui.ViewNode {
    return zui.ViewNode{
        .class = ui.fmt("item-{d}-index-{d}", .{ item, index }),
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var ui = try zui.init(arena.allocator());

    const tree = ui.v(.{
        .class = "flex flex-wrap",
        .child = ui.vv(&.{
            ui.v(.{
                .class = "flex flex-wrap p-4",
            }),
            ui.v(.{
                .class = "flex flex-wrap p-10",
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

    const PrintTree = struct {
        const Self = @This();

        pub fn print_tree(node: *const zui.ViewNode, depth: u8) void {
            for (0..depth) |_| {
                std.debug.print("  ", .{});
            }
            std.debug.print("{s}\n", .{node.class});

            if (node.children == null) {
                return;
            }

            // const children = &node.children.?;
            for (node.children.?) |*child| {
                Self.print_tree(child, depth + 1);
            }
        }
    };

    PrintTree.print_tree(&tree, 0);

    // arena size
    std.debug.print("bytes in arena: {d}\n", .{arena.queryCapacity()});

    // const props = zui.Props{ .class = "yo" };
    // try ui.v("flex flex-warp", .{});

    // const ui = try zui.init(std.heap.c_allocator);
    // _ = ui; // autofix
    // var tree = LayoutTree.init(std.heap.c_allocator);

    // const yo = try tree.new_leaf(.{
    //     .layout = .rows,
    // });

    // const yo2 = try tree.new_leaf(.{
    //     .layout = .columns,
    // });

    // try tree.add_child(yo, yo2);

    // var iterator = tree.nodes.iterator();
    // while (iterator.next()) |index| {
    //     const node = tree.nodes.get(index).?;
    //     std.log.debug("parent {any}", .{node});

    //     for (node.children.items) |child| {
    //         std.log.debug("child {any}", .{child});
    //     }
    // }
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
