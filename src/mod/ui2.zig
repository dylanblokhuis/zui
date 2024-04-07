const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @cImport({
    @cInclude("yoga/Yoga.h");
});
const FontManager = @import("font.zig");

pub const YogaNodeRef = c.YGNodeRef;
pub const CalculateLayout = c.YGNodeCalculateLayout;
pub const LayoutDirectionLTR = c.YGDirectionLTR;

pub const Yoga = c;

pub const YogaElements = std.AutoHashMap(Dom.NodeId, YogaNodeRef);

pub const Options = struct {
    font_manager: FontManager,
    font_name_to_desc: std.StringHashMapUnmanaged(FontManager.FontDesc),
    colors: std.StringHashMap(@Vector(4, u8)),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .colors = std.StringHashMap(@Vector(4, u8)).init(allocator),
            .font_name_to_desc = std.StringHashMapUnmanaged(FontManager.FontDesc){},
            .font_manager = FontManager.init(allocator),
        };
    }

    pub fn loadFont(self: *Self, allocator: Allocator, name: []const u8, desc: FontManager.FontDesc) !void {
        try self.font_manager.create_atlas(desc, allocator);
        try self.font_name_to_desc.put(allocator, name, desc);
    }
};

pub const Dom = struct {
    nodes: std.ArrayListUnmanaged(Node) = std.ArrayListUnmanaged(Node){},
    allocator: Allocator,
    options: *const Options,

    const Self = @This();

    pub const NodeId = usize;
    pub const InvalidNodeId: usize = std.math.maxInt(usize);

    pub fn init(allocator: Allocator, options: *const Options) Self {
        return Self{
            .allocator = allocator,
            .options = options,
        };
    }

    // pub fn root(self: *Self, node_id: Self.NodeId) Self.NodeId {
    //     return self.nodes.items.len - 1;
    // }

    pub fn appendChild(self: *Self, parent_id: Self.NodeId, child_id: Self.NodeId) void {
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
        self.nodes.append(self.allocator, Node.init(attributes, self.options)) catch unreachable;
        const parent_id = self.nodes.items.len - 1;

        if (attributes.children) |children| {
            for (children) |child_id| {
                self.appendChild(parent_id, child_id);
            }
        }

        return parent_id;
    }

    pub fn text(self: *Self, class: []const u8, string: []const u8) Self.NodeId {
        return self.view(.{
            .text = string,
            .class = class,
        });
    }

    pub fn fmt(self: *Self, comptime format: []const u8, args: anytype) []u8 {
        return std.fmt.allocPrint(self.allocator, format, args) catch unreachable;
    }
};

pub fn replace(prev: ?*Dom, next: *Dom, prev_node: Dom.NodeId, next_node: Dom.NodeId, yoga_elements: *YogaElements, options: *const Options) !Dom.NodeId {
    if (prev_node != Dom.InvalidNodeId) {
        const maybe_yg_node = yoga_elements.get(prev_node);
        if (maybe_yg_node) |yg_node| {
            c.YGNodeFreeRecursive(yg_node);
        }
        _ = yoga_elements.remove(prev_node);
    }

    const yg_node = c.YGNodeNew();
    const text = next.nodes.items[next_node].attributes.text;
    var classes = std.mem.splitSequence(u8, next.nodes.items[next_node].attributes.class, " ");
    while (classes.next()) |class| {
        applyLayoutStyle(yg_node, options, class, text);
    }
    try yoga_elements.put(next_node, yg_node);

    var child = next.nodes.items[next_node].first_child;
    var index: usize = 0;
    while (child != Dom.InvalidNodeId) {
        const next_child = try replace(prev, next, Dom.InvalidNodeId, child, yoga_elements, options);
        c.YGNodeInsertChild(yg_node, yoga_elements.get(next_child).?, index);
        child = next.nodes.items[child].next_sibling;
        index += 1;
    }

    return next_node;
}

fn getClassSlice(prefix: []const u8, class: []const u8) ?[]const u8 {
    var splits = std.mem.split(u8, class, prefix);

    std.debug.assert(splits.next() != null);

    const maybe_value = splits.next();

    if (maybe_value) |value| {
        return value;
    }

    return null;
}

