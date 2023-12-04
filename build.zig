const std = @import("std");
const LazyPath = std.Build.LazyPath;

/// Path to wasm4 cli binary.
const w4_path = "w4";

const cart_info = struct {
    const title = "My WASM-4 Game";
    const description =
        \\TBD
    ;
    const root_source_file = "src/main.zig";
    const version = std.SemanticVersion.parse("0.0.0") catch unreachable;
    const icon: Icon = .none;
};

const Icon = union(enum) {
    none,
    file: LazyPath,
    url: []const u8,
};

fn addCart(b: *std.Build, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const cart = b.addExecutable(.{
        .name = "cart",
        .root_source_file = .{ .path = cart_info.root_source_file },
        .target = .{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        },
        .optimize = optimize,
        .version = cart_info.version,
    });

    cart.entry = .disabled;
    cart.export_symbol_names = &.{ "start", "update" };
    cart.import_memory = true;
    cart.initial_memory = std.wasm.page_size;
    cart.max_memory = std.wasm.page_size;
    cart.stack_size = 14752;

    const build_time_options = b.addOptions();
    build_time_options.addOption(std.SemanticVersion, "version", cart_info.version);
    cart.addOptions("build_time_options", build_time_options);

    return cart;
}

pub fn build(b: *std.Build) void {
    const cart = addCart(b, b.standardOptimizeOption(.{}));
    b.installArtifact(cart);

    const watch_cmd = b.addSystemCommand(&.{
        w4_path, "watch",
    });
    if (b.option(bool, "hotswap", "Used with `watch`. Hot-swap the binary without resetting runtime memory") orelse false) {
        watch_cmd.addArg("--hot");
    }

    b.step("watch", "Auto-rebuild when files change and refresh browser tab")
        .dependOn(&watch_cmd.step);

    const release_step = b.step("release", "Build for release and bundle for distribution (ignores -Doptimize)");
    const release_cart = addCart(b, .ReleaseSmall);
    inline for (comptime std.meta.tags(enum { linux, mac, html, windows })) |platform| {
        const bundle_cmd = b.addSystemCommand(&.{
            w4_path,              "bundle",
            "--title",            cart_info.title,
            "--description",      cart_info.description,
            "--html-disk-prefix", b.fmt("{s} {}", .{ cart_info.title, cart_info.version }),
        });
        switch (cart_info.icon) {
            .none => {},
            .file => |lp| {
                bundle_cmd.addArg("--icon-file");
                bundle_cmd.addFileArg(lp);
            },
            .url => |url| bundle_cmd.addArgs(&.{ "--icon-file", url }),
        }
        const install_basename = switch (platform) {
            .linux, .mac => cart_info.title,
            .html => std.fmt.comptimePrint("{s}.html", .{cart_info.title}),
            .windows => std.fmt.comptimePrint("{s}.exe", .{cart_info.title}),
        };
        bundle_cmd.addArg("--" ++ @tagName(platform));
        const output =
            bundle_cmd.addOutputFileArg(install_basename);
        bundle_cmd.addFileArg(release_cart.getEmittedBin());

        release_step.dependOn(&b.addInstallBinFile(output, switch (platform) {
            .linux, .mac, .windows => "native-" ++ @tagName(platform),
            .html => ".",
        } ++ "/" ++ install_basename).step);
    }

    const run_cmd = b.addSystemCommand(&.{
        w4_path, "run-native",
    });
    run_cmd.addFileArg(cart.getEmittedBin());

    b.step("run", "Build and run")
        .dependOn(&run_cmd.step);
}
