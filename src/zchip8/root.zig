const std = @import("std");

const STACK_MAX = 16;

const FONT_BYTES = [_]u8{
    // "0"
    0xF0, 0x90, 0x90, 0x90, 0x90,
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
    stack: std.ArrayList(u16),
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
        @memcpy(mem[0x000..0x050], &FONT_BYTES);
        @memcpy(mem[0x200 .. 0x200 + rom_data.len], rom_data);

        return .{
            .allocator = allocator,
            .memory = mem,
            .registers = std.mem.zeroes([16]u8),
            .stack = .empty,
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
                    },

                    else => {},
                }
            },

            // subroutine
            0x2 => {
                const nnn = self.getNNN(instruction);
                try self.push(self.pc);
                self.pc = nnn;
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
                self.registers[x] += nn;
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
                        const addr = self.registers[self.getX(instruction)];
                        self.idx = addr * 5;
                    },
                    // binary encoded decimal conversion
                    0x33 => {
                        const x = self.registers[self.getX(instruction)];
                        self.memory[self.idx] = x / 100;
                        self.memory[self.idx + 1] = (x / 10) % 10;
                        self.memory[self.idx + 2] = x % 10;
                    },
                    // store memory
                    0x55 => {
                        const x = self.getX(instruction);
                        for (0..x + 1) |i| {
                            self.memory[self.idx + i] = self.registers[i];
                        }
                    },
                    // load memory
                    0x65 => {
                        const x = self.getX(instruction);
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

                const a = self.registers[x];
                const b = self.registers[y];

                switch (mode) {
                    0x0 => self.registers[x] = b,
                    0x1 => self.registers[x] = a | b,
                    0x2 => self.registers[x] = a & b,
                    0x3 => self.registers[x] = a ^ b,
                    0x4 => {
                        const result = a +% b;
                        if (a > std.math.maxInt(u8) - b) {
                            self.registers[0xF] = 1;
                        } else {
                            self.registers[0xF] = 0;
                        }

                        self.registers[x] = result;
                    },
                    0x5 => {
                        const result = a -% b;
                        if (a > b) {
                            self.registers[0xF] = 1;
                        } else {
                            self.registers[0xF] = 0;
                        }

                        self.registers[x] = result;
                    },
                    0x7 => {
                        const result = b -% a;
                        if (b > a) {
                            self.registers[0xF] = 1;
                        } else {
                            self.registers[0xF] = 0;
                        }

                        self.registers[x] = result;
                    },
                    // shift right
                    0x6 => {
                        const falls_off = (self.registers[x] & 1) == 1;
                        if (falls_off) {
                            self.registers[0xF] = 1;
                        } else {
                            self.registers[0xF] = 0;
                        }

                        self.registers[x] >>= 1;
                    },
                    // shift left
                    0xE => {
                        const falls_off = (self.registers[x] & 0x80) == 0x80;
                        if (falls_off) {
                            self.registers[0xF] = 1;
                        } else {
                            self.registers[0xF] = 0;
                        }

                        self.registers[x] <<= 1;
                    },
                    else => {},
                }
            },

            // display
            0xD => {
                const x = self.registers[self.getX(instruction)] & 63;
                const y = self.registers[self.getY(instruction)] & 31;
                self.registers[0xF] = 0;

                // last N
                const n = self.getMode(instruction);
                for (0..n) |idx| {
                    const n_byte = self.memory[self.idx + idx];
                    for (0..8) |b| {
                        const px = x + (@as(u3, @intCast(b)));
                        const py = y + idx;

                        if (px >= 64 or py >= 32) continue;

                        const sp_pixel = (n_byte >> 7 - @as(u3, @intCast(b))) & 1;
                        const sc_pixel = self.display[px + py * 64];

                        if (sp_pixel == 1) {
                            if (sc_pixel == 1) {
                                self.registers[0xF] = 1;
                                self.display[px + py * 64] = 0;
                            } else {
                                self.display[px + py * 64] = 1;
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
        std.debug.print("dumped memory from 0x200 to 0x300:\n", .{});
        for (self.memory[0x200..0x300]) |b| {
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