fn getClassValue(comptime T: type, prefix: []const u8, class: []const u8) ?T {
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

pub fn applyLayoutStyle(yg_node: c.YGNodeRef, options: *const Options, class: []const u8, text: []const u8) void {
    if (text.len > 0) {
        if (getClassSlice("font-", class)) |font_name| {
            const desc = options.font_name_to_desc.get(font_name);

            if (desc) |font_desc| {
                const atlas = options.font_manager.atlases.get(font_desc).?;
                const size = atlas.measure(text);

                c.YGNodeStyleSetWidth(yg_node, size[0]);
                c.YGNodeStyleSetHeight(yg_node, size[1]);
            }
        }
    }

    if (getClassValue(f32, "w-", class)) |width| {
        c.YGNodeStyleSetWidth(yg_node, width);
    }

    if (getClassValue(f32, "h-", class)) |height| {
        c.YGNodeStyleSetHeight(yg_node, height);
    }

    if (getClassValue(f32, "m-", class)) |margin| {
        c.YGNodeStyleSetMargin(yg_node, c.YGEdgeAll, margin);
    }

    if (getClassValue(f32, "p-", class)) |padding| {
        c.YGNodeStyleSetPadding(yg_node, c.YGEdgeAll, padding);
    }

    if (std.mem.eql(u8, "relative", class)) {
        c.YGNodeStyleSetPositionType(yg_node, c.YGPositionTypeRelative);
    }

    if (std.mem.eql(u8, "absolute", class)) {
        c.YGNodeStyleSetPositionType(yg_node, c.YGPositionTypeAbsolute);
    }

    // display
    if (std.mem.eql(u8, "flex", class)) {
        c.YGNodeStyleSetDisplay(yg_node, c.YGDisplayFlex);
    }

    if (std.mem.eql(u8, "hidden", class)) {
        c.YGNodeStyleSetDisplay(yg_node, c.YGDisplayNone);
    }

    // flex direction
    if (std.mem.eql(u8, "flex-col", class)) {
        c.YGNodeStyleSetFlexDirection(yg_node, c.YGFlexDirectionColumn);
    }

    if (std.mem.eql(u8, "flex-row", class)) {
        c.YGNodeStyleSetFlexDirection(yg_node, c.YGFlexDirectionRow);
    }

    // wrapping
    if (std.mem.eql(u8, "flex-wrap", class)) {
        c.YGNodeStyleSetFlexWrap(yg_node, c.YGWrapWrap);
    }

    if (std.mem.eql(u8, "flex-nowrap", class)) {
        c.YGNodeStyleSetFlexWrap(yg_node, c.YGWrapNoWrap);
    }

    if (std.mem.eql(u8, "flex-wrap-reverse", class)) {
        c.YGNodeStyleSetFlexWrap(yg_node, c.YGWrapWrapReverse);
    }

    // items-*
    if (getClassSlice("items-", class)) |align_items| {
        if (std.mem.eql(u8, "start", align_items)) {
            c.YGNodeStyleSetAlignItems(yg_node, c.YGAlignFlexStart);
        }

        if (std.mem.eql(u8, "center", align_items)) {
            c.YGNodeStyleSetAlignItems(yg_node, c.YGAlignCenter);
        }

        if (std.mem.eql(u8, "end", align_items)) {
            c.YGNodeStyleSetAlignItems(yg_node, c.YGAlignFlexEnd);
        }

        if (std.mem.eql(u8, "stretch", align_items)) {
            c.YGNodeStyleSetAlignItems(yg_node, c.YGAlignStretch);
        }
    }

    // justify-*
    if (getClassSlice("justify-", class)) |justify_content| {
        if (std.mem.eql(u8, "start", justify_content)) {
            c.YGNodeStyleSetJustifyContent(yg_node, c.YGJustifyFlexStart);
        }

        if (std.mem.eql(u8, "center", justify_content)) {
            c.YGNodeStyleSetJustifyContent(yg_node, c.YGJustifyCenter);
        }

        if (std.mem.eql(u8, "end", justify_content)) {
            c.YGNodeStyleSetJustifyContent(yg_node, c.YGJustifyFlexEnd);
        }

        if (std.mem.eql(u8, "between", justify_content)) {
            c.YGNodeStyleSetJustifyContent(yg_node, c.YGJustifySpaceBetween);
        }

        if (std.mem.eql(u8, "around", justify_content)) {
            c.YGNodeStyleSetJustifyContent(yg_node, c.YGJustifySpaceAround);
        }

        if (std.mem.eql(u8, "evenly", justify_content)) {
            c.YGNodeStyleSetJustifyContent(yg_node, c.YGJustifySpaceEvenly);
        }
    }
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

        // class is different, we update the node
        if (!std.mem.eql(u8, prev.attributes.class, next.attributes.class)) {
            try mutations.append(.{
                .updateClass = .{
                    .node = next_node,
                    .class = next.attributes.class,
                },
            });
        }

        if (!std.mem.eql(u8, prev.attributes.text, next.attributes.text)) {
            try mutations.append(.{
                .updateText = .{
                    .node = next_node,
                    .text = next.attributes.text,
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

        if (maybe_prev_child == Dom.InvalidNodeId) {
            break;
        }
        maybe_prev_child = prev_dom.?.nodes.items[maybe_prev_child].next_sibling;
        maybe_next_child = next_dom.nodes.items[maybe_next_child].next_sibling;
    }
}

const NodeAttributes = struct {
    key: []const u8 = "",
    class: []const u8 = "",
    text: []const u8 = "",
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

pub const Node = struct {
    attributes: NodeAttributes,
    first_child: Dom.NodeId = Dom.InvalidNodeId,
    next_sibling: Dom.NodeId = Dom.InvalidNodeId,
    style: Style = Style{},

    pub fn init(attributes: NodeAttributes, options: *const Options) Node {
        var node = Node{
            .attributes = attributes,
        };
        node.setStyleFromAttributes(options);

        return node;
    }

    pub fn setStyleFromAttributes(self: *Node, options: *const Options) void {
        var classes = std.mem.splitSequence(u8, self.attributes.class, " ");
        while (classes.next()) |class| {
            self.applyStyle(options, class);
        }
    }

    pub fn applyStyle(self: *Node, options: *const Options, class: []const u8) void {
        if (getClassValue(f32, "rounding-", class)) |f| {
            self.style.rounding = f;
        }

        if (getClassSlice("bg-", class)) |color| {
            self.style.background_color = options.colors.get(color) orelse blk: {
                std.debug.print("color not found: {s}\n", .{color});
                break :blk @Vector(4, u8){ 0, 0, 0, 255 };
            };
        }

        if (getClassSlice("text-", class)) |color| {
            self.style.color = options.colors.get(color) orelse blk: {
                std.debug.print("color not found: {s}\n", .{color});
                break :blk @Vector(4, u8){ 0, 0, 0, 255 };
            };
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
    updateText: struct {
        node: Dom.NodeId,
        text: []const u8,
    },
    updateOnClick: struct {
        node: Dom.NodeId,
        onclick: ?*const fn (Node) void,
    },
};
