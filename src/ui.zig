const std = @import("std");
const layout = @import("./libs/layout/layout.zig");
const Allocator = std.mem.Allocator;

/// # remaining stuff
///
/// how to do if statements
allocator: Allocator,

colors: std.StringHashMap([4]u8),

fonts: std.StringArrayHashMap([]const u8),

layout: layout.Layout,

// nodes: std.MultiArrayList(ViewNode),

const Self = @This();

pub fn init(allocator: Allocator) !Self {
    var colors = std.StringHashMap([4]u8).init(std.heap.c_allocator);

    // TODO: add more colors
    try colors.put("red", [4]u8{ 255, 0, 0, 255 });
    try colors.put("green", [4]u8{ 0, 255, 0, 255 });
    try colors.put("blue", [4]u8{ 0, 0, 255, 255 });
    try colors.put("yellow", [4]u8{ 255, 255, 0, 255 });
    try colors.put("black", [4]u8{ 0, 0, 0, 255 });
    try colors.put("white", [4]u8{ 255, 255, 255, 255 });
    try colors.put("indigo", [4]u8{ 75, 0, 130, 255 });

    return Self{
        .allocator = allocator,
        .colors = colors,
        .fonts = std.StringArrayHashMap([]const u8).init(std.heap.c_allocator),
        .layout = try layout.Layout.init(),
    };
}

pub const p = struct {
    class: []const u8,
    text: []const u8 = "",
    on_click: ?*const fn () void = null,
    children: ?[]ViewNode = null,
};

pub const ViewNode = struct {
    class: []const u8 = "",
    text: []const u8 = "",
    on_click: ?*const fn () void = null,
    children: ?[]ViewNode = null,
    layout_id: layout.LayId,
    bg_color: [4]u8 = [4]u8{ 0, 0, 0, 0 },
    text_color: [4]u8 = [4]u8{ 255, 255, 255, 255 },
    text_size: f32 = 14.0,
    rounding: f32 = 0.0,
    font_name: []const u8 = "default",
};

/// function to make a singular view node
pub fn v(self: *Self, props: p) ViewNode {
    std.log.debug("{s}", .{props.class});
    const id = self.layout.create_leaf();

    if (props.children) |children| {
        for (children) |child| {
            self.layout.add_child(id, child.layout_id);
        }
    }

    return ViewNode{
        .class = props.class,
        .text = props.text,
        .on_click = props.on_click,
        .children = props.children,
        .layout_id = id,
    };
}

// pub fn t(self: *Self, text: []const u8) ViewNode {
//     _ = self; // autofix

//     return ViewNode{
//         .text = text,
//         .children = null,
//     };
// }

/// function to make an array of view nodes
pub fn vv(self: *Self, children: []const ViewNode) []ViewNode {
    const nodes = self.allocator.alloc(ViewNode, children.len) catch unreachable;
    for (children, 0..) |child, index| {
        nodes[index] = child;
    }

    return nodes;
}

pub fn foreach(self: *Self, comptime T: type, cb: *const fn (self: *Self, item: T, index: usize) ViewNode, items: []const T) []ViewNode {
    var children = self.allocator.alloc(ViewNode, items.len) catch unreachable;
    for (items, 0..) |item, index| {
        children[index] = cb(self, item, index);
    }

    return children;
}

