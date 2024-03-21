const std = @import("std");
const fonts = @import("./font.zig");
const Allocator = std.mem.Allocator;

pub const Style = struct {
    background_color: @Vector(4, u8) = @Vector(4, u8){ 0, 0, 0, 0 },
    /// text color
    color: @Vector(4, u8) = @Vector(4, u8){ 0, 0, 0, 255 },
    font_name: []const u8 = "default",
    rounding: f32 = 0.0,
};

pub const StyleOptions = struct {
    colors: std.StringArrayHashMapUnmanaged(@Vector(4, u8)),

    const Self = @This();

    pub fn init() Self {
        return Self{
            .colors = std.StringArrayHashMapUnmanaged(@Vector(4, u8)){},
        };
    }
};

pub const FontOptions = struct {
    fonts: fonts,
    font_name_to_desc: std.StringArrayHashMapUnmanaged(fonts.FontDesc),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .fonts = fonts.init(allocator),
            .font_name_to_desc = std.StringArrayHashMapUnmanaged(fonts.FontDesc){},
        };
    }

    pub fn load(self: *Self, allocator: Allocator, name: []const u8, font_desc: fonts.FontDesc) !void {
        try self.font_name_to_desc.put(allocator, name, font_desc);
        try self.fonts.create_atlas(font_desc, allocator);
    }
};

pub const SelectorState = struct {
    hover: bool = false,
    focus: bool = false,
};

