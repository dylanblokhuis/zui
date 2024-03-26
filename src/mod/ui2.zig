const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @cImport({
    @cInclude("yoga/Yoga.h");
});

pub const YogaNodeRef = c.YGNodeRef;
pub const CalculateLayout = c.YGNodeCalculateLayout;
pub const LayoutDirectionLTR = c.YGDirectionLTR;

pub const Yoga = c;

pub const YogaElements = std.AutoHashMap(Dom.NodeId, YogaNodeRef);

pub const Options = struct {
    colors: std.StringHashMap(@Vector(4, u8)),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .colors = std.StringHashMap(@Vector(4, u8)).init(allocator),
        };
    }
};

pub const Dom = struct {
    nodes: std.ArrayList(Node),
    allocator: Allocator,
    options: *const Options,

    const Self = @This();

    pub const NodeId = usize;
    pub const InvalidNodeId: usize = std.math.maxInt(usize);

    pub fn init(allocator: Allocator, options: *const Options) Self {
        return Self{
            .nodes = std.ArrayList(Node).init(allocator),
            .allocator = allocator,
            .options = options,
        };
    }

    pub fn new_node(self: *Self, attributes: NodeAttributes) Self.NodeId {
        self.nodes.append(Node.init(attributes)) catch unreachable;
        return self.nodes.items.len - 1;
    }

    // pub fn root(self: *Self, node_id: Self.NodeId) Self.NodeId {
    //     return self.nodes.items.len - 1;
    // }

    pub fn append_child(self: *Self, parent_id: Self.NodeId, child_id: Self.NodeId) void {
        const parent = &self.nodes.items[parent_id];

        if (parent.first_child == Self.InvalidNodeId) {
            parent.first_child = child_id;
        } else {
            var id = parent.first_child;
            while (id != Self.InvalidNodeId) {
                const child = &self.nodes.items[id];
                if (child.next_sibling == Self.InvalidNodeId) {
                    child.next_sibling = child_id;
                    break;
                }
                id = child.next_sibling;
            }
        }
    }

    pub fn view(self: *Self, attributes: NodeAttributes) Self.NodeId {
        self.nodes.append(Node.init(attributes, self.options)) catch unreachable;
        const parent_id = self.nodes.items.len - 1;

        if (attributes.children) |children| {
            for (children) |child_id| {
                self.append_child(parent_id, child_id);
            }
        }

        return parent_id;
    }

    pub fn fmt(self: *Self, comptime format: []const u8, args: anytype) []u8 {
        return std.fmt.allocPrint(self.allocator, format, args) catch unreachable;
    }

    // pub fn views(self: *Self, children: []Self.NodeId) []Self.NodeId {
    //     _ = self; // autofix
    //     // const ids = self.allocator.alloc(NodeAttributes, children.len) catch unreachable;
    //     // for (children, 0..) |child, index| {
    //     //     const id = self.view(child);
    //     //     ids[index] = id;
    //     // }
    //     return children;
    // }
};

/// Build a DOM tree with Yoga
/// Create tree once
///
pub fn example() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    var prev_arena: ?std.heap.ArenaAllocator = null;
    var prev_dom: ?*Dom = null;
    var prev_root_node: Dom.NodeId = Dom.InvalidNodeId;

    var yoga_elements = YogaElements.init(std.heap.c_allocator);

    while (true) {
        const now = try std.time.Instant.now();
        _ = arena.reset(.retain_capacity);
        var dom = Dom.init(arena.allocator());

        const root = dom.view(.{
            .class = "bg-black",
            .children = &.{
                dom.view(.{
                    .class = "bg-red m-10 w-200 h-200",
                    .children = &.{
                        dom.view(.{
                            .class = "bg-blue m-10 w-50 h-50",
                        }),
                        // dom.view(.{
                        //     .class = "bg-blue m-10 w-200 h-200",
                        // }),
                    },
                }),

                dom.view(.{
                    .class = "bg-red m-10 w-200 h-200",
                }),

                dom.view(.{
                    .class = "bg-red m-10 w-200 h-200",
                }),
            },
        });

        var mutations = std.ArrayList(Mutation).init(arena.allocator());
        try diff(prev_dom, &dom, prev_root_node, root, &mutations);

        for (mutations.items) |item| {
            std.debug.print("{}\n", .{item});
            switch (item) {
                Mutation.replace => |data| {
                    _ = try replace(
                        prev_dom,
                        &dom,
                        data.prev,
                        data.next,
                        &yoga_elements,
                    );
                },
                Mutation.updateClass => |update_class| {
                    _ = update_class; // autofix
                },
                Mutation.updateOnClick => |update_onclick| {
                    _ = update_onclick; // autofix
                },
            }
        }

        if (mutations.items.len > 0) {
            c.YGNodeCalculateLayout(yoga_elements.get(root).?, 1920, 1080, c.YGDirectionLTR);
        }

        std.log.debug("{d}", .{c.YGNodeLayoutGetLeft(yoga_elements.get(root - 1).?)});

        prev_arena = arena;
        prev_dom = &dom;
        prev_root_node = root;
        const elapsed = (try std.time.Instant.now()).since(now);
        std.log.debug("elapsed us: {d}", .{elapsed / std.time.ns_per_us});
    }
}

