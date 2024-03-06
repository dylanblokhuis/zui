const std = @import("std");
const layout = @import("./libs/layout/layout.zig");
const rl = @import("raylib");
const RLFonts = @import("./main.zig").RLFonts;
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
    class: []const u8 = "",
    text: []const u8 = "",
    on_click: ?*const fn () void = null,
    children: ?[]ViewNode = null,
};

pub const ViewNode = struct {
    class: []const u8 = "",
    text: []const u8 = "",
    on_click: ?*const fn () void = null,
    children: ?[]ViewNode = null,
    layout_id: ?layout.LayId = null,
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

///
///
/// example input:
///
/// ```zig
/// pub fn list(ui: *zui, item: T, index: usize) zui.ViewNode {
///    return ui.v(.{});
/// }
/// ```
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
        between,
    } = .center,
    wrap: bool = false,

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

        if (std.mem.eql(u8, chunk, "wrap")) {
            style.wrap = true;
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

        if (self.get_class_color("text-", chunk)) |color| {
            style.text_color = color;
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

fn compute_layout_inner(self: *Self, node: *ViewNode, fonts: *const RLFonts, maybe_parent_layout_id: ?layout.LayId) void {
    std.log.debug("computing layout for node: {s}", .{node.class});
    const style = self.get_style(node.class);
    node.bg_color = style.bg_color;
    node.text_color = style.text_color;
    node.rounding = style.rounding;
    node.text_size = style.text_size;
    node.font_name = style.font_name;

    const layout_id = self.layout.create_leaf();

    self.layout.set_size_xy(layout_id, style.width, style.height);

    if (!std.mem.eql(u8, node.text, "")) {
        const maybe_font = fonts.get(node.font_name);
        if (maybe_font) |font| {
            const text = std.fmt.allocPrintZ(self.allocator, "{s}", .{node.text}) catch unreachable;
            const text_size = rl.measureTextEx(font, text, style.text_size, 0.0);
            self.layout.set_size_xy(layout_id, @as(i16, @intFromFloat(text_size.x)), @as(i16, @intFromFloat(text_size.y)));
        }
    }

    self.layout.set_margins_ltrb(layout_id, style.margin_left, style.margin_top, style.margin_right, style.margin_bottom);

    {
        var container_flags = layout.Layout.CONTAIN_LAYOUT;
        if (style.is_column) {
            container_flags |= layout.Layout.CONTAIN_COLUMN;
        } else {
            container_flags |= layout.Layout.CONTAIN_ROW;
        }

        if (style.wrap) {
            container_flags |= layout.Layout.CONTAIN_WRAP;
        } else {
            container_flags |= layout.Layout.CONTAIN_NOWRAP;
        }

        if (style.align_items == .start) {
            container_flags |= layout.Layout.CONTAIN_START;
        } else if (style.align_items == .center) {
            container_flags |= layout.Layout.CONTAIN_MIDDLE;
        } else if (style.align_items == .end) {
            container_flags |= layout.Layout.CONTAIN_END;
        } else if (style.align_items == .between) {
            container_flags |= layout.Layout.CONTAIN_JUSTIFY;
        }

        self.layout.set_contain(layout_id, container_flags);
    }

    {
        // self.layout.set_behave(layout_id, layout.Layout.BEHAVE_TOP | layout.Layout.BEHAVE_LEFT);
    }

    node.layout_id = layout_id;

    if (maybe_parent_layout_id) |parent_layout_id| {
        self.layout.add_child(parent_layout_id, layout_id);
    }

    if (node.children) |children| {
        for (children) |*child| {
            compute_layout_inner(self, @constCast(child), fonts, layout_id);
        }
    }
}

// const MeasureFunc = fn (self: *Self, node: *ViewNode, known_width: f32, known_height: f32) layout.Size;

/// computes the layout for the whole tree and sets the layout property
pub fn compute_layout(self: *Self, root: *ViewNode, fonts: *const RLFonts) void {
    self.compute_layout_inner(root, fonts, null);
    self.layout.run();
}
