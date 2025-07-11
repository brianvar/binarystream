const std = @import("std");

pub const BinaryStreamWriter = struct {
    const Self = *@This();

    writer: std.io.Writer,

    pub fn write(self: Self, value: []const u8) !usize {
        return try self.writer.write(value);
    }

    pub fn writeBool(self: Self, value: bool) !usize {
        const data = [1]u8{@intFromBool(value)};
        return try self.writer.write(data[0..]);
    }

    pub fn writeByte(self: Self, value: u8) !usize {
        const data = [1]u8{value};
        return try self.writer.write(data[0..]);
    }

    pub fn writeShort(self: Self, value: i16, endian: std.builtin.Endian) !usize {
        const data = std.mem.toBytes(std.mem.nativeTo(i16, value, endian));
        return try self.writer.write(data[0..]);
    }

    pub fn writeUnsignedShort(self: Self, value: u16, endian: std.builtin.Endian) !usize {
        const data = std.mem.toBytes(std.mem.nativeTo(u16, value, endian));
        return try self.writer.write(data[0..]);
    }

    pub fn writeTriad(self: Self, value: i24, endian: std.builtin.Endian) !usize {
        const data = std.mem.toBytes(std.mem.nativeTo(i24, value, endian));
        return try self.writer.write(data[0..3]);
    }

    pub fn writeUnsignedTriad(self: Self, value: u24, endian: std.builtin.Endian) !usize {
        const data = std.mem.toBytes(std.mem.nativeTo(u24, value, endian));
        return try self.writer.write(data[0..3]);
    }

    pub fn writeInt(self: Self, value: i32, endian: std.builtin.Endian) !usize {
        const data = std.mem.toBytes(std.mem.nativeTo(i32, value, endian));
        return try self.writer.write(data[0..]);
    }

    pub fn writeUnsignedInt(self: Self, value: u32, endian: std.builtin.Endian) !usize {
        const data = std.mem.toBytes(std.mem.nativeTo(u32, value, endian));
        return try self.writer.write(data[0..]);
    }

    pub fn writeLong(self: Self, value: i64, endian: std.builtin.Endian) !usize {
        const data = std.mem.toBytes(std.mem.nativeTo(i64, value, endian));
        return try self.writer.write(data[0..]);
    }

    pub fn writeUnsignedLong(self: Self, value: u64, endian: std.builtin.Endian) !usize {
        const data = std.mem.toBytes(std.mem.nativeTo(u64, value, endian));
        return try self.writer.write(data[0..]);
    }

    pub fn writeFloat(self: Self, value: f32, endian: std.builtin.Endian) !usize {
        // cast to u32 since nativeTo cannot bitSwap floats
        const data = std.mem.toBytes(std.mem.nativeTo(u32, @bitCast(value), endian));
        return try self.writer.write(data[0..]);
    }

    pub fn writeDouble(self: Self, value: f64, endian: std.builtin.Endian) !usize {
        // cast to u64 since nativeTo cannot bitSwap floats
        const data = std.mem.toBytes(std.mem.nativeTo(u64, @bitCast(value), endian));
        return try self.writer.write(data[0..]);
    }

    pub fn flush(self: Self) !void {
        try self.writer.flush();
    }
};

test "basic write" {
    var list = try std.ArrayList(u8).initCapacity(std.testing.allocator, 256);
    list.expandToCapacity();
    defer list.deinit();

    var stream = BinaryStreamWriter{ .writer = .fixed(list.allocatedSlice()) };

    // byte
    const byte_buffer = [3]u8{ 1, 2, 3 };
    _ = try stream.write(byte_buffer[0..]);
    _ = try stream.writeByte(4);

    // bool
    _ = try stream.writeBool(true);
    _ = try stream.writeBool(false);

    // short
    _ = try stream.writeShort(-500, .little);
    _ = try stream.writeShort(-500, .big);
    _ = try stream.writeUnsignedShort(30000, .little);
    _ = try stream.writeUnsignedShort(30000, .big);

    // triad
    _ = try stream.writeTriad(-16000, .little);
    _ = try stream.writeTriad(-16000, .big);
    _ = try stream.writeUnsignedTriad(36000, .little);
    _ = try stream.writeUnsignedTriad(36000, .big);

    // int
    _ = try stream.writeInt(-100000, .little);
    _ = try stream.writeInt(-100000, .big);
    _ = try stream.writeUnsignedInt(100000, .little);
    _ = try stream.writeUnsignedInt(100000, .big);

    // long
    _ = try stream.writeLong(-12314352341234234, .little);
    _ = try stream.writeLong(-12314352341234234, .big);
    _ = try stream.writeUnsignedLong(12314352341234234, .little);
    _ = try stream.writeUnsignedLong(12314352341234234, .big);

    // float
    _ = try stream.writeFloat(123.4345, .little);
    _ = try stream.writeFloat(123.4345, .big);

    // double
    _ = try stream.writeDouble(123.4345123123, .little);
    _ = try stream.writeDouble(123.4345123123, .big);

    // Don't forget to flush!
    try stream.flush();

    // https://www.eso.org/~ndelmott/ascii.html
    const expected_buffer = [_]u8{
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

    try std.testing.expect(std.mem.eql(u8, list.items[0..stream.writer.end], &expected_buffer));
}
