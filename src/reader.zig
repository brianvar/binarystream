const std = @import("std");
const native_endian = @import("builtin").target.cpu.arch.endian();

fn reverseBuffer(buffer: []u8) void {
    for (0..buffer.len / 2) |i| {
        std.mem.swap(u8, &buffer[i], &buffer[buffer.len - 1 - i]);
    }
}

pub const BinaryStreamReader = struct {
    const Self = *@This();

    reader: std.io.Reader,

    pub fn readByte(self: Self) !u8 {
        return self.reader.takeByte();
    }

    pub fn readBytes(self: Self, count: usize) ![]u8 {
        return try self.reader.take(count);
    }

    pub fn readBool(self: Self) !bool {
        return try self.readByte() != 0;
    }

    pub fn readShort(self: Self, comptime T: type, endian: std.builtin.Endian) !T {
        return self.readNumber(2, T, endian);
    }

    pub fn readTriad(self: Self, comptime T: type, endian: std.builtin.Endian) !T {
        return self.readNumber(3, T, endian);
    }

    pub fn readInt(self: Self, comptime T: type, endian: std.builtin.Endian) !T {
        return self.readNumber(4, T, endian);
    }

    pub fn readLong(self: Self, comptime T: type, endian: std.builtin.Endian) !T {
        return self.readNumber(8, T, endian);
    }

    pub fn readFloat(self: Self, endian: std.builtin.Endian) !f32 {
        return self.readFloatingPointNumber(4, f32, endian);
    }

    pub fn readDouble(self: Self, endian: std.builtin.Endian) !f64 {
        return self.readFloatingPointNumber(8, f64, endian);
    }

    pub fn readNumber(self: Self, comptime bytes: usize, comptime T: type, endian: std.builtin.Endian) !T {
        return try self.reader.takeVarInt(T, endian, bytes);
    }

    pub fn readFloatingPointNumber(self: Self, comptime bytes: usize, comptime T: type, endian: std.builtin.Endian) !T {
        var buffer = try self.reader.take(bytes);

        // we need this hacks since we can't @byteSwap floats and doubles
        switch (native_endian) {
            .little => {
                if (endian == .big) {
                    reverseBuffer(buffer);
                }
            },
            .big => {
                if (endian == .little) {
                    reverseBuffer(buffer);
                }
            },
        }

        return std.mem.bytesAsValue(T, buffer[0..bytes]).*;
    }
};

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

    const reader = std.io.Reader.fixed(list.items);
    var stream = BinaryStreamReader{ .reader = reader };

    // byte
    const three_bytes: []u8 = try stream.readBytes(3);
    try std.testing.expect(three_bytes.len == 3);
    try std.testing.expect(std.mem.eql(u8, three_bytes, buffer[0..3]));
    try std.testing.expect(try stream.readByte() == 4);

    // bool
    try std.testing.expect(try stream.readBool() == true);
    try std.testing.expect(try stream.readBool() == false);

    // short
    try std.testing.expect(try stream.readShort(i16, .little) == -500);
    try std.testing.expect(try stream.readShort(i16, .big) == -500);
    try std.testing.expect(try stream.readShort(u16, .little) == 30000);
    try std.testing.expect(try stream.readShort(u16, .big) == 30000);

    // triad
    try std.testing.expect(try stream.readTriad(i24, .little) == -16000);
    try std.testing.expect(try stream.readTriad(i24, .big) == -16000);
    try std.testing.expect(try stream.readTriad(u24, .little) == 36000);
    try std.testing.expect(try stream.readTriad(u24, .big) == 36000);

    // int
    try std.testing.expect(try stream.readInt(i32, .little) == -100000);
    try std.testing.expect(try stream.readInt(i32, .big) == -100000);
    try std.testing.expect(try stream.readInt(u32, .little) == 100000);
    try std.testing.expect(try stream.readInt(u32, .big) == 100000);

    // long
    try std.testing.expect(try stream.readLong(i64, .little) == -12314352341234234);
    try std.testing.expect(try stream.readLong(i64, .big) == -12314352341234234);
    try std.testing.expect(try stream.readLong(u64, .little) == 12314352341234234);
    try std.testing.expect(try stream.readLong(u64, .big) == 12314352341234234);

    // float
    try std.testing.expect(try stream.readFloat(.little) == 123.4345);
    try std.testing.expect(try stream.readFloat(.big) == 123.4345);

    // double
    try std.testing.expect(try stream.readDouble(.little) == 123.4345123123);
    try std.testing.expect(try stream.readDouble(.big) == 123.4345123123);
}