pub const Node = struct {
    data: V,
    layout: Layout = Layout{
        .size = @Vector(2, f32){ 0.0, 0.0 },
        .margins = @Vector(4, f32){ 0.0, 0.0, 0.0, 0.0 },
        .behave = BehaveFlags{},
        .contain = ContainFlags{},
        .rect = @Vector(4, f32){ 0.0, 0.0, 0.0, 0.0 },
    },
    style: Style = Style{},
    selector_state: SelectorState = SelectorState{},

    first_child: ?*Node,
    next_sibling: ?*Node,

    pub fn calc_overlayed_size(node: *Node, dim: usize) f32 {
        const wdim = dim + 2;
        var need_size: f32 = 0.0;
        var maybe_child = node.first_child;

        while (maybe_child) |child| {
            const rect = child.layout.rect;
            const child_size = rect[dim] + rect[2 + dim] + child.layout.margins[wdim];
            need_size = @max(need_size, child_size);
            maybe_child = child.next_sibling;
        }
        return need_size;
    }

    pub fn calc_stacked_size(node: *Node, dim: usize) f32 {
        const wdim = dim + 2;
        var need_size: f32 = 0.0;
        var maybe_child = node.first_child;
        while (maybe_child) |child| {
            const rect = child.layout.rect;
            need_size += rect[dim] + rect[2 + dim] + child.layout.margins[wdim];
            maybe_child = child.next_sibling;
        }
        return need_size;
    }

    pub fn calc_wrapped_overlayed_size(node: *Node, dim: usize) f32 {
        const wdim = dim + 2;
        var need_size: f32 = 0.0;
        var need_size2: f32 = 0.0;
        var maybe_child = node.first_child;
        while (maybe_child) |child| {
            const rect = child.layout.rect;
            if (child.layout.behave.brk) {
                need_size2 += need_size;
                need_size = 0.0;
            }
            const child_size = rect[dim] + rect[2 + dim] + child.layout.margins[wdim];
            need_size = @max(need_size, child_size);
            maybe_child = child.next_sibling;
        }

        return need_size2 + need_size;
    }

    pub fn calc_wrapped_stacked_size(node: *Node, dim: usize) f32 {
        const wdim = dim + 2;
        var need_size: f32 = 0.0;
        var need_size2: f32 = 0.0;
        var maybe_child = node.first_child;
        while (maybe_child) |child| {
            const rect = child.layout.rect;
            if (child.layout.behave.brk) {
                need_size2 = @max(need_size2, need_size);
                need_size = 0.0;
            }
            need_size += rect[dim] + rect[2 + dim] + child.layout.margins[wdim];
            maybe_child = child.next_sibling;
        }

        return @max(need_size2, need_size);
    }

    pub fn calc_size(node: *Node, dim: usize) void {
        var maybe_child = node.first_child;
        while (maybe_child) |child| {
            child.calc_size(dim);
            maybe_child = child.next_sibling;
        }

        node.layout.rect[dim] = node.layout.margins[dim];

        // If we have an explicit input size, just set our output size (which other
        // calc_size and arrange procedures will use) to it.
        if (node.layout.size[dim] != 0.0) {
            node.layout.rect[dim + 2] = node.layout.size[dim];
            return;
        }

        var cal_size: f32 = undefined;

        if (node.layout.contain.column and node.layout.contain.wrap) {
            if (dim != 0) {
                cal_size = node.calc_stacked_size(1);
            } else {
                cal_size = node.calc_overlayed_size(0);
            }
        } else if (node.layout.contain.row and node.layout.contain.wrap) {
            if (dim == 0) {
                cal_size = node.calc_wrapped_stacked_size(0);
            } else {
                cal_size = node.calc_wrapped_overlayed_size(1);
            }
        } else if (node.layout.contain.column) {
            cal_size = node.calc_stacked_size(dim);
        } else if (node.layout.contain.row) {
            cal_size = node.calc_overlayed_size(dim);
        } else {
            // default layout model
            cal_size = node.calc_overlayed_size(dim);
        }

        // Set our output data size. Will be used by parent calc_size procedures.,
        // and by arrange procedures.
        node.layout.rect[2 + dim] = cal_size;
    }

    pub fn arrange_stacked(node: *Node, dim: usize, wrap: bool) void {
        const wdim = dim + 2;

        const rect = node.layout.rect;
        const space: f32 = rect[2 + dim];

        const max_x2 = rect[dim] + space;

        var maybe_start_child = node.first_child;
        while (maybe_start_child) |start_child| {
            var used: f32 = 0.0;
            var count: u32 = 0;
            var squeezed_count: u32 = 0;
            var total: u32 = 0;
            var hardbreak: bool = false;

            // first pass: count items that need to be expanded,
            // and the space that is used

            var maybe_child: ?*Node = start_child;
            var end_child: ?*Node = null;

            while (maybe_child) |child| {
                var extend = used;
                if ((dim == 0 and child.layout.behave.hfill) or (dim == 1 and child.layout.behave.vfill)) {
                    count += 1;
                    extend += child.layout.rect[dim] + child.layout.margins[wdim];
                } else {
                    if ((dim == 0 and !child.layout.behave.hfixed) or (dim == 1 and !child.layout.behave.vfixed)) {
                        squeezed_count += 1;
                    }
                    extend += child.layout.rect[dim] + child.layout.rect[2 + dim] + child.layout.margins[wdim];
                }

                if (wrap and (total != 0 and ((extend > space) or child.layout.behave.brk))) {
                    end_child = child;
                    hardbreak = child.layout.behave.brk;
                    child.layout.behave.brk = true;
                    break;
                } else {
                    used = extend;
                    maybe_child = child.next_sibling;
                }
                total += 1;
            }

            const extra_space: f32 = space - used;
            var filler: f32 = 0.0;
            var spacer: f32 = 0.0;
            var extra_margin: f32 = 0.0;
            var eater: f32 = 0.0;

            if (extra_space > 0) {
                if (count > 0) {
                    filler = extra_space / @as(f32, @floatFromInt(count));
                } else if (total > 0) {
                    if (node.layout.contain.between) {
                        if (!wrap or (end_child != null and !hardbreak)) {
                            spacer = extra_space / @as(f32, @floatFromInt(total));
                        }
                    }
                    if (node.layout.contain.start) {} else if (node.layout.contain.end) {
                        extra_margin = extra_space;
                    } else {
                        extra_margin = extra_space / 2;
                    }
                }
            } else if (!wrap and squeezed_count > 0) {
                eater = extra_space / @as(f32, @floatFromInt(squeezed_count));
            }

            var x = rect[dim];
            var x1: f32 = undefined;
            maybe_child = start_child;
            while (maybe_child) |child| {
                if (child == end_child) {
                    break;
                }
                var ix0: f32 = undefined;
                var ix1: f32 = undefined;
                const child_margins = child.layout.margins;
                var child_rect = child.layout.rect;

                x += child_rect[dim] + extra_margin;
                if ((dim == 0 and child.layout.behave.hfill) or (dim == 1 and child.layout.behave.vfill)) {
                    x1 = x + filler;
                } else if ((dim == 0 and child.layout.behave.hfixed) or (dim == 1 and child.layout.behave.vfixed)) {
                    x1 = x + child_rect[2 + dim];
                } else {
                    x1 = x + @max(0.0, child_rect[2 + dim] + eater);
                }

                ix0 = x;
                if (wrap) {
                    ix1 = @min(max_x2 - child_margins[wdim], x1);
                } else {
                    ix1 = x1;
                }
                child_rect[dim] = ix0; // pos
                child_rect[dim + 2] = ix1 - ix0; // size
                child.layout.rect = child_rect;
                x = x1 + child_margins[wdim];
                maybe_child = child.next_sibling;
                extra_margin = spacer;
            }
            maybe_start_child = end_child;
        }
    }

    pub fn arrange_overlay(node: *Node, dim: usize) void {
        const wdim = dim + 2;
        const rect = node.layout.rect;
        const offset = rect[dim];
        const space = rect[2 + dim];

        var maybe_child = node.first_child;
        while (maybe_child) |child| {
            const child_margins = child.layout.margins;
            var child_rect = child.layout.rect;

            if ((dim == 0 and child.layout.behave.hcenter) or (dim == 1 and child.layout.behave.vcenter)) {
                child_rect[dim] += (space - child_rect[2 + dim]) / 2 - child_margins[wdim];
            } else if ((dim == 0 and child.layout.behave.right) or (dim == 1 and child.layout.behave.bottom)) {
                child_rect[dim] += space - child_rect[2 + dim] - child_margins[dim] - child_margins[wdim];
            } else if ((dim == 0 and child.layout.behave.hfill) or (dim == 1 and child.layout.behave.vfill)) {
                child_rect[2 + dim] = @max(0.0, space - child_rect[dim] - child_margins[wdim]);
            }

            child_rect[dim] += offset;
            child.layout.rect = child_rect;
            maybe_child = child.next_sibling;
        }
    }

    pub fn arrange_overlay_squeezed_range(dim: usize, start: ?*Node, end: ?*Node, offset: f32, space: f32) void {
        const wdim = dim + 2;
        var maybe_item: ?*Node = start;
        while (maybe_item) |item| {
            if (item == end) {
                break;
            }
            const margins = item.layout.margins;
            var rect = item.layout.rect;
            const min_size = @max(0, space - rect[dim] - margins[wdim]);
            if ((dim == 0 and item.layout.behave.hcenter) or (dim == 1 and item.layout.behave.vcenter)) {
                rect[2 + dim] = @min(rect[2 + dim], min_size);
                rect[dim] += (space - rect[2 + dim]) / 2 - margins[wdim];
            } else if ((dim == 0 and item.layout.behave.right) or (dim == 1 and item.layout.behave.bottom)) {
                rect[2 + dim] = @min(rect[2 + dim], min_size);
                rect[dim] += space - rect[2 + dim] - margins[wdim];
            } else if ((dim == 0 and item.layout.behave.hfill) or (dim == 1 and item.layout.behave.vfill)) {
                rect[2 + dim] = min_size;
            } else {
                rect[2 + dim] = @min(rect[2 + dim], min_size);
            }

            rect[dim] += offset;
            item.layout.rect = rect;
            maybe_item = item.next_sibling;
        }
    }

    pub fn arrange_wrapped_overlay_squeezed(node: *Node, dim: usize) f32 {
        const wdim = dim + 2;
        var offset = node.layout.rect[dim];
        var need_size: f32 = 0;
        var maybe_child = node.first_child;
        var maybe_start_child = maybe_child;
        while (maybe_child) |child| {
            if (child.layout.behave.brk) {
                Node.arrange_overlay_squeezed_range(dim, maybe_start_child.?, child, offset, need_size);
                offset += need_size;
                maybe_start_child = child;
                need_size = 0;
            }
            const rect = child.layout.rect;
            const child_size = rect[dim] + rect[2 + dim] + child.layout.margins[wdim];
            need_size = @max(need_size, child_size);
            maybe_child = child.next_sibling;
        }
        Node.arrange_overlay_squeezed_range(dim, maybe_start_child, null, offset, need_size);
        offset += need_size;
        return offset;
    }

    pub fn arrange(node: *Node, dim: usize) void {
        if (node.layout.contain.column and node.layout.contain.wrap) {
            if (dim != 0) {
                node.arrange_stacked(1, true);
                const offset = node.arrange_wrapped_overlay_squeezed(0);
                node.layout.rect[2 + 0] = offset - node.layout.rect[0];
            }
        } else if (node.layout.contain.row and node.layout.contain.wrap) {
            if (dim == 0) {
                node.arrange_stacked(0, true);
            } else {
                _ = node.arrange_wrapped_overlay_squeezed(1);
            }
        } else if (node.layout.contain.column) {
            node.arrange_stacked(dim, false);
        } else if (node.layout.contain.row) {
            const rect = node.layout.rect;
            _ = Node.arrange_overlay_squeezed_range(dim, node.first_child, null, rect[dim], rect[2 + dim]);
        } else {
            node.arrange_overlay(dim);
        }

        var maybe_child = node.first_child;
        while (maybe_child) |child| {
            child.arrange(dim);
            maybe_child = child.next_sibling;
        }
    }

    fn set_style(self: *Node, ui: *Ui) void {
        var classes = std.mem.splitSequence(u8, self.data.class, " ");

        while (classes.next()) |chunk| {
            if (chunk.len > 6 and std.mem.eql(u8, chunk[0..6], "hover:")) {
                continue;
            }

            self.set_style_by_class(ui, chunk);
        }

        if (self.selector_state.hover) {
            classes = std.mem.splitSequence(u8, self.data.class, " ");
            while (classes.next()) |chunk| {
                if (chunk.len > 6 and std.mem.eql(u8, chunk[0..6], "hover:")) {
                    self.set_style_by_class(ui, chunk[6..]);
                }
            }
        }

        // add text size if no explicit size is set
        if (!std.mem.eql(u8, self.data.text, "") and self.layout.size[0] == 0.0 and self.layout.size[1] == 0.0) {
            const maybe_font = ui.font_name_to_desc.get(self.style.font_name);
            if (maybe_font) |font_desc| {
                const atlas = ui.fonts.atlases.get(font_desc).?;
                self.layout.size = atlas.measure(self.data.text);
            } else {
                std.log.err("font not found while computing layout: {s}", .{self.style.font_name});
            }
        }

        var maybe_child = self.first_child;
        while (maybe_child) |child| {
            child.set_style(ui);
            maybe_child = child.next_sibling;
        }
    }

    pub fn set_style_by_class(self: *Node, ui: *Ui, class: []const u8) void {
        if (std.mem.eql(u8, class, "row")) {
            self.layout.contain.row = true;
            self.layout.contain.column = false;
            self.layout.contain.wrap = true;
        }

        if (std.mem.eql(u8, class, "col")) {
            self.layout.contain.row = false;
            self.layout.contain.column = true;
            self.layout.contain.wrap = true;
        }

        if (std.mem.eql(u8, class, "wrap")) {
            self.layout.contain.wrap = true;
            self.layout.contain.nowrap = false;
        }

        if (get_class_value(f32, "w-", class)) |width| {
            self.layout.size[0] = width;
        }

        if (get_class_value(f32, "h-", class)) |height| {
            self.layout.size[1] = height;
        }

        if (get_class_value(f32, "m-", class)) |f| {
            self.layout.margins = @Vector(4, f32){ f, f, f, f };
        }

        if (get_class_value(f32, "rounding-", class)) |f| {
            self.style.rounding = f;
        }

        if (get_class_slice("bg-", class)) |color| {
            self.style.background_color = ui.style_options.colors.get(color) orelse blk: {
                std.debug.print("color not found: {s}\n", .{color});
                break :blk @Vector(4, u8){ 0, 0, 0, 255 };
            };
        }

        if (get_class_slice("text-", class)) |color| {
            self.style.color = ui.style_options.colors.get(color) orelse blk: {
                std.debug.print("color not found: {s}\n", .{color});
                break :blk @Vector(4, u8){ 0, 0, 0, 255 };
            };
        }

        if (get_class_slice("items-", class)) |align_items| {
            self.layout.contain.start = false;
            self.layout.contain.middle = false;
            self.layout.contain.end = false;
            self.layout.contain.between = false;

            if (std.mem.eql(u8, align_items, "start")) {
                self.layout.contain.start = true;
            }

            if (std.mem.eql(u8, align_items, "center")) {
                self.layout.contain.middle = true;
            }

            if (std.mem.eql(u8, align_items, "end")) {
                self.layout.contain.end = true;
            }

            if (std.mem.eql(u8, align_items, "between")) {
                self.layout.contain.between = true;
            }
        }

        if (get_class_slice("font-", class)) |font_name| {
            self.style.font_name = font_name;
        }

        if (get_class_slice("b-", class)) |behave| {
            if (std.mem.eql(u8, behave, "left")) {
                self.layout.behave.left = true;
            }

            if (std.mem.eql(u8, behave, "top")) {
                self.layout.behave.top = true;
            }

            if (std.mem.eql(u8, behave, "right")) {
                self.layout.behave.right = true;
            }

            if (std.mem.eql(u8, behave, "bottom")) {
                self.layout.behave.bottom = true;
            }

            if (std.mem.eql(u8, behave, "hfill")) {
                self.layout.behave.hfill = true;
            }

            if (std.mem.eql(u8, behave, "vfill")) {
                self.layout.behave.vfill = true;
            }

            if (std.mem.eql(u8, behave, "hcenter")) {
                self.layout.behave.hcenter = true;
            }

            if (std.mem.eql(u8, behave, "vcenter")) {
                self.layout.behave.vcenter = true;
            }

            if (std.mem.eql(u8, behave, "center")) {
                self.layout.behave.hcenter = true;
                self.layout.behave.vcenter = true;
            }

            if (std.mem.eql(u8, behave, "fill")) {
                self.layout.behave.fill = true;
            }

            if (std.mem.eql(u8, behave, "hfixed")) {
                self.layout.behave.hfixed = true;
            }

            if (std.mem.eql(u8, behave, "vfixed")) {
                self.layout.behave.vfixed = true;
            }

            if (std.mem.eql(u8, behave, "brk")) {
                self.layout.behave.brk = true;
            }
        }
    }
};

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

