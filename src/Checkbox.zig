const std = @import("std");
const Dom = @import("mod/ui.zig").Dom;
const Component = @import("mod/ui.zig").Component;
const Hooks = @import("mod/ui.zig").Hooks;
const Self = @This();

henkie: u32 = 5,
some_array: [3]u8 = [3]u8{ 1, 2, 3 },
signal: Hooks.createRef(u32) = undefined,

pub fn onclick(component: Component, event: Dom.Event) void {
    _ = event; // autofix
    const self = component.cast(@This());
    self.signal.set(self.signal.get() + 1);
    std.debug.print("button clicked! {d}\n", .{self.signal.get()});
}

pub fn list(component: Component, item: u8, index: usize) Dom.NodeId {
    _ = item; // autofix
    return component.dom.view(.{
        .class = "text-white",
        .text = component.dom.fmt("item {d}", .{index}),
    });
}

pub fn on_dep(component: Component) void {
    std.debug.print("Use effect triggered!!!!\n", .{});
    _ = component; // autofix
}

pub fn render(component: Component) Dom.NodeId {
    const self = component.cast(@This());
    const dom = component.dom;
    self.signal = Hooks.createRef(u32).init(component, self.henkie);
    Hooks.useEffect(component, Self.on_dep, &.{self.signal.id});

    return dom.view(.{
        .class = "flex flex-col bg-red",
        .children = &.{
            dom.text("text-white", dom.fmt("button {d}", .{self.signal.get()})),
            dom.view(.{
                .class = "bg-blue text-white",
                .text = dom.fmt("button {d}", .{self.signal.get()}),
                .onclick = component.listener(Self.onclick),
            }),
            dom.view(.{
                .class = "bg-blue",
                .children = component.foreach(u8, &self.some_array, Self.list),
            }),
        },
    });
}

pub fn renderable(self: *@This(), dom: *Dom) Component.Interface {
    return Component.Interface{
        .obj_ptr = Component{ .ptr = self, .dom = dom },
        .func_ptr = @This().render,
    };
}
