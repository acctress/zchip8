const std = @import("std");

const STACK_MAX = 16;

const FONT_BYTES = [_]u8{
    // "0"
    0xF0, 0x90, 0x90, 0x90, 0xF0,
    // "1"
    0x20, 0x60, 0x20, 0x20, 0x70,
    // "2"
    0xF0, 0x10, 0xF0, 0x80, 0xF0,
    // "3"
    0xF0, 0x10, 0xF0, 0x10, 0xF0,
    // "4"
    0x90, 0x90, 0xF0, 0x10, 0x10,
    // "5"
    0xF0, 0x80, 0xF0, 0x10, 0xF0,
    // "6"
    0xF0, 0x80, 0xF0, 0x90, 0xF0,
    // "7"
    0xF0, 0x10, 0x20, 0x40, 0x40,
    // "8"
    0xF0, 0x90, 0xF0, 0x90, 0xF0,
    // "9"
    0xF0, 0x90, 0xF0, 0x10, 0xF0,
    // "A"
    0xF0, 0x90, 0xF0, 0x90, 0x90,
    // "B"
    0xE0, 0x90, 0xE0, 0x90, 0xE0,
    // "C"
    0xF0, 0x80, 0x80, 0x80, 0xF0,
    // "D"
    0xE0, 0x90, 0x90, 0x90, 0xE0,
    // "E"
    0xF0, 0x80, 0xF0, 0x80, 0xF0,
    // "F"
    0xF0, 0x80, 0xF0, 0x80, 0x80,
};