/// default is: center in both directions, with left/top margin as offset
const BehaveFlags = packed struct(u16) {
    /// anchor to left item or left side of parent
    left: bool = false,
    /// anchor to top item or top side of parent
    top: bool = false,
    /// anchor to right item or right side of parent
    right: bool = false,
    /// anchor to bottom item or bottom side of parent
    bottom: bool = false,

    /// anchor to both left and right item or parent borders
    hfill: bool = false,
    /// anchor to both top and bottom item or parent borders
    vfill: bool = false,
    /// center horizontally, with left margin as offset
    hcenter: bool = false,
    /// center vertically, with top margin as offset
    vcenter: bool = false,

    /// anchor to all four directions
    fill: bool = false,

    hfixed: bool = false,
    vfixed: bool = false,

    /// break
    brk: bool = false,
    _pad: u4 = 0,
};

const ContainFlags = packed struct(u16) {
    /// left to right
    row: bool = false,
    /// top to bottom
    column: bool = false,

    /// free layout
    layout: bool = true,
    /// flex layout
    flex: bool = false,

    /// wrap flags, no wrap
    nowrap: bool = true,
    /// wrap flags, wrap
    wrap: bool = false,

    /// justify-content-start
    start: bool = false,
    /// justify-content-middle
    middle: bool = true,
    /// justify-content-end
    end: bool = false,
    /// justify-content-space-between
    between: bool = false,

    // align-items
    // can be implemented by putting a flex container in a layout container,
    // then using LAY_TOP, LAY_BOTTOM, LAY_VFILL, LAY_VCENTER, etc.
    // FILL is equivalent to stretch/grow

    // align-content (start, end, center, stretch)
    // can be implemented by putting a flex container in a layout container,
    // then using LAY_TOP, LAY_BOTTOM, LAY_VFILL, LAY_VCENTER, etc.
    // FILL is equivalent to stretch; space-between is not supported.

    _pad: u6 = 0,
};

