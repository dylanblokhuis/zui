const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @cImport({
    @cInclude("yoga/Yoga.h");
});
const FontManager = @import("font.zig");
const AnyPointer = @import("../libs/any-pointer.zig").AnyPointer;
const Self = @This();

pub const YogaNodeRef = c.YGNodeRef;

pub const Yoga = c;

pub const YogaElements = std.AutoHashMap(usize, YogaNodeRef);

allocator: Allocator,
options: *const Options,
// hooks: *HooksList,
persistent: *Persistent,
id_counter: usize = 0,
hooks_counter: u32 = 0,

pub const Options = struct {
    font_manager: FontManager,
    font_name_to_desc: std.StringHashMapUnmanaged(FontManager.FontDesc),
    colors: std.StringHashMap(@Vector(4, u8)),

    pub fn init(allocator: Allocator) @This() {
        return @This(){
            .colors = std.StringHashMap(@Vector(4, u8)).init(allocator),
            .font_name_to_desc = std.StringHashMapUnmanaged(FontManager.FontDesc){},
            .font_manager = FontManager.init(allocator),
        };
    }

    pub fn loadFont(self: *@This(), allocator: Allocator, name: []const u8, desc: FontManager.FontDesc) !void {
        try self.font_manager.create_atlas(desc, allocator);
        try self.font_name_to_desc.put(allocator, name, desc);
    }
};

pub const Hook = struct {
    ptr: AnyPointer,
    last_changed: usize,

    pub fn init(ptr: AnyPointer, dom_id: usize) @This() {
        return @This(){ .ptr = ptr, .last_changed = dom_id };
    }
};

