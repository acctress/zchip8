const std = @import("std");
const sdl3 = @import("sdl3");
const zchip8 = @import("zchip8").zchip8;

const FPS = 60;
const SCREEN_WIDTH = 64 * 10;
const SCREEN_HEIGHT = 32 * 10;

pub fn main() !void {
    defer sdl3.shutdown();

    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const init_flags = sdl3.InitFlags{ .video = true };
    try sdl3.init(init_flags);
    defer sdl3.quit(init_flags);

    const window = try sdl3.video.Window.init(
        "chip-8",
        SCREEN_WIDTH,
        SCREEN_HEIGHT,
        .{},
    );
    defer window.deinit();

    const rom = try std.fs.cwd().readFileAlloc(allocator, "tests/1-chip8-logo.ch8", 4096);
    var cpu: zchip8 = try .init(rom);
    cpu.dump();

    var fps_capper = sdl3.extras.FramerateCapper(f32){ .mode = .{ .limited = FPS } };
    var quit = false;
    while (!quit) {
        const dt = fps_capper.delay();
        _ = dt;

        cpu.step();

        const surface = try window.getSurface();
        try surface.fillRect(null, surface.mapRgb(0, 0, 0));

        for (cpu.display, 0..) |pixel, idx| {
            const x: i32 = @mod(@as(i32, @intCast(idx)), 64) * 10;
            const y: i32 = @divTrunc(@as(i32, @intCast(idx)), 64) * 10;

            if (pixel == 1) {
                try surface.fillRect(
                    sdl3.rect.IRect{ .x = x, .y = y, .w = 10, .h = 10 },
                    surface.mapRgb(255, 255, 255),
                );
            }
        }

        try window.updateSurface();

        while (sdl3.events.poll()) |event|
            switch (event) {
                .quit => quit = true,
                .terminating => quit = true,
                else => {},
            };
    }
}
