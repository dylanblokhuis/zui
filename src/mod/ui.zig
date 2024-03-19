const std = @import("std");
const Allocator = std.mem.Allocator;

const NodeData = union(enum) {
    // component: ComponentInterface,
    view: V,
};

const Node = struct {
    data: V,
    first_child: ?*Node,
    next_sibling: ?*Node,
};

const V = struct {
    class: []const u8 = "",
    children: ?[]Node = null,
    onclick: ?Listener = null,
};

const Listener = struct {
    func_ptr: *const fn (component: Component) void,
    component: Component,
};

const Ui = struct {
    allocator: Allocator,
    nodes: std.ArrayListUnmanaged(Node),

    const Self = @This();

    pub fn init() Self {
        return Self{
            .allocator = std.heap.c_allocator,
            .nodes = std.ArrayListUnmanaged(Node){},
        };
    }

    pub fn c(self: *Self, comptime component: anytype) Node {
        const interface: ComponentInterface = @constCast(&component).renderable(self);
        // node.component = interface;
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
};

const Component = struct {
    /// this ptr holds the actual component data, like your custom struct
    ptr: *anyopaque,
    ui: *Ui,

    const Self = @This();

    pub fn cast(self: Self, T: type) *T {
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
        _ = index; // autofix
        return component.ui.v(.{
            .class = "henkie5",
        });
    }

    pub fn render(component: Component) Node {
        const self = component.cast(@This());
        const ui = component.ui;

        return ui.v(.{
            .class = "button!",
            .children = ui.vv(&.{
                ui.v(.{
                    .class = "henkie2",
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
                .class = "henkie",
            }),
            ui.c(Button{}),
        }),
    });

    const Recurse = struct {
        pub fn inner(self: *@This(), node: *Node, depth: u32) void {
            std.debug.print("depth: {d}, node {s}\n", .{ depth, node.data.class });

            if (node.data.onclick) |listener| {
                listener.func_ptr(listener.component);
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
}
