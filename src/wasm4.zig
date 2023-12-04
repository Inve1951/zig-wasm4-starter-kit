//! Zig-friendly wasm-4 bindings/abstractions.

const std = @import("std");
const assert = std.debug.assert;
const w4 = @import("vendor/wasm4.zig");

pub const BlitFlags = enum(u32) {
    none = w4.BLIT_1BPP,
    /// Sprite pixel format: 2BPP if set, otherwise 1BPP.
    @"2bpp" = w4.BLIT_2BPP,
    /// Flip sprite horizontally.
    flipX = w4.BLIT_FLIP_X,
    /// Flip sprite vertically.
    flipy = w4.BLIT_FLIP_Y,
    /// Rotate sprite anti-clockwise by 90 degrees.
    /// Rotation is applied after any flipping.
    rotate = w4.BLIT_ROTATE,

    comptime {
        assert(0 == @intFromEnum(BlitFlags.none));
    }
};

/// Converts a multi-line string to a bitmap.
/// Expects a leading space on every line and a space between every symbol.
/// Trailing spaces on non-full lines are necessary when the space character is not on color channel 0.
/// Example:
/// ```
/// const circle = Bitmap(
///     \\   x x x
///     \\ x       x
///     \\ x       x
///     \\ x       x
///     \\   x x x
/// ,
///     " x",
/// ){};
/// ```
pub fn Bitmap(comptime pattern: []const u8, comptime channels: []const u8) type {
    // @setEvalBranchQuota(pattern.len * channels.len);
    assert(channels.len == 2 or channels.len == 4);
    for (channels, 0..) |c, i|
        assert(i == std.mem.lastIndexOfScalar(u8, channels, c).?);
    const bpp = @divExact(channels.len, 2);

    const width, const height = blk: {
        var width = 0;
        var height = 0;

        var it = std.mem.split(u8, std.mem.trim(u8, pattern, "\n"), "\n");
        while (it.next()) |line| {
            height += 1;
            width = @max(width, @divExact(line.len, 2));

            for (line, 0..) |c, i| {
                if (i % 2 == 0)
                    assert(c == ' ')
                else
                    assert(std.mem.indexOfScalar(u8, channels, c) != null);
            }
        }
        // The runtime assumes these in the drawing code.
        assert(width > 4);
        assert(height > 4);
        break :blk .{ width, height };
    };

    const PixelT = std.meta.Int(.unsigned, bpp);
    const MemT = std.math.ByteAlignedInt(std.meta.Int(.unsigned, width * height * bpp));

    const mem: MemT = blk: {
        var mem: MemT = 0;

        var y = 0;
        var it = std.mem.split(u8, std.mem.trim(u8, pattern, "\n"), "\n");
        while (it.next()) |line| {
            defer y += 1;
            const y_neg = height - y - 1;

            for (line, 0..) |c, i| {
                if (i % 2 == 0)
                    continue;

                const x = @divExact(i - 1, 2);
                const x_neg = width - x - 1;

                const pixel: PixelT = @intCast(std.mem.indexOfScalar(u8, channels, c).?);
                mem |= @shlExact(@as(MemT, pixel), (y_neg * width + x_neg) * bpp);
            }
        }
        break :blk @byteSwap(mem);
    };

    return struct {
        const Self = @This();

        comptime mem: [@sizeOf(MemT)]u8 = std.mem.toBytes(mem),
        comptime width: comptime_int = width,
        comptime height: comptime_int = height,
        comptime bpp: BlitFlags = switch (bpp) {
            1 => .none,
            2 => .@"2bpp",
            else => unreachable,
        },

        /// Copies pixels to the framebuffer.
        pub fn blit(bitmap: Self, x: i32, y: i32, flags: BlitFlags) void {
            const f = @intFromEnum(flags);
            assert(0 == f & @intFromEnum(BlitFlags.@"2bpp"));

            // Works around compiler crash. (0.12.0-dev.1735+bece97ef2)
            const mem2 = bitmap.mem;
            w4.blit(&mem2, x, y, bitmap.width, bitmap.height, f | @intFromEnum(bitmap.bpp));
        }

        /// Copies a subregion within a larger sprite atlas to the framebuffer.
        pub fn blitSub(bitmap: Self, crop_x: u32, crop_y: u32, crop_w: u32, crop_h: u32, x: i32, y: i32, flags: BlitFlags) void {
            assert(crop_x < bitmap.width);
            assert(crop_y < bitmap.height);
            assert(crop_w != 0);
            assert(crop_h != 0);
            assert(crop_x + crop_w <= bitmap.width);
            assert(crop_y + crop_h <= bitmap.height);
            const f = @intFromEnum(flags);
            assert(0 == f & @intFromEnum(BlitFlags.@"2bpp"));

            // Works around compiler crash. (0.12.0-dev.1735+bece97ef2)
            const mem2 = bitmap.mem;
            w4.blitSub(&mem2, x, y, crop_w, crop_h, crop_x, crop_y, bitmap.width, f | @intFromEnum(bitmap.bpp));
        }
    };
}

