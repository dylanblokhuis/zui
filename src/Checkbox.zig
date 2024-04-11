const std = @import("std");
const Dom = @import("mod/ui.zig").Dom;
const Component = @import("mod/ui.zig").Component;
const Hooks = @import("mod/ui.zig").Hooks;
const Node = @import("mod/ui.zig").Node;
const Self = @This();

is_toggled: Hooks.createRef(bool) = undefined,
list: Hooks.createList(u32) = undefined,

pub fn on_dep(component: Component) void {
    const self, _ = component.cast(@This());
    self.list.append(std.crypto.random.int(u32));
}

pub fn onclick(component: Component, _: Dom.Event) void {
    const self, _ = component.cast(@This());
    self.is_toggled.set(!self.is_toggled.get());
}

pub fn list(component: Component, item: u32, _: usize) *Node {
    return component.dom.view(.{
        .class = "text-red",
        .text = component.dom.fmt("Item {d}", .{item}),
    });
}

pub fn render(component: Component) *Node {
    const self, const dom = component.cast(@This());
    self.is_toggled = Hooks.createRef(bool).init(component, false);
    self.list = Hooks.createList(u32).init(component);

    Hooks.useEffect(component, Self.on_dep, &.{self.is_toggled.id});

    return dom.view(.{
        .class = "flex flex-row items-center gap-8",
        .children = &.{
            dom.view(.{
                .class = dom.fmt("{s} rounded-0.5 p-8", .{if (self.is_toggled.get()) "bg-blue" else "bg-red"}),
                .children = &.{dom.text("text-white", "Click me!")},
                .onclick = component.listener(Self.onclick),
            }),

            dom.view(.{
                .class = "bg-blue rounded-0.5 p-8",
                .children = &.{dom.text("text-white", "Remove item")},
            }),

            dom.view(.{
                .children = dom.foreach(component, u32, self.list.slice(), Self.list),
            }),

            dom.text("text-black", "Hello world!!!"),
        },
    });
}

pub fn renderable(self: *@This(), dom: *Dom) Component.Interface {
    return Component.Interface{
        .obj_ptr = Component{ .ptr = self, .dom = dom },
        .func_ptr = @This().render,
    };
}