const Layout = struct {
    size: @Vector(2, f32),
    margins: @Vector(4, f32),
    behave: BehaveFlags,
    contain: ContainFlags,

    // computed rect
    rect: @Vector(4, f32),
};

const V = struct {
    class: []const u8 = "",
    text: []const u8 = "",
    children: ?[]Node = null,
    onclick: ?Listener = null,
};

const Listener = struct {
    func_ptr: *const fn (component: Component) void,
    component: Component,

    pub fn call(self: @This()) void {
        self.func_ptr(self.component);
    }
};

pub const Ui = struct {
    allocator: Allocator,
    arena: std.heap.ArenaAllocator,
    style_options: StyleOptions,
    fonts: fonts,
    font_name_to_desc: std.StringArrayHashMapUnmanaged(fonts.FontDesc),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .style_options = StyleOptions.init(),
            .fonts = fonts.init(allocator),
            .font_name_to_desc = std.StringArrayHashMapUnmanaged(fonts.FontDesc){},
        };
    }

    pub fn c(self: *Self, comptime component: anytype) Node {
        var comp = self.arena.allocator().create(@TypeOf(component)) catch unreachable;
        comp.* = component;
        const interface: ComponentInterface = comp.renderable(self);
        return interface.render();
    }

    pub fn v(self: *Self, node: V) Node {
        _ = self;
        var parent = Node{
            .data = node,
            .first_child = null,
            .next_sibling = null,
        };

        if (node.children) |children| {
            for (children) |*child| {
                if (parent.first_child == null) {
                    parent.first_child = child;
                } else {
                    // find the first suitable sibling
                    var maybe_next = parent.first_child;

                    while (maybe_next) |next| {
                        if (next.next_sibling == null) {
                            next.next_sibling = child;
                            break;
                        }
                        maybe_next = next.next_sibling;
                    }
                }
            }
        }

        return parent;
    }

    pub fn vv(self: *Self, children: []const Node) []Node {
        const alloc_children = self.arena.allocator().alloc(Node, children.len) catch unreachable;
        for (children, 0..) |child, i| {
            alloc_children[i] = child;
        }
        return alloc_children;
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
    pub fn foreach(self: *Self, component: Component, comptime T: type, items: []const T, cb: *const fn (component: Component, item: T, index: usize) Node) []Node {
        var children = self.arena.allocator().alloc(Node, items.len) catch unreachable;
        for (items, 0..) |item, index| {
            children[index] = cb(component, item, index);
        }

        return children;
    }

    pub fn fmt(self: *Self, comptime format: []const u8, args: anytype) []u8 {
        return std.fmt.allocPrint(self.arena.allocator(), format, args) catch unreachable;
    }

    pub fn compute_layout(self: *Ui, node: *Node) void {
        // first we set the layout based on the classes
        node.set_style(self);

        // then we do our layout passes
        node.calc_size(0);
        node.arrange(0);
        node.calc_size(1);
        node.arrange(1);
    }

    pub fn load_font(self: *Self, name: []const u8, font_desc: fonts.FontDesc) !void {
        try self.font_name_to_desc.put(self.allocator, name, font_desc);
        try self.fonts.create_atlas(font_desc, self.allocator);
    }

    pub fn handle_mouse_move_event(self: *Self, node: *Node, mouse_position: @Vector(2, f32)) void {
        node.selector_state = SelectorState{};

        // find the node that was clicked
        // call the onclick listener
        if (node.layout.rect[0] <= mouse_position[0] and
            node.layout.rect[1] <= mouse_position[1] and
            node.layout.rect[0] + node.layout.rect[2] >= mouse_position[0] and
            node.layout.rect[1] + node.layout.rect[3] >= mouse_position[1])
        {
            node.selector_state.hover = true;
        }

        var maybe_child = node.first_child;
        while (maybe_child) |child| {
            self.handle_mouse_move_event(child, mouse_position);
            maybe_child = child.next_sibling;
        }
    }

    pub fn handle_click_event(self: *Self, node: *Node, mouse_position: @Vector(2, f32)) void {
        // we can reuse the global hover state
        if (node.selector_state.hover and node.data.onclick != null) {
            std.debug.print("clicking  node {s}\n", .{node.data.class});
            node.data.onclick.?.call();
        }

        var maybe_child = node.first_child;
        while (maybe_child) |child| {
            self.handle_click_event(child, mouse_position);
            maybe_child = child.next_sibling;
        }
    }
};

