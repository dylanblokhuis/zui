const std = @import("std");
const freetype = @import("freetype");
const Allocator = std.mem.Allocator;
const Self = @This();

const AtlasHashMap = std.ArrayHashMap(FontDesc, FontAtlas, FontDesc.FontDescContext, false);

library: freetype.Library,
atlases: AtlasHashMap,
max_font_file_size: usize = 1024 * 1024 * 10, // 10MB

pub fn init(allocator: Allocator) Self {
    return Self{
        .library = freetype.Library.init() catch unreachable,
        .atlases = AtlasHashMap.init(allocator),
    };
}

pub fn deinit(self: *Self, allocator: Allocator) void {
    for (self.atlases.values()) |*atlas| {
        atlas.deinit(allocator);
    }
    self.atlases.deinit();
    self.library.deinit();
}

pub const FontDesc = struct {
    /// The path to the font file relative to the current working directory.
    path: []const u8,
    /// The size of the font in pixels.
    size: u32,

    pub fn init(path: []const u8, size: u32) FontDesc {
        return FontDesc{
            .path = path,
            .size = size,
        };
    }

    const FontDescContext = struct {
        pub fn hash(self: @This(), s: FontDesc) u32 {
            _ = self;

            var h = std.hash.Wyhash.init(0);
            h.update(s.path);

            return @intCast(h.final() + s.size);
        }

        pub fn eql(self: @This(), a: FontDesc, b: FontDesc, b_index: usize) bool {
            _ = self;
            _ = b_index;

            if (a.size != b.size) {
                return false;
            }

            return std.mem.eql(u8, a.path, b.path);
        }
    };
};

/// how to:
///
/// ```zig
/// var pos: i32 = 0;
/// for (text_to_render) |c| {
///     const glyph = atlas.glyph_infos[@intCast(c)];
///     const rect = glyph.glyph_position_in_atlas();
///     const position = @Vector(2, f32) {
///         @floatFromInt(pos + glyph.xoff),
///         font_size - @as(f32, @floatFromInt(glyph.yoff))
///     };
///
///     // do drawing
///
///     pos += glyph.advance;
/// }
/// ```
const GlyphInfo = struct {
    // coords of the glyph in the texture
    x0: u32,
    y0: u32,
    x1: u32,
    y1: u32,
    // left & top bearing
    xoff: i32,
    yoff: i32,
    // x advance
    advance: i32,

    /// Returns the position of the glyph in the atlas as a vector of 4 floats.
    ///
    /// The first two floats are the width and height of the glyph in the atlas.
    ///
    /// The last two floats are the x and y offset of the glyph in the atlas.
    pub inline fn glyph_position_in_atlas(self: GlyphInfo) @Vector(4, f32) {
        return @Vector(4, f32){
            // width
            @floatFromInt(self.width()),
            // height
            @floatFromInt(self.height()),
            // x
            @floatFromInt(self.x0),
            // y
            @floatFromInt(self.y0),
        };
    }

    pub inline fn width(self: GlyphInfo) u32 {
        return self.x1 - self.x0;
    }

    pub inline fn height(self: GlyphInfo) u32 {
        return self.y1 - self.y0;
    }
};

const FontAtlas = struct {
    data: []u8,
    width: u32,
    height: u32,
    glyph_infos: []GlyphInfo,
    font_size: u32,

    pub fn deinit(self: *FontAtlas, allocator: Allocator) void {
        allocator.free(self.data);
        allocator.free(self.glyph_infos);
    }

    pub fn measure(self: *const FontAtlas, text: []const u8) @Vector(2, f32) {
        var width: i32 = 0;
        var height: f32 = 0;

        for (text) |c| {
            const glyph = self.glyph_infos[@intCast(c)];
            const offset_y = (@as(f32, @floatFromInt(self.font_size))) - @as(f32, @floatFromInt(glyph.yoff));
            width += glyph.advance;
            height = @max(height, offset_y + @as(f32, @floatFromInt(glyph.height())));
        }

        return @Vector(2, f32){ @floatFromInt(width), height };
    }
};

pub fn create_atlas(self: *Self, desc: FontDesc, allocator: Allocator) !void {
    const bytes = try std.fs.cwd().readFileAlloc(allocator, desc.path, self.max_font_file_size);
    defer allocator.free(bytes);

    const face = try self.library.createFaceMemory(bytes, 0);
    defer face.deinit();

    try face.setPixelSizes(0, desc.size);

    const num_glyphs = 128;
    const glyph_info = try allocator.alloc(GlyphInfo, num_glyphs);
    const max_dim: u32 = @intFromFloat(
        @as(f32, @floatFromInt(1 + (face.size().metrics().height >> 6))) * std.math.ceil(std.math.sqrt(@as(f32, @floatFromInt(num_glyphs)))),
    );

    var tex_width: u32 = 1;
    while (tex_width < max_dim) {
        tex_width <<= 1;
    }

    const pixels = try allocator.alloc(u8, 2 * tex_width * tex_width);

    for (0..(2 * tex_width * tex_width)) |i| {
        pixels[i] = 0;
    }

    var pen_x: u32 = 0;
    var pen_y: u32 = 0;

    for (0..num_glyphs) |i| {
        try face.loadChar(@intCast(i), .{ .render = true, .target_normal = true });
        const bitmap = face.glyph().bitmap();

        if (pen_x + bitmap.width() >= tex_width) {
            pen_x = 0;
            pen_y += @intCast(((face.size().metrics().height >> 6) + 1));
        }

        if (bitmap.buffer()) |buffer| {
            for (0..bitmap.rows()) |row| {
                for (0..bitmap.width()) |col| {
                    const x = pen_x + col;
                    const y = pen_y + row;
                    const pitch: usize = @intCast(bitmap.pitch());
                    const pixelIndex = (y * tex_width + x) * 2;
                    const byte = buffer[row * pitch + col];

                    if (byte > 0) {
                        pixels[pixelIndex] = 0xFF;
                        // we set the alpha channel to the byte value to get nice antialiasing
                        pixels[pixelIndex + 1] = byte;
                    }
                }
            }
        }

        glyph_info[i] = .{
            .x0 = pen_x,
            .y0 = pen_y,
            .x1 = pen_x + bitmap.width(),
            .y1 = pen_y + bitmap.rows(),

            .xoff = face.glyph().bitmapLeft(),
            .yoff = face.glyph().bitmapTop(),
            .advance = @intCast(face.glyph().advance().x >> 6),
        };
        pen_x += bitmap.width() + 1;
    }

    try self.atlases.putNoClobber(desc, FontAtlas{
        .data = pixels,
        .width = tex_width,
        .height = tex_width,
        .glyph_infos = glyph_info,
        .font_size = desc.size,
    });
}
