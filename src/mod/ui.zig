const std = @import("std");
const Allocator = std.mem.Allocator;

const NodeData = union(enum) {
    // component: ComponentInterface,
    view: V,
};

const Node = struct {
    data: V,
    layout: Layout = Layout{
        .size = @Vector(2, f32){ 0.0, 0.0 },
        .margins = @Vector(4, f32){ 0.0, 0.0, 0.0, 0.0 },
        .behave = BehaveFlags{ .center = true },
        .contain = ContainFlags{ .row = true, .flex = true, .nowrap = false, .middle = true },
        .rect = @Vector(4, f32){ 0.0, 0.0, 0.0, 0.0 },
    },

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
                if (child.layout.behave.fill) {
                    count += 1;
                    extend += child.layout.rect[dim] + child.layout.margins[wdim];
                } else {
                    if (child.layout.behave.hfixed) {
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
                    if (node.layout.contain.between and (!wrap or (end_child != null) and !hardbreak)) {
                        spacer = extra_space / (@as(f32, @floatFromInt(total - 1)));
                    }
                    if (node.layout.contain.start) {} else if (node.layout.contain.end) {
                        extra_margin = extra_space;
                    } else {
                        extra_margin = extra_space / 2;
                    }
                }
            } else if (!wrap and squeezed_count > 0) {
                eater = extra_space / @as(f32, @floatFromInt(squeezed_count));
                var x = rect[dim];
                var x1: f32 = undefined;
                maybe_child = start_child;
                while (maybe_child) |child| {
                    var ix0: f32 = undefined;
                    var ix1: f32 = undefined;
                    const child_margins = child.layout.margins;
                    var child_rect = child.layout.rect;

                    x += child_rect[dim] + extra_margin;
                    if (child.layout.behave.hfill) {
                        x1 = x + filler;
                    } else if (child.layout.behave.hfixed) {
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

            if (child.layout.behave.hcenter) {
                child_rect[dim] += (space - child_rect[2 + dim]) / 2 - child_margins[wdim];
            } else if (child.layout.behave.right) {
                child_rect[dim] += space - child_rect[2 + dim] - child_margins[dim] - child_margins[wdim];
            } else if (child.layout.behave.hfill) {
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
            if (item.layout.behave.center) {
                rect[2 + dim] = @min(rect[2 + dim], min_size);
                rect[dim] += (space - rect[2 + dim]) / 2 - margins[wdim];
            } else if (item.layout.behave.right) {
                rect[2 + dim] = @min(rect[2 + dim], min_size);
                rect[dim] += space - rect[2 + dim] - margins[wdim];
            } else if (item.layout.behave.fill) {
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
        Node.arrange_overlay_squeezed_range(dim, maybe_start_child.?, null, offset, need_size);
        offset += need_size;
        return offset;
    }

    pub fn arrange(node: *Node, dim: usize) void {
        if (node.layout.contain.column or node.layout.contain.wrap) {
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

    pub fn run_item(node: *Node) void {
        // first we set the layout based on the classes
        node.set_style();
        // then we do our layout passes
        node.calc_size(0);
        node.arrange(0);
        node.calc_size(1);
        node.arrange(1);
    }

    fn set_style(self: *Node) void {
        var classes = std.mem.splitSequence(u8, self.data.class, " ");

        while (classes.next()) |chunk| {
            if (std.mem.eql(u8, chunk, "row")) {
                self.layout.contain.row = true;
            }

            if (std.mem.eql(u8, chunk, "col")) {
                self.layout.contain.column = true;
            }

            if (std.mem.eql(u8, chunk, "wrap")) {
                self.layout.contain.wrap = true;
            }

            if (get_class_value(f32, "w-", chunk)) |width| {
                self.layout.size[0] = width;
            }

            if (get_class_value(f32, "h-", chunk)) |height| {
                self.layout.size[1] = height;
            }
        }

        var maybe_child = self.first_child;
        while (maybe_child) |child| {
            child.set_style();
            maybe_child = child.next_sibling;
        }
    }
};

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

const BehaveFlags = packed struct {
    left: bool = false,
    top: bool = false,
    right: bool = false,
    bottom: bool = false,

    hfill: bool = false,
    vfill: bool = false,
    hcenter: bool = false,
    vcenter: bool = false,

    center: bool = false,
    fill: bool = false,

    hfixed: bool = false,
    vfixed: bool = false,

    /// break
    brk: bool = false,
};

const ContainFlags = packed struct {
    /// left to right
    row: bool = false,
    /// top to bottom
    column: bool = false,

    /// free layout
    layout: bool = false,
    /// flex layout
    flex: bool = false,

    /// wrap flags, no wrap
    nowrap: bool = false,
    /// wrap flags, wrap
    wrap: bool = false,

    /// justify-content-start
    start: bool = false,
    /// justify-content-middle
    middle: bool = false,
    /// justify-content-end
    end: bool = false,
    /// justify-content-space-between
    between: bool = false,
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

const Ui = struct {
    allocator: Allocator,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .allocator = std.heap.c_allocator,
        };
    }

    pub fn c(self: *Self, comptime component: anytype) Node {
        const interface: ComponentInterface = @constCast(&component).renderable(self);
        return interface.render();
    }

    pub fn v(self: *Self, node: V) Node {
        _ = self; // autofix
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
        const alloc_children = self.allocator.alloc(Node, children.len) catch unreachable;
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
        var children = self.allocator.alloc(Node, items.len) catch unreachable;
        for (items, 0..) |item, index| {
            children[index] = cb(component, item, index);
        }

        return children;
    }

    pub fn fmt(self: *Self, comptime format: []const u8, args: anytype) []u8 {
        return std.fmt.allocPrint(self.allocator, format, args) catch unreachable;
    }

    // pub fn create_signal(self: *Self, comptime T: type, initial_value: T) type {
    //     _ = self; // autofix
    //     return struct {
    //         value: T = initial_value,
    //     };
    // }
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

const Button = struct {
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
        return component.ui.v(.{ .class = component.ui.fmt("hello {d}", .{index}) });
    }

    pub fn render(component: Component) Node {
        const self = component.cast(@This());
        const ui = component.ui;

        return ui.v(.{
            .class = "button!",
            .children = ui.vv(&.{
                ui.v(.{
                    .class = "henkie2 w-40 h-50",
                }),
                ui.v(.{
                    .class = "henkie3",
                    .onclick = component.listener(Button.onclick),
                }),
                ui.v(.{
                    .class = "henkie4",
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

const ComponentInterface = struct {
    obj_ptr: Component,
    func_ptr: *const fn (ptr: Component) Node,

    pub fn render(self: @This()) Node {
        return self.func_ptr(self.obj_ptr);
    }
};

pub fn d() void {
    var ui = Ui.init();

    var tree = ui.v(.{
        .class = "henkie",
        .children = ui.vv(&.{
            ui.v(.{
                .class = "child 1 w-40 h-50",
            }),
            ui.c(Button{}),
            ui.c(Button{}),
        }),
    });

    tree.run_item();

    const Recurse = struct {
        pub fn inner(self: *@This(), node: *Node, depth: u32) void {
            std.debug.print("depth: {d}, node {s}\n", .{ depth, node.data.class });
            std.debug.print("x {d} y {d} width {d} height {d}\n", .{ node.layout.rect[0], node.layout.rect[1], node.layout.rect[2], node.layout.rect[3] });
            if (node.data.onclick) |listener| {
                listener.call();
            }

            if (node.first_child) |first_child| {
                self.inner(first_child, depth + 1);
            }
            if (node.next_sibling) |next| {
                self.inner(next, depth);
            }
        }
    };

    var recurse = Recurse{};
    recurse.inner(&tree, 0);

    // var recurse = Recurse{};
    // recurse.calc_size(&tree, 0, 0);
    // recurse.calc_size(&tree, 1, 0);
}
