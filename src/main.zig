const std = @import("std");
const GenArena = @import("./gen_arena.zig").Arena;

pub fn main() !void {
    var tree = LayoutTree.init(std.heap.c_allocator);

    const yo = try tree.new_leaf(.{
        .layout = .rows,
    });

    const yo2 = try tree.new_leaf(.{
        .layout = .columns,
    });

    try tree.add_child(yo, yo2);

    var iterator = tree.nodes.iterator();
    while (iterator.next()) |index| {
        const node = tree.nodes.get(index).?;
        std.log.debug("parent {any}", .{node});

        for (node.children.items) |child| {
            std.log.debug("child {any}", .{child});
        }
    }
}

const Style = struct {
    layout: enum {
        // vstack
        rows,
        // hstack
        columns,
    },
    padding: f16 = 0.0,
    border: f16 = 0.0,
};

const Point = struct {
    x: f32,
    y: f32,
};

const Rect = struct {
    width: f32,
    height: f32,
};

const Border = struct {
    left: f16,
    right: f16,
    top: f16,
    bottom: f16,
};

const ComputedLayout = struct {
    order: u8,
    location: Point,
    size: Rect,
    content_size: Rect,
    border: Border,
    padding: Border,
};

const Node = struct {
    style: Style,
    children: std.ArrayListUnmanaged(LayoutTree.Index),
    layout: ?ComputedLayout,
};

const LayoutTree = struct {
    const Index = GenArena(Node).Index;

    allocator: std.mem.Allocator,

    nodes: GenArena(Node),
    parents: std.ArrayListUnmanaged(?Index),

    pub fn init(allocator: std.mem.Allocator) LayoutTree {
        std.log.debug("{any}", .{@sizeOf(ComputedLayout)});
        return LayoutTree{
            .allocator = allocator,
            .nodes = GenArena(Node).init(allocator),
            .parents = std.ArrayListUnmanaged(?Index){},
        };
    }

    pub fn new_leaf(self: *LayoutTree, style: Style) !Index {
        const id = try self.nodes.append(Node{
            .style = style,
            .children = std.ArrayListUnmanaged(LayoutTree.Index){},
            .layout = null,
        });
        // try self.children.append(std.ArrayList(Index).init(self.allocator));
        try self.parents.append(self.allocator, null);

        return id;
    }

    pub fn add_child(self: *LayoutTree, parent: Index, child: Index) !void {
        self.parents.items[child.index] = parent;
        var node = self.nodes.get(parent) orelse {
            return error.NodeNotFound;
        };
        try node.children.append(self.allocator, child);
        try self.nodes.mutate(parent, node);
    }

    pub fn compute_layout(self: *LayoutTree) !void {
        var iterator = self.nodes.iterator();
        while (iterator.next()) |index| {
            const node = self.nodes.get(index) orelse {
                return error.NodeNotFound;
            };
            _ = node; // autofix

            // const parent = self.parents.items[index];
            // const parent_layout = parent != null
            //     ? self.nodes.get(parent).layout
            //     : null;

            // const layout = self.compute_layout_for_node(node, parent_layout);
            // try self.nodes.mutate(index, node);
        }
    }
};