/// Draws text using the built-in system font (8x8 pixels per character).
/// The string may contain new-line (\n) characters.
/// Uses color channel 0 for text and color channel 1 for background.
pub fn text(str: []const u8, x: i32, y: i32) void {
    w4.text(str, x, y);
}

pub const KeyCode = enum(u8) {
    /// Char code 0x80.
    button_x = w4.BUTTON_1,
    /// Char code 0x81.
    button_y = w4.BUTTON_2,
    /// Char code 0x84.
    button_left = w4.BUTTON_LEFT,
    /// Char code 0x85.
    button_right = w4.BUTTON_RIGHT,
    /// Char code 0x86.
    button_up = w4.BUTTON_UP,
    /// Char code 0x87.
    button_down = w4.BUTTON_DOWN,

    /// Returns a 1-char string representation of the button, assuming WASM-4's default font.
    pub fn str(key_code: KeyCode) *const [1]u8 {
        return switch (key_code) {
            inline else => |c| &.{
                comptime 0x80 + @as(u8, std.math.log2_int(@typeInfo(KeyCode).Enum.tag_type, @intFromEnum(c))),
            },
        };
    }
};

/// TODO: (CIE)LAB color blending. (here's some LAB code https://github.com/tsunko/vidmap/blob/6858c62237b0d5639bae6864fa97455ec0816d3f/nativemap/src/color.zig)
pub const Color = enum(u24) {
    black = 0x00_00_00,
    white = 0xff_ff_ff,

    red = 0xff_00_00,
    yellow = 0xff_ff_00,
    grellow = 0x80_ff_00,
    green = 0x00_ff_00,
    cyan = 0x00_ff_ff,
    blue = 0x00_00_ff,
    purple = 0xff_00_ff,

    _,
};

const W4State = struct {
    /// The 4 colors available for drawing.
    color_palette: ?[4]Color = null,
    /// What palette slot (0-3) each channel (0-3) references. `null` makes a channel transparent.
    color_channels: ?[4]?u2 = null,
    system_flags: ?struct {
        preserve_framebuffer: ?bool = null,
        hide_gamepad_overlay: ?bool = null,
    } = null,
};
/// Update engine registers.
pub fn setState(state: W4State) void {
    if (state.color_palette) |colors| {
        for (colors, 0..) |color, i|
            w4.PALETTE[i] = @intFromEnum(color);
    }
    if (state.color_channels) |channels| {
        w4.DRAW_COLORS.* = 0;
        for (channels, 0..) |channel, i| {
            if (channel) |n|
                w4.DRAW_COLORS.* |= (@as(u16, n) + 1) << (4 * @as(u4, @intCast(i)));
        }
    }
    if (state.system_flags) |sys_flags| {
        if (sys_flags.preserve_framebuffer) |preserve_framebuffer| {
            if (preserve_framebuffer)
                w4.SYSTEM_FLAGS.* |= w4.SYSTEM_PRESERVE_FRAMEBUFFER
            else
                w4.SYSTEM_FLAGS.* &= ~w4.SYSTEM_PRESERVE_FRAMEBUFFER;
        }
        if (sys_flags.hide_gamepad_overlay) |hide_gamepad_overlay| {
            if (hide_gamepad_overlay)
                w4.SYSTEM_FLAGS.* |= w4.SYSTEM_HIDE_GAMEPAD_OVERLAY
            else
                w4.SYSTEM_FLAGS.* &= ~w4.SYSTEM_HIDE_GAMEPAD_OVERLAY;
        }
    }
}

pub const Input = struct {
    prev: u8 = 0,
    gamepad: *const u8,

    pub fn init(gamepad: u2) Input {
        return .{
            .gamepad = @ptrFromInt(@intFromPtr(w4.GAMEPAD1) + gamepad),
        };
    }

    /// Call at the end of every frame.
    pub fn update(input: *Input) void {
        input.prev = input.gamepad.*;
    }

    const KeyState = enum(u2) {
        still_up = 0b00,
        just_down = 0b01,
        just_up = 0b10,
        still_down = 0b11,
    };

    pub fn getKeyState(input: Input, key_code: KeyCode) KeyState {
        const is_down = 0 != input.gamepad.* & @intFromEnum(key_code);
        const was_down = 0 != input.prev & @intFromEnum(key_code);
        return @enumFromInt((@as(u2, @intFromBool(was_down)) << 1) | @intFromBool(is_down));
    }

    pub fn isDown(input: Input, key_code: KeyCode) bool {
        return 0 != @intFromEnum(input.getKeyState(key_code)) & 1;
    }

    pub fn isUp(input: Input, key_code: KeyCode) bool {
        return !input.isDown(key_code);
    }
};
