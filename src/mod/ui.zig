const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @cImport({
    @cInclude("yoga/Yoga.h");
});
const FontManager = @import("font.zig");
const AnyPointer = @import("../libs/any-pointer.zig").AnyPointer;

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
    /// This data should persist between renders
    pub const Persistent = struct {
        hooks: std.ArrayListUnmanaged(AnyPointer) = .{},
        allocator: Allocator,
    };

    nodes: std.ArrayListUnmanaged(Node) = .{},
    allocator: Allocator,
    options: *const Options,
    // hooks: *HooksList,
    persistent: *Persistent,
    hooks_counter: u32 = 0,

    const Self = @This();

    pub const NodeId = usize;
    pub const InvalidNodeId: usize = std.math.maxInt(usize);

    pub fn init(allocator: Allocator, persistent: *Persistent, options: *const Options) Self {
        return Self{
            .allocator = allocator,
            .persistent = persistent,
            .options = options,
        };
    }

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

    pub fn c(self: *Self, comptime component: anytype) Self.NodeId {
        const interface: ComponentInterface = @constCast(component).renderable(self);
        return interface.func_ptr(interface.obj_ptr);
    }

    pub fn fmt(self: *Self, comptime format: []const u8, args: anytype) []u8 {
        return std.fmt.allocPrint(self.allocator, format, args) catch unreachable;
    }

    ///
    ///
    /// example input:
    ///
    /// ```zig
    /// pub fn list(ui: *zui, item: T, index: usize) zui.ViewNode {
    ///    return ui.v(.{});
    /// }
    /// ```
    pub fn foreach(self: *Self, component: Component, comptime T: type, items: []const T, cb: *const fn (component: Component, item: T, index: usize) Dom.NodeId) []Dom.NodeId {
        var children = self.allocator.alloc(Dom.NodeId, items.len) catch unreachable;
        for (items, 0..) |item, index| {
            children[index] = cb(component, item, index);
        }

        return children;
    }

    pub const Event = union(enum) {
        click: struct {
            x: f32,
            y: f32,
        },
    };

    pub fn handle_event(self: *Self, yoga_elements: *YogaElements, parent_offset: @Vector(2, f32), node_id: Self.NodeId, event: Event) void {
        const node = &self.nodes.items[node_id];
        const yoga_node = yoga_elements.get(node_id).?;

        const rect = @Vector(4, f32){
            parent_offset[0] + Yoga.YGNodeLayoutGetLeft(yoga_node),
            parent_offset[1] + Yoga.YGNodeLayoutGetTop(yoga_node),
            Yoga.YGNodeLayoutGetWidth(yoga_node),
            Yoga.YGNodeLayoutGetHeight(yoga_node),
        };

        switch (event) {
            .click => |data| {
                if (rect[0] <= data.x and data.x <= rect[0] + rect[2] and rect[1] <= data.y and data.y <= rect[1] + rect[3]) {
                    if (node.attributes.onclick) |listener| {
                        listener.call(event);
                    }
                }
            },
        }

        var child = node.first_child;
        while (child != Self.InvalidNodeId) {
            const child_node = self.nodes.items[child];
            self.handle_event(yoga_elements, @Vector(2, f32){ rect[0], rect[1] }, child, event);
            child = child_node.next_sibling;
        }
    }
};

const Listener = struct {
    func_ptr: *const fn (component: Component, event: Dom.Event) void,
    component: Component,

    pub fn call(self: @This(), event: Dom.Event) void {
        self.func_ptr(self.component, event);
    }
};

pub const ComponentInterface = struct {
    obj_ptr: Component,
    func_ptr: *const fn (ptr: Component) Dom.NodeId,
};

const ComponentKey = struct {
    id: u32,
    key: []const u8,

    const ComponentKeyContext = struct {
        pub fn hash(self: @This(), s: ComponentKey) u32 {
            _ = self;

            var h = std.hash.XxHash32.init(0);
            h.update(s.key);

            return h.final() + s.id;
        }

        pub fn eql(self: @This(), a: ComponentKey, b: ComponentKey, b_index: usize) bool {
            _ = self;
            _ = b_index;

            if (a.id != b.id) {
                return false;
            }

            return std.mem.eql(u8, a.key, b.key);
        }
    };
};

pub const Component = struct {
    /// this ptr holds the actual component data, like your custom struct
    ptr: *anyopaque,
    /// we store the ui pointer in the component so its easier to call methods
    dom: *Dom,

    const Self = @This();

    pub inline fn cast(self: Self, T: type) *T {
        return @ptrCast(@alignCast(self.ptr));
    }

    pub fn listener(self: Self, func_ptr: *const fn (c: Self, event: Dom.Event) void) Listener {
        return Listener{
            .func_ptr = func_ptr,
            .component = self,
        };
    }

    pub fn foreach(self: Self, comptime T: type, items: []const T, cb: *const fn (component: Self, item: T, index: usize) Dom.NodeId) []Dom.NodeId {
        return self.dom.foreach(self, T, items, cb);
    }
};

pub fn create_ref(
    comptime T: type,
) type {
    return struct {
        value: *T,
        component: Component,

        pub fn init(
            component: Component,
            initial_value: T,
        ) @This() {
            if (component.dom.persistent.hooks.items.len > component.dom.hooks_counter) {
                const hook = component.dom.persistent.hooks.items[component.dom.hooks_counter].cast(*T);
                component.dom.hooks_counter += 1;
                return @This(){
                    .value = hook,
                    .component = component,
                };
            }

            const ptr = component.dom.persistent.allocator.create(T) catch unreachable;
            ptr.* = initial_value;
            const make = AnyPointer.make(*T, ptr);
            component.dom.persistent.hooks.append(component.dom.persistent.allocator, make) catch unreachable;
            component.dom.hooks_counter += 1;

            return @This(){
                .value = make.cast(*T),
                .component = component,
            };
        }

        pub inline fn get(self: @This()) T {
            return self.value.*;
        }

        pub inline fn set(self: @This(), value: T) void {
            self.value.* = value;
        }
    };
}

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
    // TODO: use the measure callbacks instead to support wrapping text
    if (text.len > 0) {
        const font_name = getClassSlice("font-", class) orelse "default";
        const desc = options.font_name_to_desc.get(font_name);

        if (desc) |font_desc| {
            const atlas = options.font_manager.atlases.get(font_desc).?;
            const size = atlas.measure(text);

            c.YGNodeStyleSetWidth(yg_node, size[0]);
            c.YGNodeStyleSetHeight(yg_node, size[1]);
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

    // gap
    if (getClassValue(f32, "gap-", class)) |gap| {
        c.YGNodeStyleSetGap(yg_node, c.YGGutterAll, gap);
    }

    if (getClassValue(f32, "gap-x-", class)) |gap| {
        c.YGNodeStyleSetGap(yg_node, c.YGGutterColumn, gap);
    }

    if (getClassValue(f32, "gap-y-", class)) |gap| {
        c.YGNodeStyleSetGap(yg_node, c.YGGutterRow, gap);
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
    onclick: ?Listener = null,
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
        if (getClassSlice("font-", class)) |font_name| {
            self.style.font_name = font_name;
        }

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