pub const Node = struct {
    const Attributes = struct {
        key: []const u8 = "",
        class: []const u8 = "",
        text: []const u8 = "",
        onclick: ?Listener = null,
        children: ?[]const *Self.Node = null,
    };

    pub const Style = struct {
        background_color: @Vector(4, u8) = @Vector(4, u8){ 0, 0, 0, 0 },
        /// text color
        color: @Vector(4, u8) = @Vector(4, u8){ 0, 0, 0, 255 },
        font_name: []const u8 = "default",
        rounding: f32 = 0.0,
    };

    id: usize = std.math.maxInt(usize),
    attributes: Attributes,
    first_child: ?*Node = null,
    next_sibling: ?*Node = null,
    yoga_ref: YogaNodeRef = null,
    style: Style = Style{},

    pub fn init(attributes: Attributes, options: *const Options) Node {
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

        if (getClassValue(f32, "rounded-", class)) |f| {
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

// pub const InvalidNodeId: usize = std.math.maxInt(usize);

/// This data should persist between renders
pub const Persistent = struct {
    id: usize = 0,
    hooks: std.ArrayListUnmanaged(Hook) = .{},
    allocator: Allocator,
};

pub fn init(allocator: Allocator, persistent: *Persistent, options: *const Options) Self {
    // TODO: we should prob just move this into a bool to save memory
    persistent.id = (persistent.id + 1) % std.math.maxInt(usize);
    return Self{
        .allocator = allocator,
        .persistent = persistent,
        .options = options,
    };
}

pub fn view(self: *Self, attributes: Node.Attributes) *Node {
    const parent = self.allocator.create(Node) catch unreachable;
    parent.* = Node.init(attributes, self.options);

    if (attributes.children) |children| {
        for (children) |child_ptr| {
            if (parent.first_child == null) {
                parent.first_child = child_ptr;
            } else {
                var child = parent.first_child;
                while (child) |item| {
                    if (item.next_sibling == null) {
                        item.next_sibling = child_ptr;
                        break;
                    }
                    child = item.next_sibling;
                }
            }
        }
    }

    return parent;
}

pub fn text(self: *Self, class: []const u8, string: []const u8) *Node {
    return self.view(.{
        .text = string,
        .class = class,
    });
}

pub fn custom(self: *Self, comptime component: anytype) *Node {
    const type_info = @typeInfo(@TypeOf(component));
    if (type_info == .Pointer) {
        if (!@hasDecl(type_info.Pointer.child, "renderable")) {
            @compileError("Component must have a renderable method");
        }
        if (type_info.Pointer.size != .One) {
            @compileError("Component must be single pointer, cannot be a slice or a many pointer");
        }
    } else {
        @compileError("Component must be a pointer");
    }

    const interface: Component.Interface = @constCast(component).renderable(self);
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
pub fn foreach(self: *Self, component: Component, comptime T: type, items: []const T, cb: *const fn (component: Component, item: T, index: usize) *Node) []*Node {
    var children = self.allocator.alloc(*Node, items.len) catch unreachable;
    for (items, 0..) |item, index| {
        children[index] = cb(component, item, index);
    }
    return children;
}

pub fn tree(self: *Self, root: *Node) *Node {
    root.id = self.id_counter;
    self.id_counter += 1;

    var node: ?*Node = root.first_child;
    while (node) |item| {
        _ = self.tree(item);
        node = item.next_sibling;
    }

    return root;
}

pub fn print_tree(self: *Self, node: *Node, depth: u32) void {
    if (depth == 0) {
        std.debug.print("\nTree:\n", .{});
    }
    // indent based on depth
    for (0..depth) |_| {
        std.debug.print("  ", .{});
    }

    std.debug.print("Node: {d}\n", .{node.id});
    var maybe_node: ?*Node = node.first_child;
    while (maybe_node) |item| {
        self.print_tree(item, depth + 1);
        maybe_node = item.next_sibling;
    }
}

pub const Event = union(enum) {
    click: struct {
        x: f32,
        y: f32,
    },
};

pub fn handle_event(self: *Self, yoga_elements: *YogaElements, parent_offset: @Vector(2, f32), node: *Node, event: Event) void {
    const yoga_node = yoga_elements.get(node.id).?;

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

    var maybe_child = node.first_child;
    while (maybe_child) |child| {
        self.handle_event(yoga_elements, @Vector(2, f32){ rect[0], rect[1] }, child, event);
        maybe_child = child.next_sibling;
    }
}

const Listener = struct {
    func_ptr: *const fn (component: Component, event: Self.Event) void,
    component: Component,

    pub fn call(self: @This(), event: Self.Event) void {
        self.func_ptr(self.component, event);
    }
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
    pub const Interface = struct {
        obj_ptr: Component,
        func_ptr: *const fn (ptr: Component) *Self.Node,
    };

    /// this ptr holds the actual component data, like your custom struct
    ptr: *anyopaque,
    /// we store the ui pointer in the component so its easier to call methods
    dom: *Self,

    pub inline fn cast(self: @This(), T: type) struct { *T, *Self } {
        return .{ @ptrCast(@alignCast(self.ptr)), self.dom };
    }

    pub fn listener(self: @This(), func_ptr: *const fn (c: @This(), event: Self.Event) void) Listener {
        return Listener{
            .func_ptr = func_ptr,
            .component = self,
        };
    }

    pub inline fn arena(self: @This()) Allocator {
        return self.dom.allocator;
    }

    pub inline fn gpa(self: @This()) Allocator {
        return self.dom.persistent.allocator;
    }

    // pub fn foreach(self: Self, comptime T: type, items: []const T, cb: *const fn (component: Self, item: T, index: usize) *Node) []*Node {
    //     return self.dom.foreach(self, T, items, cb);
    // }

    pub fn useRef(
        comptime T: type,
    ) type {
        return struct {
            id: usize,
            component: Component,

            pub fn init(
                component: Component,
                initial_value: T,
            ) @This() {
                if (component.dom.persistent.hooks.items.len > component.dom.hooks_counter) {
                    const hook_id = component.dom.hooks_counter;
                    component.dom.hooks_counter += 1;
                    return @This(){
                        .id = hook_id,
                        .component = component,
                    };
                }

                const ptr = component.dom.persistent.allocator.create(T) catch unreachable;
                ptr.* = initial_value;
                const make = AnyPointer.make(*T, ptr);
                component.dom.persistent.hooks.append(component.dom.persistent.allocator, Self.Hook.init(make, component.dom.persistent.id)) catch unreachable;
                const hook_id = component.dom.hooks_counter;
                component.dom.hooks_counter += 1;

                return @This(){
                    .id = hook_id,
                    .component = component,
                };
            }

            pub inline fn get(self: @This()) *T {
                return self.component.dom.persistent.hooks.items[self.id].ptr.cast(*T);
            }

            pub inline fn set(self: @This(), value: T) void {
                self.component.dom.persistent.hooks.items[self.id].ptr.cast(*T).* = value;
                self.component.dom.persistent.hooks.items[self.id].last_changed = self.component.dom.persistent.id;
            }
        };
    }

    pub fn useEffect(
        component: Component,
        callback: *const fn (component: Component) void,
        dependencies: []const usize,
    ) void {
        var any_mutated = false;
        for (dependencies) |dep| {
            if (component.dom.persistent.hooks.items[dep].last_changed == (component.dom.persistent.id - 1)) {
                any_mutated = true;
                break;
            }
        }

        if (!any_mutated) {
            return;
        }

        callback(component);
    }
};

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

const YogaContext = struct {
    class: []const u8,
};

pub fn applyLayoutStyle(yg_node: c.YGNodeRef, options: *const Options, class: []const u8, text_value: []const u8) void {
    // TODO: we need to reset the node here if the class was different last frame
    // TODO: use the measure callbacks instead to support wrapping text
    if (text_value.len > 0) {
        const font_name = getClassSlice("font-", class) orelse "default";
        const desc = options.font_name_to_desc.get(font_name);

        if (desc) |font_desc| {
            const atlas = options.font_manager.atlases.get(font_desc).?;
            const size = atlas.measure(text_value);
            c.YGNodeStyleSetMinWidth(yg_node, size[0]);
            c.YGNodeStyleSetMinHeight(yg_node, size[1]);
            c.YGNodeStyleSetWidthAuto(yg_node);
            c.YGNodeStyleSetHeightAuto(yg_node);
            // c.YGNodeStyleSetWidth(yg_node, size[0]);
            // c.YGNodeStyleSetHeight(yg_node, size[1]);
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
