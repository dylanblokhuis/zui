const std = @import("std");
const Dom = @import("mod/ui.zig").Dom;
const Component = @import("mod/ui.zig").Component;
const Hooks = @import("mod/ui.zig").Hooks;
const Self = @This();

// henkie: u32 = 5,
// some_array: [3]u8 = [3]u8{ 1, 2, 3 },
is_toggled: Hooks.createRef(bool) = undefined,
list: Hooks.createList(u32) = undefined,

// pub fn onclick(component: Component, event: Dom.Event) void {
//     _ = event; // autofix
//     const self = component.cast(@This());
//     self.signal.set(self.signal.get() + 1);
//     std.debug.print("button clicked! {d}\n", .{self.signal.get()});
// }

// pub fn list(component: Component, item: u8, index: usize) Dom.NodeId {
//     _ = item; // autofix
//     return component.dom.view(.{
//         .class = "text-white",
//         .text = component.dom.fmt("item {d}", .{index}),
//     });
// }

pub fn on_dep(component: Component) void {
    const self, _ = component.cast(@This());

    const u = std.crypto.random.int(u32);
    std.log.debug("{d}", .{u});
    self.list.append(u);
}

pub fn onclick(component: Component, event: Dom.Event) void {
    _ = event; // autofix
    const self, _ = component.cast(@This());
    self.is_toggled.set(!self.is_toggled.get());

    const slice = self.list.slice();
    std.log.debug("{any}", .{slice});
}

pub fn list(component: Component, item: u32, index: usize) Dom.NodeId {
    _ = item; // autofix
    _ = index; // autofix
    return component.dom.view(.{ .class = "text-red", .text = "An item!" });
}

pub fn render(component: Component) Dom.NodeId {
    const self, const dom = component.cast(@This());
    self.is_toggled = Hooks.createRef(bool).init(component, false);
    self.list = Hooks.createList(u32).init(component);

    Hooks.useEffect(component, Self.on_dep, &.{self.is_toggled.id});

    return dom.view(.{
        .class = "flex flex-row items-center gap-8",
        .onclick = component.listener(Self.onclick),
        .children = &.{
            dom.view(.{
                .class = dom.fmt("{s} rounded-0.5 p-8", .{if (self.is_toggled.get()) "bg-blue" else "bg-red"}),
                .children = &.{dom.text("text-white", "Click me!")},
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