pub fn replace(prev: ?*Dom, next: *Dom, prev_node: Dom.NodeId, next_node: Dom.NodeId, yoga_elements: *YogaElements, options: *const Options) !Dom.NodeId {
    if (prev_node != Dom.InvalidNodeId) {
        const maybe_yg_node = yoga_elements.get(prev_node);
        if (maybe_yg_node) |yg_node| {
            c.YGNodeFreeRecursive(yg_node);
        }
    }

    const yg_node = c.YGNodeNew();
    var classes = std.mem.splitSequence(u8, next.nodes.items[next_node].attributes.class, " ");
    while (classes.next()) |class| {
        apply_layout_style(yg_node, options, class);
    }
    try yoga_elements.put(next_node, yg_node);

    var child = next.nodes.items[next_node].first_child;
    var index: usize = 0;
    while (child != Dom.InvalidNodeId) {
        const next_child = try replace(prev, next, Dom.InvalidNodeId, child, yoga_elements, options);
        std.log.info("{d} - {d}", .{ next_node, index });
        c.YGNodeInsertChild(yg_node, yoga_elements.get(next_child).?, index);
        child = next.nodes.items[child].next_sibling;
        index += 1;
    }

    return next_node;
}

fn get_class_slice(prefix: []const u8, class: []const u8) ?[]const u8 {
    var splits = std.mem.split(u8, class, prefix);

    std.debug.assert(splits.next() != null);

    const maybe_value = splits.next();

    if (maybe_value) |value| {
        return value;
    }

    return null;
}

fn get_class_value(comptime T: type, prefix: []const u8, class: []const u8) ?T {
    var splits = std.mem.split(u8, class, prefix);

    std.debug.assert(splits.next() != null);

    const maybe_value = splits.next();

    if (maybe_value) |value| {
        const info = @typeInfo(T);

        if (info == .Float) {
            return std.fmt.parseFloat(T, value) catch null;
        }

        if (info == .Int) {
            return std.fmt.parseInt(T, value, 10) catch null;
        }

        return null;
    }

    return null;
}

pub fn apply_layout_style(yg_node: c.YGNodeRef, options: *const Options, class: []const u8) void {
    _ = options; // autofix
    if (get_class_value(f32, "w-", class)) |width| {
        c.YGNodeStyleSetWidth(yg_node, width);
    }

    if (get_class_value(f32, "h-", class)) |height| {
        c.YGNodeStyleSetHeight(yg_node, height);
    }

    if (get_class_value(f32, "m-", class)) |margin| {
        c.YGNodeStyleSetMargin(yg_node, c.YGEdgeAll, margin);
    }

    if (get_class_value(f32, "p-", class)) |padding| {
        c.YGNodeStyleSetPadding(yg_node, c.YGEdgeAll, padding);
    }

    // c.YGNodeStyleSetPositionType(yg_node, c.YGPositionTypeRelative);
    // c.YGNodeStyleSetDisplay(yg_node, c.YGDisplayFlex);
    // c.YGNodeStyleSetFlexDirection(yg_node, c.YGFlexDirectionColumn);

    // c.YGNodeStyleSetWidth(node, c.YGValue{.value = 200, .unit = c.YGUnitPoint});
    // c.YGNodeStyleSetHeight(node, c.YGValue{.value = 200, .unit = c.YGUnitPoint});
    // c.YGNodeStyleSetMargin(node, c.YGEdgeAll, 10.0);
}

