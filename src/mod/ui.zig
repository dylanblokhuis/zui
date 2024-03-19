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
        const interface: ComponentInterface = @constCast(&component).renderable();
        return interface.render(self);
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
    pub fn foreach(self: *Self, comptime T: type, cb: *const fn (self: *Self, item: T, index: usize) Node, items: []const T) []Node {
        var children = self.allocator.alloc(Node, items.len) catch unreachable;
        for (items, 0..) |item, index| {
            children[index] = cb(self, item, index);
        }

        return children;
    }

    pub fn fmt(self: *Self, comptime format: []const u8, args: anytype) []u8 {
        return std.fmt.allocPrint(self.allocator, format, args) catch unreachable;
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
            ui.c(AnotherButton{}),
        }),
    });

    const Recurse = struct {
        pub fn inner(self: *@This(), node: *Node, depth: u32) void {
            std.debug.print("depth: {d}, node {s}\n", .{ depth, node.data.class });
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

pub fn t() void {}

const Button = struct {
    henkie: u32 = 5,

    pub fn render(ptr: *anyopaque, ui: *Ui) Node {
        const self: *@This() = @ptrCast(@alignCast(ptr));
        _ = self; // autofix

        // this is all getting discarded in the arena, but how can we preserve something like this?

        return ui.v(.{
            .class = "button!",
            .children = ui.vv(&.{
                ui.v(.{
                    .class = "henkie2",
                }),
                ui.v(.{
                    .class = "henkie3",
                }),
            }),
        });
    }

    pub fn renderable(self: *@This()) ComponentInterface {
        return ComponentInterface{
            .obj_ptr = self,
            .func_ptr = @This().render,
        };
    }
};

const AnotherButton = struct {
    sdfsdfdsfdf: u32 = 5,

    pub fn list(ui: *Ui, item: u32, index: usize) Node {
        _ = index; // autofix
        return ui.v(.{
            .class = ui.fmt("inside loop! {d}", .{item}),
        });
    }

    pub fn render(ptr: *anyopaque, ui: *Ui) Node {
        const self: *@This() = @ptrCast(@alignCast(ptr));

        return ui.v(.{
            .class = ui.fmt("Henkie! {d}", .{self.sdfsdfdsfdf}),
            .children = ui.vv(&.{
                ui.v(.{
                    .class = "henkie2",
                }),
                ui.v(.{
                    .class = "henkie3",
                }),
                ui.v(.{
                    .children = ui.foreach(u32, @This().list, &.{
                        1,
                        2,
                        3,
                    }),
                }),
            }),
        });
    }

    pub fn renderable(self: *@This()) ComponentInterface {
        return ComponentInterface{
            .obj_ptr = self,
            .func_ptr = @This().render,
        };
    }
};

// const AnotherButton = struct {
//     sdflkjsdflksdjklfs: u32 = 34342,

//     pub fn render(ptr: *anyopaque, ui: *Ui) Node {
//         _ = ui; // autofix
//         const self: *@This() = @ptrCast(@alignCast(ptr));
//         std.debug.print("rendering button {any}\n", .{self});

//         return ui.v(.{
//             .class = "AnotherButton!",
//         });
//     }

//     pub fn renderable(self: *@This(), ui: *Ui) ComponentInterface {
//         _ = ui; // autofix
//         return ComponentInterface{
//             .obj_ptr = self,
//             .func_ptr = @This().render,
//         };
//     }
// };

const ComponentInterface = struct {
    obj_ptr: *anyopaque,
    func_ptr: *const fn (ptr: *anyopaque, ui: *Ui) Node,

    pub fn render(self: @This(), ui: *Ui) Node {
        return self.func_ptr(self.obj_ptr, ui);
    }
};
