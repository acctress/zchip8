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

    const rom = try std.fs.cwd().readFileAlloc(allocator, "tests/4-flags.ch8", 4096);
    var cpu: zchip8 = try .init(allocator, rom);
    defer cpu.deinit();

    cpu.dump();

    var fps_capper = sdl3.extras.FramerateCapper(f32){ .mode = .{ .limited = FPS } };
    var quit = false;
    while (!quit) {
        const dt = fps_capper.delay();
        _ = dt;

        cpu.update_timers();
        for (0..10) |_| {
            try cpu.step();
        }

        const surface = try window.getSurface();

        std.debug.print("in render loop: {any}\n", .{cpu.display[0..8]});

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
                .key_down => |k| {
                    switch (k.key.?) {
                        .one => cpu.key_states[0] = true,
                        .two => cpu.key_states[1] = true,
                        .three => cpu.key_states[2] = true,
                        .four => cpu.key_states[3] = true,
                        .q => cpu.key_states[4] = true,
                        .w => cpu.key_states[5] = true,
                        .e => cpu.key_states[6] = true,
                        .r => cpu.key_states[7] = true,
                        .a => cpu.key_states[8] = true,
                        .s => cpu.key_states[9] = true,
                        .d => cpu.key_states[10] = true,
                        .f => cpu.key_states[11] = true,
                        .z => cpu.key_states[12] = true,
                        .x => cpu.key_states[13] = true,
                        .c => cpu.key_states[14] = true,
                        .v => cpu.key_states[15] = true,
                        else => {},
                    }
                },
                .key_up => |k| {
                    switch (k.key.?) {
                        .one => {
                            cpu.key_states[0] = false;
                            cpu.key_released[0] = true;
                        },
                        .two => {
                            cpu.key_states[1] = false;
                            cpu.key_released[1] = true;
                        },
                        .three => {
                            cpu.key_states[2] = false;
                            cpu.key_released[2] = true;
                        },
                        .four => {
                            cpu.key_states[3] = false;
                            cpu.key_released[3] = true;
                        },
                        .q => {
                            cpu.key_states[4] = false;
                            cpu.key_released[4] = true;
                        },
                        .w => {
                            cpu.key_states[5] = false;
                            cpu.key_released[5] = true;
                        },
                        .e => {
                            cpu.key_states[6] = false;
                            cpu.key_released[6] = true;
                        },
                        .r => {
                            cpu.key_states[7] = false;
                            cpu.key_released[7] = true;
                        },
                        .a => {
                            cpu.key_states[8] = false;
                            cpu.key_released[8] = true;
                        },
                        .s => {
                            cpu.key_states[9] = false;
                            cpu.key_released[9] = true;
                        },
                        .d => {
                            cpu.key_states[10] = false;
                            cpu.key_released[10] = true;
                        },
                        .f => {
                            cpu.key_states[11] = false;
                            cpu.key_released[11] = true;
                        },
                        .z => {
                            cpu.key_states[12] = false;
                            cpu.key_released[12] = true;
                        },
                        .x => {
                            cpu.key_states[13] = false;
                            cpu.key_released[13] = true;
                        },
                        .c => {
                            cpu.key_states[14] = false;
                            cpu.key_released[14] = true;
                        },
                        .v => {
                            cpu.key_states[15] = false;
                            cpu.key_released[15] = true;
                        },
                        else => {},
                    }
                },
                else => {},
            };
    }
}