pub fn fmt(self: *Self, comptime format: []const u8, args: anytype) []u8 {
    return std.fmt.allocPrint(self.allocator, format, args) catch unreachable;
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

fn get_class_slice(prefix: []const u8, class: []const u8) ?[]const u8 {
    var splits = std.mem.split(u8, class, prefix);

    std.debug.assert(splits.next() != null);

    const maybe_value = splits.next();

    if (maybe_value) |value| {
        return value;
    }

    return null;
}

fn get_class_color(self: *Self, prefix: []const u8, class: []const u8) ?[4]u8 {
    var splits = std.mem.split(u8, class, prefix);

    std.debug.assert(splits.next() != null);

    const maybe_color = splits.next();

    if (maybe_color) |color| {
        return self.colors.get(color);
    }

    return null;
}

const Style = struct {
    is_column: bool = false,
    align_items: enum {
        start,
        center,
        end,
    } = .start,

    width: i16 = 0,
    height: i16 = 0,

    margin_left: i16 = 0,
    margin_right: i16 = 0,
    margin_top: i16 = 0,
    margin_bottom: i16 = 0,

    bg_color: [4]u8 = [4]u8{ 0, 0, 0, 0 },
    text_color: [4]u8 = [4]u8{ 0, 0, 0, 0 },
    text_size: f32 = 0.0,
    font_name: []const u8 = "default",

    rounding: f32 = 0.0,
};

fn get_style(self: *Self, class: []const u8) Style {
    var classes = std.mem.splitSequence(u8, class, " ");

    var style = Style{};

    while (classes.next()) |chunk| {
        if (std.mem.eql(u8, chunk, "row")) {
            style.is_column = false;
        }

        if (std.mem.eql(u8, chunk, "col")) {
            style.is_column = true;
        }

        if (get_class_value(i16, "w-", chunk)) |width| {
            style.width = width;
        }

        if (get_class_value(i16, "h-", chunk)) |height| {
            style.height = height;
        }

        // margin
        if (get_class_value(i16, "m-", chunk)) |margin| {
            style.margin_left = margin;
            style.margin_right = margin;
            style.margin_top = margin;
            style.margin_bottom = margin;
        }

        if (get_class_value(i16, "mx-", chunk)) |margin| {
            style.margin_left = margin;
            style.margin_right = margin;
        }

        if (get_class_value(i16, "my-", chunk)) |margin| {
            style.margin_top = margin;
            style.margin_bottom = margin;
        }

        if (get_class_value(i16, "ml-", chunk)) |margin| {
            style.margin_left = margin;
        }

        if (get_class_value(i16, "mr-", chunk)) |margin| {
            style.margin_right = margin;
        }

        if (get_class_value(i16, "mt-", chunk)) |margin| {
            style.margin_top = margin;
        }

        if (get_class_value(i16, "mb-", chunk)) |margin| {
            style.margin_bottom = margin;
        }

        if (self.get_class_color("bg-", chunk)) |color| {
            style.bg_color = color;
        }

        if (get_class_value(f32, "rounded-", chunk)) |rounding| {
            style.rounding = rounding;
        }

        if (get_class_value(f32, "text-", chunk)) |text_size| {
            style.text_size = text_size;
        }

        if (get_class_slice("font-", chunk)) |font_name| {
            style.font_name = font_name;
        }

        if (get_class_slice("items-", chunk)) |align_items| {
            if (std.mem.eql(u8, align_items, "start")) {
                style.align_items = .start;
            }

            if (std.mem.eql(u8, align_items, "center")) {
                style.align_items = .center;
            }

            if (std.mem.eql(u8, align_items, "end")) {
                style.align_items = .end;
            }
        }
    }

    return style;
}

fn compute_layout_inner(self: *Self, node: *ViewNode) void {
    const style = self.get_style(node.class);
    node.bg_color = style.bg_color;
    node.rounding = style.rounding;
    node.text_size = style.text_size;
    node.font_name = style.font_name;

    self.layout.set_size_xy(node.layout_id, style.width, style.height);
    self.layout.set_margins_ltrb(node.layout_id, style.margin_left, style.margin_top, style.margin_right, style.margin_bottom);

    if (node.children) |children| {
        for (children) |*child| {
            compute_layout_inner(self, @constCast(child));
        }
    }
}

/// computes the layout for the whole tree and sets the layout property
pub fn compute_layout(self: *Self, root: *ViewNode) void {
    self.compute_layout_inner(root);
    self.layout.run(root.layout_id);
}