const Component = struct {
    /// this ptr holds the actual component data, like your custom struct
    ptr: *anyopaque,
    /// we store the ui pointer in the component so its easier to call methods
    ui: *Ui,

    const Self = @This();

    pub inline fn cast(self: Self, T: type) *T {
        return @ptrCast(@alignCast(self.ptr));
    }

    pub fn listener(self: Self, func_ptr: *const fn (c: Self) void) Listener {
        return Listener{
            .func_ptr = func_ptr,
            .component = self,
        };
    }

    pub fn foreach(self: Self, comptime T: type, items: []const T, cb: *const fn (component: Self, item: T, index: usize) Node) []Node {
        return self.ui.foreach(self, T, items, cb);
    }
};

pub const Button = struct {
    henkie: u32 = 5,
    some_array: [10]u8 = [10]u8{
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
    },

    pub fn onclick(component: Component) void {
        const self = component.cast(@This());
        self.henkie += 1;
        std.debug.print("button clicked! {d}\n", .{self.henkie});
    }

    pub fn list(component: Component, item: u8, index: usize) Node {
        _ = item; // autofix
        return component.ui.v(.{
            .class = "text-white b-hcenter font-bold m-10",
            .text = component.ui.fmt("item {d}", .{index}),
        });
    }

    pub fn render(component: Component) Node {
        const self = component.cast(@This());
        const ui = component.ui;

        return ui.v(.{
            .class = "col",
            .children = ui.vv(&.{
                ui.v(.{
                    .class = "w-40 h-20 bg-green",
                }),
                ui.v(.{
                    .class = "w-20 h-40 bg-blue",
                    .onclick = component.listener(Button.onclick),
                }),
                ui.v(.{
                    .class = "bg-red row",
                    .children = component.foreach(u8, &self.some_array, Button.list),
                }),
            }),
        });
    }

    pub fn renderable(self: *@This(), ui: *Ui) ComponentInterface {
        return ComponentInterface{
            .obj_ptr = Component{ .ptr = self, .ui = ui },
            .func_ptr = @This().render,
        };
    }
};

pub const ComponentInterface = struct {
    obj_ptr: Component,
    func_ptr: *const fn (ptr: Component) Node,

    pub fn render(self: @This()) Node {
        return self.func_ptr(self.obj_ptr);
    }
};
