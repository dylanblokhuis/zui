const c = @cImport({
    @cInclude("layout.h");
});

pub const LayId = c.lay_id;
pub const LayContext = c.lay_context;
pub const Rect = c.lay_vec4;

// pub const LayItem = struct {
//     id: LayId,
//     const Self = @This();

//     pub fn set_size(self: *Self, ctx: *LayContext, width: f32, height: f32) void {
//         c.lay_set_size_xy(ctx, self.id, width, height);
//     }
// };

pub const Layout = struct {
    ctx: c.lay_context = undefined,

    // container flags

    /// left to right
    pub const CONTAIN_ROW: c_int = 2;
    /// top to bottom
    pub const CONTAIN_COLUMN: c_int = 3;

    /// free layout
    pub const CONTAIN_LAYOUT: c_int = 0;
    /// flex layout
    pub const CONTAIN_FLEX: c_int = 2;

    /// wrap flags, no wrap
    pub const CONTAIN_NOWRAP: c_int = 0;
    /// wrap flags, no wrap
    pub const CONTAIN_WRAP: c_int = 4;

    /// justify-content-start
    pub const CONTAIN_START: c_int = 8;
    /// justify-content-middle
    pub const CONTAIN_MIDDLE: c_int = 0;
    /// justify-content-end
    pub const CONTAIN_END: c_int = 16;
    /// justify-content-between
    pub const CONTAIN_JUSTIFY: c_int = 24;

    // behaviour flags

    /// anchor to left item or left side of parent
    pub const BEHAVE_LEFT: c_int = 32;
    /// anchor to top item or top side of parent
    pub const BEHAVE_TOP: c_int = 64;
    /// anchor to right item or right side of parent
    pub const BEHAVE_RIGHT: c_int = 128;
    /// anchor to bottom item or bottom side of parent
    pub const BEHAVE_BOTTOM: c_int = 256;
    /// anchor to both left and right item or parent borders
    pub const BEHAVE_HFILL: c_int = 160;
    /// anchor to both top and bottom item or parent borders
    pub const BEHAVE_VFILL: c_int = 320;
    /// center horizontally, with left margin as offset
    pub const BEHAVE_HCENTER: c_int = 0;
    /// center vertically, with top margin as offset
    pub const BEHAVE_VCENTER: c_int = 0;
    /// center in both directions, with left/top margin as offset
    pub const BEHAVE_CENTER: c_int = 0;
    /// anchor to all four directions
    pub const BEHAVE_FILL: c_int = 480;
    /// When in a wrapping container, put this element on a new line. Wrapping
    /// layout code auto-inserts LAY_BREAK flags as needed. See GitHub issues for
    /// TODO related to this.
    ///
    /// Drawing routines can read this via item pointers as needed after
    /// performing layout calculations.
    pub const BEHAVE_BREAK: c_int = 512;

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
    pub fn get_rect(self: *const Self, id: LayId) c.lay_vec4 {
        return c.lay_get_rect(&self.ctx, id);
    }

    pub fn get_size(self: *Self, id: LayId) c.lay_vec2 {
        return c.lay_get_size(&self.ctx, id);
    }
};
