const std = @import("std");
const assert = std.debug.assert;
const w4 = @import("wasm4.zig");
const w4_vendor = @import("vendor/wasm4.zig");
const build_time_options = @import("build_time_options");
const version_text = std.fmt.comptimePrint("v{}", .{build_time_options.version});

const smiley = w4.Bitmap(
    \\
    \\     x x x x    
    \\   x x x x x x  
    \\ x x   x x   x x
    \\ x x   x x   x x
    \\ x x x x x x x x
    \\ x x o - - o x x
    \\   x - o o - x  
    \\     x x x x    
,
    "x o-",
){};

var input: w4.Input = undefined;

export fn start() void {
    input = w4.Input.init(0);

    w4.setState(.{
        .color_palette = .{
            w4.Color.white,
            w4.Color.black,
            w4.Color.red,
            w4.Color.grellow,
        },
    });
}

export fn update() void {
    defer input.update();

    w4.setState(.{
        .color_channels = .{ 1, null, null, null },
    });

    w4.text("Hello from\nZig!", 10, 10);
    w4.text(version_text, 160 - version_text.len * 8, 152);

    const x_pressed = input.isDown(.button_x);

    w4.setState(.{
        .color_channels = if (x_pressed)
            .{ 2, null, 2, 1 }
        else
            .{ 1, null, null, 1 },
    });

    smiley.blit(76, 76, .none);

    if (x_pressed) w4.setState(.{
        .color_channels = .{ 3, 1, null, null },
    });
    w4.text("Press " ++ w4.KeyCode.button_x.str() ++ " to blink", 16, 90);
}