pub const zchip8 = struct {
    allocator: std.mem.Allocator,
    memory: [4096]u8,
    registers: [16]u8,
    stack: std.ArrayListUnmanaged(u16),
    display: [2048]u1,
    key_states: [16]bool,
    key_released: [16]bool,
    idx: u16,
    pc: u16,
    sp: u8,
    delay_timer: u8,
    sound_timer: u8,
    do_increment: bool,

    pub fn init(allocator: std.mem.Allocator, rom_data: []const u8) !zchip8 {
        var mem: [4096]u8 = std.mem.zeroes([4096]u8);
        @memcpy(mem[0x000..FONT_BYTES.len], &FONT_BYTES);
        @memcpy(mem[0x200 .. 0x200 + rom_data.len], rom_data);

        return .{
            .allocator = allocator,
            .memory = mem,
            .registers = std.mem.zeroes([16]u8),
            .stack = try std.ArrayListUnmanaged(u16).initCapacity(allocator, 16),
            .display = std.mem.zeroes([2048]u1),
            .key_states = std.mem.zeroes([16]bool),
            .key_released = std.mem.zeroes([16]bool),
            .idx = 0,
            .pc = 0x200,
            .sp = 0,
            .delay_timer = 0,
            .sound_timer = 0,
            .do_increment = true,
        };
    }

    pub fn deinit(self: *zchip8) void {
        self.stack.deinit(self.allocator);
        self.dump();
    }

    pub fn update_timers(self: *zchip8) void {
        if (self.delay_timer > 0) self.delay_timer -= 1;
        if (self.sound_timer > 0) self.sound_timer -= 1;
    }

    pub fn step(self: *zchip8) !void {
        self.do_increment = true;

        const instruction: u16 = ((@as(u16, self.memory[self.pc]) << 8) | @as(u16, self.memory[self.pc + 1]));
        const opcode = self.getOp(instruction);

        switch (opcode) {
            0x0 => {
                switch (instruction) {
                    // clear
                    0x00E0 => {
                        for (self.display, 0..) |_, idx| {
                            self.display[idx] = 0;
                        }
                    },

                    // subroutine
                    0x00EE => {
                        const pc = self.pop().?;
                        self.pc = pc;
                        self.do_increment = false;
                    },

                    else => {},
                }
            },

            // subroutine
            0x2 => {
                const nnn = self.getNNN(instruction);
                try self.push(self.pc + 2);
                self.pc = nnn;
                self.do_increment = false;
            },

            // jump
            0x1 => {
                const nnn = self.getNNN(instruction);
                self.pc = nnn;
                self.do_increment = false;
            },

            // set register
            0x6 => {
                const x = self.getX(instruction);
                const nn = self.getNN(instruction);
                self.registers[x] = nn;
            },

            // add
            0x7 => {
                const x = self.getX(instruction);
                const nn = self.getNN(instruction);
                const result = self.registers[x] +% nn;
                self.registers[x] = result;
            },

            // set index
            0xA => self.idx = self.getNNN(instruction),

            // random
            0xC => {
                const x = self.getX(instruction);
                const nn = self.getNN(instruction);
                const rand = std.crypto.random.int(u8);
                self.registers[x] = rand & nn;
            },

            // skip conditionally
            0x3 => {
                const x = self.registers[self.getX(instruction)];
                const nn = self.getNN(instruction);
                if (x == nn) self.pc += 2;
            },

            0x4 => {
                const x = self.registers[self.getX(instruction)];
                const nn = self.getNN(instruction);
                if (x != nn) self.pc += 2;
            },

            0x5 => {
                const x = self.registers[self.getX(instruction)];
                const y = self.registers[self.getY(instruction)];
                if (x == y) self.pc += 2;
            },

            0x9 => {
                const x = self.registers[self.getX(instruction)];
                const y = self.registers[self.getY(instruction)];
                if (x != y) self.pc += 2;
            },

            // skip if key
            0xE => {
                switch (self.getNN(instruction)) {
                    0x9E => {
                        const x = self.registers[self.getX(instruction)];
                        if (self.key_states[x] == true) self.pc += 2;
                    },

                    0xA1 => {
                        const x = self.registers[self.getX(instruction)];
                        if (self.key_states[x] == false) self.pc += 2;
                    },

                    else => {},
                }
            },

            // And all the Fs
            0xF => {
                switch (self.getNN(instruction)) {
                    // timers
                    0x07 => self.registers[self.getX(instruction)] = self.delay_timer,
                    0x15 => self.delay_timer = self.registers[self.getX(instruction)],
                    0x18 => self.sound_timer = self.registers[self.getX(instruction)],
                    // add to index
                    0x1E => self.idx += self.registers[self.getX(instruction)],
                    // get key
                    0x0A => {
                        for (self.key_released, 0..) |key, idx| {
                            if (key) {
                                self.registers[self.getX(instruction)] = @as(u8, @intCast(idx));
                                self.key_released[idx] = false;

                                break;
                            }
                        } else {
                            self.pc -= 2;
                        }
                    },
                    // font char
                    0x29 => {
                        const addr = self.registers[self.getX(instruction)] & 0x0F;
                        self.idx = @as(u16, addr) * 5;
                    },
                    // binary encoded decimal conversion
                    0x33 => {
                        const x = self.registers[self.getX(instruction)];
                        self.memory[self.idx] = x / 100;
                        self.memory[self.idx + 1] = (x / 10) % 10;
                        self.memory[self.idx + 2] = x % 10;
                    },
                    0x55 => {
                        const x = @min(self.getX(instruction), 14); // Never touch VF
                        for (0..x + 1) |i| {
                            self.memory[self.idx + i] = self.registers[i];
                        }
                    },
                    0x65 => {
                        const x = @min(self.getX(instruction), 14); // Never touch VF
                        for (0..x + 1) |i| {
                            self.registers[i] = self.memory[self.idx + i];
                        }
                    },
                    else => {},
                }
            },

            // arithmetic operations
            0x8 => {
                const x = self.getX(instruction);
                const y = self.getY(instruction);
                const mode = self.getMode(instruction);

                std.debug.print("X of instructions: {d}, 0x{x}\n", .{ x, x });
                std.debug.print("Y of instructions: {d}, 0x{x}\n", .{ y, y });
                std.debug.print("Opcode 0x8xy{x}: Vx={d}, Vy={d}, VF={d}\n", .{ mode, self.registers[x], self.registers[y], self.registers[0xF] });

                const vx = self.registers[x];
                const vy = self.registers[y];

                switch (mode) {
                    0x0 => {
                        std.debug.print("8XY0 BEFORE: x={d} vx={d} vy={d} VF={d}", .{ x, vx, vy, self.registers[0xf] });
                        self.registers[x] = vy;
                        std.debug.print("8XY0 AFTER: x={d} vx={d} vy={d} VF={d}", .{ x, vx, vy, self.registers[0xf] });
                        self.registers[0xF] = 0;
                    },
                    0x1 => {
                        self.registers[x] = vx | vy;
                        self.registers[0xF] = 0;
                    },
                    0x2 => {
                        self.registers[x] = vx & vy;
                        self.registers[0xF] = 0;
                    },
                    0x3 => {
                        self.registers[x] = vx ^ vy;
                        self.registers[0xF] = 0;
                    },
                    0x4 => { // add
                        const sum = @as(u16, vx) + @as(u16, vy);
                        self.registers[x] = @truncate(sum);
                        self.registers[0xF] = if (sum > 0xFF) 1 else 0;
                    },
                    0x5 => { // sub
                        self.registers[x] = vx -% vy;
                        self.registers[0xF] = if (vx >= vy) 1 else 0;
                    },
                    0x6 => { // shift right - MODERN behavior (Vx = Vy >> 1)
                        const lsb = vy & 1;
                        self.registers[x] = vy >> 1;
                        self.registers[0xF] = lsb;
                    },
                    0xE => { // shift left
                        const msb = (vy >> 7) & 1;
                        const result = vy << 1;
                        self.registers[x] = result;
                        self.registers[0xF] = msb;
                    },
                    0x7 => { // sub but y - x
                        self.registers[x] = vy -% vx;
                        self.registers[0xF] = if (vy >= vx) 1 else 0;
                    },
                    else => {},
                }
            },

            // display
            0xD => {
                const n = self.getMode(instruction);
                const vx = self.registers[self.getX(instruction)];
                const vy = self.registers[self.getY(instruction)];

                self.registers[0xF] = 0;

                for (0..n) |row_idx| {
                    const py = (vy + row_idx) % 32;
                    const sprite_byte = self.memory[self.idx + row_idx];

                    for (0..8) |col_idx| {
                        const px = (vx + col_idx) % 64;

                        const bit = (sprite_byte >> @as(u3, @intCast(7 - col_idx))) & 1;
                        if (bit == 1) {
                            const pixel_index = px + (py * 64);
                            if (self.display[pixel_index] == 1) {
                                self.registers[0xF] = 1;
                                self.display[pixel_index] = 0;
                            } else {
                                self.display[pixel_index] = 1;
                            }
                        }
                    }
                }
            },

            else => {},
        }

        if (self.do_increment) self.pc += 2;
    }

    pub fn dump(self: *zchip8) void {
        std.debug.print("dumped memory from 0x200 to 0xFFF:\n", .{});
        for (self.memory[0x200..0xFFF]) |b| {
            std.debug.print("0x{x}, ", .{b});
        }
        std.debug.print("\n\n", .{});

        std.debug.print("registers:\n", .{});
        for (self.registers, 0..) |v, idx| {
            std.debug.print("V{d} = {d}\n", .{ idx, v });
        }
        std.debug.print("\n\n", .{});
    }

    /// push to the stack
    fn push(self: *zchip8, value: u16) !void {
        if (self.stack.items.len == STACK_MAX) return error.MaxStackSizeReached;
        try self.stack.append(self.allocator, value);
    }

    /// pop from the stack
    fn pop(self: *zchip8) ?u16 {
        return self.stack.pop();
    }

    fn getOp(self: *zchip8, n: u16) u8 {
        _ = self;
        return @truncate((n >> 12) & 0xF);
    }

    fn getX(self: *zchip8, n: u16) u8 {
        _ = self;
        return @truncate((n >> 8) & 0xF);
    }

    fn getY(self: *zchip8, n: u16) u8 {
        _ = self;
        return @truncate((n >> 4) & 0xF);
    }

    fn getMode(self: *zchip8, n: u16) u8 {
        _ = self;
        return @truncate(n & 0xF);
    }

    fn getNN(self: *zchip8, n: u16) u8 {
        _ = self;
        return @truncate(n & 0xFF);
    }

    fn getNNN(self: *zchip8, n: u16) u16 {
        _ = self;
        return @truncate(n & 0xFFF);
    }
};
