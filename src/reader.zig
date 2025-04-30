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
            var buffer: [2]u8 = undefined;
            const n = try self.reader.read(&buffer);
            if(n < 2) {
                return error.NotEnoughBytes;
            }
            const first_byte = @as(i16, @intCast(buffer[0]));
            const second_byte = @as(i16, @intCast(buffer[1]));
            
            return switch(endian) {
                .little => ((second_byte & 0xFF) << 8) | (first_byte & 0xFF),
                .big => ((first_byte & 0xFF) << 8) | (second_byte & 0xFF)
            };
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
}
