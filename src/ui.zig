const std = @import("std");
const Allocator = std.mem.Allocator;

/// # remaining stuff
///
/// how to do if statements
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

pub const ViewNode = struct {
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

