const std = @import("std");
const Allocator = std.mem.Allocator;

/// # remaining stuff
///
/// how to do if statements
allocator: Allocator,

colors: std.StringHashMap([4]u8),

fonts: std.StringArrayHashMap([]const u8),

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
    };
}

pub const p = struct {
    class: []const u8,
    text: []const u8 = "",
    on_click: ?*const fn () void = null,
    children: ?[]ViewNode = null,
};

pub const Layout = struct {
    width: f32,
    height: f32,
    x: f32,
    y: f32,
};

pub const ViewNode = struct {
    class: []const u8 = "",
    text: []const u8 = "",
    on_click: ?*const fn () void = null,
    children: ?[]ViewNode = null,
    computed_layout: ?Layout = null,
    bg_color: [4]u8 = [4]u8{ 0, 0, 0, 0 },
    text_color: [4]u8 = [4]u8{ 255, 255, 255, 255 },
    text_size: f32 = 14.0,
    rounding: f32 = 0.0,
    font_name: []const u8 = "default",
};

/// function to make a singular view node
pub fn v(self: *Self, props: p) ViewNode {
    _ = self; // autofix

    return ViewNode{
        .class = props.class,
        .text = props.text,
        .on_click = props.on_click,
        .children = props.children,
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

fn get_class_value(prefix: []const u8, class: []const u8) ?f32 {
    var splits = std.mem.split(u8, class, prefix);

    std.debug.assert(splits.next() != null);

    const maybe_value = splits.next();

    if (maybe_value) |value| {
        return std.fmt.parseFloat(f32, value) catch null;
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

    width: f32 = 0.0,
    height: f32 = 0.0,

    padding_left: f32 = 0.0,
    padding_right: f32 = 0.0,
    padding_top: f32 = 0.0,
    padding_bottom: f32 = 0.0,

    margin_left: f32 = 0.0,
    margin_right: f32 = 0.0,
    margin_top: f32 = 0.0,
    margin_bottom: f32 = 0.0,

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

        if (get_class_value("w-", chunk)) |width| {
            style.width = width;
        }

        if (get_class_value("h-", chunk)) |height| {
            style.height = height;
        }

        // padding
        if (get_class_value("p-", chunk)) |padding| {
            style.padding_left = padding;
            style.padding_right = padding;
            style.padding_top = padding;
            style.padding_bottom = padding;
        }

        if (get_class_value("px-", chunk)) |padding| {
            style.padding_left = padding;
            style.padding_right = padding;
        }

        if (get_class_value("py-", chunk)) |padding| {
            style.padding_top = padding;
            style.padding_bottom = padding;
        }

        if (get_class_value("pl-", chunk)) |padding| {
            style.padding_left = padding;
        }

        if (get_class_value("pr-", chunk)) |padding| {
            style.padding_right = padding;
        }

        if (get_class_value("pt-", chunk)) |padding| {
            style.padding_top = padding;
        }

        if (get_class_value("pb-", chunk)) |padding| {
            style.padding_bottom = padding;
        }

        // margin
        if (get_class_value("m-", chunk)) |margin| {
            style.margin_left = margin;
            style.margin_right = margin;
            style.margin_top = margin;
            style.margin_bottom = margin;
        }

        if (get_class_value("mx-", chunk)) |margin| {
            style.margin_left = margin;
            style.margin_right = margin;
        }

        if (get_class_value("my-", chunk)) |margin| {
            style.margin_top = margin;
            style.margin_bottom = margin;
        }

        if (get_class_value("ml-", chunk)) |margin| {
            style.margin_left = margin;
        }

        if (get_class_value("mr-", chunk)) |margin| {
            style.margin_right = margin;
        }

        if (get_class_value("mt-", chunk)) |margin| {
            style.margin_top = margin;
        }

        if (get_class_value("mb-", chunk)) |margin| {
            style.margin_bottom = margin;
        }

        if (self.get_class_color("bg-", chunk)) |color| {
            style.bg_color = color;
        }

        if (get_class_value("rounded-", chunk)) |rounding| {
            style.rounding = rounding;
        }

        if (get_class_value("text-", chunk)) |text_size| {
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

const LayoutInput = struct {
    offset: struct {
        x: f32,
        y: f32,
    },
    parent_size: struct {
        width: f32,
        height: f32,
    },
    space_available: struct {
        width: f32,
        height: f32,
    },
};

fn compute_layout_inner(self: *Self, node: *ViewNode, parent_style: *const Style, parent_layout_input: *LayoutInput) void {
    const style = self.get_style(node.class);
    // TODO: fix this mess
    node.bg_color = style.bg_color;
    node.rounding = style.rounding;
    node.text_size = style.text_size;
    node.font_name = style.font_name;

    node.computed_layout = Layout{
        .width = style.width,
        .height = style.height,
        .x = parent_layout_input.parent_size.width - parent_layout_input.space_available.width + parent_layout_input.offset.x + style.margin_left,
        .y = parent_layout_input.parent_size.height - parent_layout_input.space_available.height + parent_layout_input.offset.y + style.margin_top,
    };

    if (parent_style.is_column) {
        parent_layout_input.space_available.height -= style.height;
    } else {
        parent_layout_input.space_available.width -= style.width;
    }

    if (node.children == null) {
        return;
    }

    var input = LayoutInput{
        .offset = .{
            .x = node.computed_layout.?.x + style.padding_left,
            .y = node.computed_layout.?.y + style.padding_top,
        },
        .parent_size = .{
            .width = style.width,
            .height = style.height,
        },
        .space_available = .{
            .width = style.width,
            .height = style.height,
        },
    };

    for (node.children.?) |*child| {
        compute_layout_inner(self, @constCast(child), &style, &input);
    }
}

/// computes the layout for the whole tree and sets the layout property
pub fn compute_layout(self: *Self, root: *ViewNode, width: f32, height: f32) void {
    var input = LayoutInput{
        .offset = .{
            .x = 0,
            .y = 0,
        },
        .space_available = .{
            .width = width,
            .height = height,
        },
        .parent_size = .{
            .width = width,
            .height = height,
        },
    };
    self.compute_layout_inner(root, &Style{}, &input);
}
