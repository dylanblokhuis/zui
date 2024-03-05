const c = @cImport({
    @cInclude("layout.h");
});

pub const LayId = c.lay_id;
pub const LayContext = c.lay_context;

// pub const LayItem = struct {
//     id: LayId,
//     const Self = @This();

//     pub fn set_size(self: *Self, ctx: *LayContext, width: f32, height: f32) void {
//         c.lay_set_size_xy(ctx, self.id, width, height);
//     }
// };

pub const Layout = struct {
    ctx: c.lay_context = undefined,

    const Self = @This();

    pub fn init() !Self {
        var self = Self{};
        c.lay_init_context(&self.ctx);

        return self;
    }

    pub fn create_leaf(self: *Self) LayId {
        return c.lay_item(&self.ctx);
    }

    pub fn set_size_xy(self: *Self, id: LayId, width: i16, height: i16) void {
        c.lay_set_size_xy(&self.ctx, id, width, height);
    }

    pub fn set_margins_ltrb(self: *Self, id: LayId, left: i16, top: i16, right: i16, bottom: i16) void {
        c.lay_set_margins_ltrb(&self.ctx, id, left, top, right, bottom);
    }
    pub fn set_margins(self: *Self, id: LayId, margins: c.lay_vec4) void {
        c.lay_set_margins(&self.ctx, id, margins);
    }

    pub fn set_behave(self: *Self, id: LayId, behave: c.enum_lay_layout_flags) void {
        c.lay_set_behave(&self.ctx, id, behave);
    }

    pub fn set_contain(self: *Self, id: LayId, container: c.enum_lay_box_flags) void {
        c.lay_set_contain(&self.ctx, id, container);
    }

    pub fn add_child(self: *Self, parent: LayId, child: LayId) void {
        c.lay_insert(&self.ctx, parent, child);
    }

    /// Performs the layout calculations, starting at the root item (id 0). After
    /// calling this, you can use lay_get_rect() to query for an item's calculated
    /// rectangle. If you use procedures such as lay_append() or lay_insert() after
    /// calling this, your calculated data may become invalid if a reallocation
    /// occurs.
    ///
    /// You should prefer to recreate your items starting from the root instead of
    /// doing fine-grained updates to the existing context.
    ///
    /// However, it's safe to use lay_set_size on an item, and then re-run
    /// lay_run_context. This might be useful if you are doing a resizing animation
    /// on items in a layout without any contents changing.
    pub fn run(self: *Self) void {
        c.lay_run_context(&self.ctx);
    }

    /// Returns the calculated rectangle of an item. This is only valid after calling
    /// lay_run_context and before any other reallocation occurs. Otherwise, the
    /// result will be undefined. The vector components are:
    ///
    /// 0: x starting position, 1: y starting position
    ///
    /// 2: width, 3: height
    pub fn get_rect(self: *Self, id: LayId) c.lay_vec4 {
        return c.lay_get_rect(&self.ctx, id);
    }

    pub fn get_size(self: *Self, id: LayId) c.lay_vec2 {
        return c.lay_get_size(&self.ctx, id);
    }
};
