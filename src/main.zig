const std = @import("std");
const sdl3 = @import("sdl3");
const zchip8 = @import("zchip8").zchip8;

const SCALE = 10;
const FPS = 60;
const SCREEN_WIDTH = 64 * SCALE;
const SCREEN_HEIGHT = 32 * SCALE;

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

    const rom = try std.fs.cwd().readFileAlloc(allocator, "tests/Puzzle.ch8", 4096);
    var cpu: zchip8 = try .init(allocator, rom);
    defer cpu.deinit();

    cpu.dump();

    var fps_capper = sdl3.extras.FramerateCapper(f32){ .mode = .{ .limited = FPS } };
    var quit = false;
    while (!quit) {
        const dt = fps_capper.delay();
        _ = dt;

        cpu.update_timers();
        for (0..12) |_| {
            try cpu.step();
        }

        const surface = try window.getSurface();

        try surface.fillRect(null, surface.mapRgb(30, 25, 45));

        for (cpu.display, 0..) |pixel, idx| {
            const x: i32 = @mod(@as(i32, @intCast(idx)), 64) * SCALE;
            const y: i32 = @divTrunc(@as(i32, @intCast(idx)), 64) * SCALE;

            if (pixel == 1) {
                try surface.fillRect(
                    sdl3.rect.IRect{ .x = x, .y = y, .w = SCALE, .h = SCALE },
                    surface.mapRgb(105, 90, 150),
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
                        .one => cpu.key_states[1] = true,
                        .two => cpu.key_states[2] = true,
                        .three => cpu.key_states[3] = true,
                        .four => cpu.key_states[0xC] = true,
                        .q => cpu.key_states[4] = true,
                        .w => cpu.key_states[5] = true,
                        .e => cpu.key_states[6] = true,
                        .r => cpu.key_states[0xD] = true,
                        .a => cpu.key_states[7] = true,
                        .s => cpu.key_states[8] = true,
                        .d => cpu.key_states[9] = true,
                        .f => cpu.key_states[0xE] = true,
                        .z => cpu.key_states[0xA] = true,
                        .x => cpu.key_states[0] = true,
                        .y => cpu.key_states[0xB] = true,
                        .v => cpu.key_states[0xF] = true,
                        else => {},
                    }
                },
                .key_up => |k| {
                    switch (k.key.?) {
                        .one => {
                            cpu.key_states[1] = false;
                            cpu.key_released[1] = true;
                        },
                        .two => {
                            cpu.key_states[2] = false;
                            cpu.key_released[2] = true;
                        },
                        .three => {
                            cpu.key_states[3] = false;
                            cpu.key_released[3] = true;
                        },
                        .four => {
                            cpu.key_states[0xC] = false;
                            cpu.key_released[0xC] = true;
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
                            cpu.key_states[0xD] = false;
                            cpu.key_released[0xD] = true;
                        },
                        .a => {
                            cpu.key_states[7] = false;
                            cpu.key_released[7] = true;
                        },
                        .s => {
                            cpu.key_states[8] = false;
                            cpu.key_released[8] = true;
                        },
                        .d => {
                            cpu.key_states[9] = false;
                            cpu.key_released[9] = true;
                        },
                        .f => {
                            cpu.key_states[0xE] = false;
                            cpu.key_released[0xE] = true;
                        },
                        .z => {
                            cpu.key_states[0xA] = false;
                            cpu.key_released[0xA] = true;
                        },
                        .x => {
                            cpu.key_states[0] = false;
                            cpu.key_released[0] = true;
                        },
                        .y => {
                            cpu.key_states[0xB] = false;
                            cpu.key_released[0xB] = true;
                        },
                        .v => {
                            cpu.key_states[0xF] = false;
                            cpu.key_released[0xF] = true;
                        },
                        else => {},
                    }
                },
                else => {},
            };
    }
}