pub fn diff(prev_dom: ?*Dom, next_dom: *Dom, prev_node: Dom.NodeId, next_node: Dom.NodeId, mutations: *std.ArrayList(Mutation)) !void {
    if (prev_node == Dom.InvalidNodeId) {
        try mutations.append(.{
            .replace = .{
                .prev = Dom.InvalidNodeId,
                .next = next_node,
            },
        });
    } else {
        const prev = &prev_dom.?.nodes.items[prev_node];
        const next = &next_dom.nodes.items[next_node];

        // key is different, we rebuild the entire subtree
        if (!std.mem.eql(u8, prev.attributes.key, next.attributes.key)) {
            try mutations.append(.{
                .replace = .{
                    .prev = prev_node,
                    .next = next_node,
                },
            });
        }

        std.log.info("{s} - {s}", .{ prev.attributes.class, next.attributes.class });

        // class is different, we update the node
        if (!std.mem.eql(u8, prev.attributes.class, next.attributes.class)) {
            try mutations.append(.{
                .updateClass = .{
                    .node = next_node,
                    .class = next.attributes.class,
                },
            });
        }
    }

    if (prev_dom == null) {
        return;
    }

    var maybe_prev_child = prev_dom.?.nodes.items[prev_node].first_child;
    var maybe_next_child = next_dom.nodes.items[next_node].first_child;

    while (maybe_prev_child != Dom.InvalidNodeId or maybe_next_child != Dom.InvalidNodeId) {
        if (maybe_prev_child == Dom.InvalidNodeId) {
            try mutations.append(.{ .replace = .{
                .prev = Dom.InvalidNodeId,
                .next = maybe_next_child,
            } });
        } else if (maybe_next_child == Dom.InvalidNodeId) {
            try mutations.append(.{ .replace = .{
                .prev = maybe_prev_child,
                .next = Dom.InvalidNodeId,
            } });
        } else {
            try diff(prev_dom, next_dom, maybe_prev_child, maybe_next_child, mutations);
        }

        maybe_prev_child = prev_dom.?.nodes.items[maybe_prev_child].next_sibling;
        maybe_next_child = next_dom.nodes.items[maybe_next_child].next_sibling;
    }
}

const NodeAttributes = struct {
    key: []const u8 = "",
    class: []const u8 = "",
    onclick: ?*const fn (Node) void = null,
    children: ?[]const Dom.NodeId = null,
};

pub const Style = struct {
    background_color: @Vector(4, u8) = @Vector(4, u8){ 0, 0, 0, 0 },
    /// text color
    color: @Vector(4, u8) = @Vector(4, u8){ 0, 0, 0, 255 },
    font_name: []const u8 = "default",
    rounding: f32 = 0.0,
};

const Node = struct {
    attributes: NodeAttributes,
    first_child: Dom.NodeId = Dom.InvalidNodeId,
    next_sibling: Dom.NodeId = Dom.InvalidNodeId,
    style: Style = Style{},

    pub fn init(attributes: NodeAttributes, options: *const Options) Node {
        var node = Node{
            .attributes = attributes,
        };
        node.init_style_from_attributes(options);

        return node;
    }

    pub fn init_style_from_attributes(self: *Node, options: *const Options) void {
        var classes = std.mem.splitSequence(u8, self.attributes.class, " ");
        while (classes.next()) |class| {
            if (get_class_value(f32, "rounding-", class)) |f| {
                self.style.rounding = f;
            }

            if (get_class_slice("bg-", class)) |color| {
                self.style.background_color = options.colors.get(color) orelse blk: {
                    std.debug.print("color not found: {s}\n", .{color});
                    break :blk @Vector(4, u8){ 0, 0, 0, 255 };
                };
            }

            if (get_class_slice("text-", class)) |color| {
                self.style.color = options.colors.get(color) orelse blk: {
                    std.debug.print("color not found: {s}\n", .{color});
                    break :blk @Vector(4, u8){ 0, 0, 0, 255 };
                };
            }
        }
    }
};

pub const Mutation = union(enum) {
    replace: struct {
        prev: Dom.NodeId,
        next: Dom.NodeId,
    },
    updateClass: struct {
        node: Dom.NodeId,
        class: []const u8,
    },
    updateOnClick: struct {
        node: Dom.NodeId,
        onclick: ?*const fn (Node) void,
    },
};
