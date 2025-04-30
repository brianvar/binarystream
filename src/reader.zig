const std = @import("std");

pub fn BinaryStreamReader(comptime ReaderType: type) type {
    return struct {
        const Self = *const @This();

        reader: ReaderType,

        pub fn read_byte(self: Self) !u8 {
            return self.reader.readByte();
        }

        pub fn read_bool(self: Self) !bool {
            return try self.read_byte() != 0;
        }

        pub fn read_short(self: Self, endian: std.builtin.Endian) !i16 {
            const buffer = try self.try_get(2);
            const first_byte: i16 = @intCast(buffer[0]);
            const second_byte: i16 = @intCast(buffer[1]);
            
            return switch(endian) {
                .little => second_byte << 8 | first_byte,
                .big => first_byte << 8 | second_byte
            };
        }

        pub fn read_ushort(self: Self, endian: std.builtin.Endian) !u16 {
            const buffer = try self.try_get(2);
            const first_byte: u16 = @intCast(buffer[0]);
            const second_byte: u16 = @intCast(buffer[1]);

            return switch(endian) {
                .little => second_byte << 8 | first_byte,
                .big => first_byte << 8 | second_byte
            };
        }

        pub fn read_triad(self: Self, endian: std.builtin.Endian) !i24 {
            const buffer = try self.try_get(3);
            const first_byte: i24 = @intCast(buffer[0]);
            const second_byte: i24 = @intCast(buffer[1]);
            const third_byte: i24 = @intCast(buffer[2]);
            
            return switch(endian) {
                .little => third_byte << 16 | second_byte << 8 | first_byte,
                .big => first_byte << 16 | second_byte << 8 | third_byte
            };
        }

        pub fn read_utriad(self: Self, endian: std.builtin.Endian) !u24 {
            const buffer = try self.try_get(3);
            const first_byte: u24 = @intCast(buffer[0]);
            const second_byte: u24 = @intCast(buffer[1]);
            const third_byte: u24 = @intCast(buffer[2]);
            
            return switch(endian) {
                .little => third_byte << 16 | second_byte << 8 | first_byte,
                .big => first_byte << 16 | second_byte << 8 | third_byte
            };
        }

        fn try_get(self: Self, comptime size: usize) ![size]u8 {
            var buffer: [size]u8 = undefined;
            const n = try self.reader.read(&buffer);
            if(n < 2) {
                return error.NotEnoughBytes;
            }
            return buffer;
        }
    };
}

pub fn binaryStreamReader(reader: anytype) BinaryStreamReader(@TypeOf(reader)) {
    return .{ .reader = reader };
}

test "basic read" {
    const buffer = [_]u8{
        1, 2, 3, 4, // byte
        1, 0, // boolean
        12, 254, // little-endian short (-500)
        254, 12, // big-endian short (-500)
        48, 117, // little-endian ushort (30000 == 0u)
        117, 48, // big-endian ushort (30000 == u0)
        128, 193, 255, // little-endian triad
        255, 193, 128, // big-endian triad
        160, 140, 0, // little-endian utriad
        0, 140, 160, // big-endian utriad
        96, 121, 254, 255, // little-endian int
        255, 254, 121, 96, // big-endian int
        160, 134, 1, 0, // little-endian uint
        0, 1, 134, 160, // big-endian uint
        198, 205, 15, 107, 41, 64, 212, 255, // little-endian long
        255, 212, 64, 41, 107, 15, 205, 198, // big-endian long
        58, 50, 240, 148, 214, 191, 43, 0, // little-endian ulong
        0, 43, 191, 214, 148, 240, 50, 58, // big-endian ulong
        119, 222, 246, 66, // little-endian float
        66, 246, 222, 119, // big-endian float
        108, 194, 186, 12, 207, 219, 94, 64, // little-endian double
        64, 94, 219, 207, 12, 186, 194, 108, // big-endian double
    };

    var list = std.ArrayList(u8).init(std.testing.allocator);
    try list.appendSlice(&buffer);
    defer list.deinit();

    var buffer_stream = std.io.fixedBufferStream(list.items);
    const reader = buffer_stream.reader();
    const stream = binaryStreamReader(reader);

    // byte
    try std.testing.expect(try stream.read_byte() == 1);
    try std.testing.expect(try stream.read_byte() == 2);
    try std.testing.expect(try stream.read_byte() == 3);
    try std.testing.expect(try stream.read_byte() == 4);

    // bool
    try std.testing.expect(try stream.read_bool() == true);
    try std.testing.expect(try stream.read_bool() == false);

    // short
    try std.testing.expect(try stream.read_short(.little) == -500);
    try std.testing.expect(try stream.read_short(.big) == -500);
    try std.testing.expect(try stream.read_ushort(.little) == 30000);
    try std.testing.expect(try stream.read_ushort(.big) == 30000);

    // triad
    try std.testing.expect(try stream.read_triad(.little) == -16000);
    try std.testing.expect(try stream.read_triad(.big) == -16000);
    try std.testing.expect(try stream.read_utriad(.little) == 36000);
    try std.testing.expect(try stream.read_utriad(.big) == 36000);
}
