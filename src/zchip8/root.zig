const std = @import("std");

pub const zchip8 = struct {
    memory: [4096]u8,
    registers: [16]u8,
    stack: [16]u16,
    display: [2048]u1,
    idx: u16,
    pc: u16,
    sp: u8,
    delay_timer: u8,
    sound_timer: u8,
    do_increment: bool,

    pub fn init(rom_data: []const u8) !zchip8 {
        var mem: [4096]u8 = std.mem.zeroes([4096]u8);
        @memcpy(mem[0x200 .. 0x200 + rom_data.len], rom_data);

        return .{
            .memory = mem,
            .registers = std.mem.zeroes([16]u8),
            .stack = std.mem.zeroes([16]u16),
            .display = std.mem.zeroes([2048]u1),
            .idx = 0,
            .pc = 0x200,
            .sp = 0,
            .delay_timer = 0,
            .sound_timer = 0,
            .do_increment = true,
        };
    }

    pub fn step(self: *zchip8) void {
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

                    else => {},
                }
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
