const std = @import("std");

pub fn BinaryStreamWriter(comptime buffer_size: usize, comptime WriterType: type) type {
    return struct {
        const Self = *@This();

        writer: std.io.BufferedWriter(buffer_size, WriterType),

        pub fn write(self: Self, value: []const u8) !usize {
            return try self.writer.write(value);
        }

        pub fn write_bool(self: Self, value: bool) !usize {
            const data = [1]u8{ @intFromBool(value) };
            return try self.writer.write(data[0..]);
        }

        pub fn write_byte(self: Self, value: u8) !usize {
            const data = [1]u8{ value };
            return try self.writer.write(data[0..]);
        }

        pub fn write_short(self: Self, value: i16, endian: std.builtin.Endian) !usize {
            const data = std.mem.toBytes(std.mem.nativeTo(i16, value, endian));
            return try self.writer.write(data[0..]);
        }

        pub fn write_ushort(self: Self, value: u16, endian: std.builtin.Endian) !usize {
            const data = std.mem.toBytes(std.mem.nativeTo(u16, value, endian));
            return try self.writer.write(data[0..]);
        }

        pub fn write_triad(self: Self, value: i32, endian: std.builtin.Endian) !usize {
            const data = std.mem.toBytes(std.mem.nativeTo(i32, value, endian));
            const data_triad = switch (endian) {
                .little => data[0..3],
                .big => data[1..]
            };
            return try self.writer.write(data_triad[0..]);
        }

        pub fn write_utriad(self: Self, value: u32, endian: std.builtin.Endian) !usize {
            const data = std.mem.toBytes(std.mem.nativeTo(u32, value, endian));
            const data_triad = switch (endian) {
                .little => data[0..3],
                .big => data[1..]
            };
            return try self.writer.write(data_triad[0..]);
        }

        pub fn write_int(self: Self, value: i32, endian: std.builtin.Endian) !usize {
            const data = std.mem.toBytes(std.mem.nativeTo(i32, value, endian));
            return try self.writer.write(data[0..]);
        }

        pub fn write_uint(self: Self, value: u32, endian: std.builtin.Endian) !usize {
            const data = std.mem.toBytes(std.mem.nativeTo(u32, value, endian));
            return try self.writer.write(data[0..]);
        }

        pub fn write_long(self: Self, value: i64, endian: std.builtin.Endian) !usize {
            const data = std.mem.toBytes(std.mem.nativeTo(i64, value, endian));
            return try self.writer.write(data[0..]);
        }

        pub fn write_ulong(self: Self, value: u64, endian: std.builtin.Endian) !usize {
            const data = std.mem.toBytes(std.mem.nativeTo(u64, value, endian));
            return try self.writer.write(data[0..]);
        }

        pub fn write_float(self: Self, value: f32, endian: std.builtin.Endian) !usize {
            // cast to u32 since nativeTo cannot bitSwap floats
            const data = std.mem.toBytes(std.mem.nativeTo(u32, @bitCast(value), endian));
            return try self.writer.write(data[0..]);
        }

        pub fn write_double(self: Self, value: f64, endian: std.builtin.Endian) !usize {
            // cast to u64 since nativeTo cannot bitSwap floats
            const data = std.mem.toBytes(std.mem.nativeTo(u64, @bitCast(value), endian));
            return try self.writer.write(data[0..]);
        }

        pub fn flush(self: Self) !void {
            try self.writer.flush();
        }
    };
}

pub fn binaryStreamWriter(comptime buffer_size: usize, writer: anytype) BinaryStreamWriter(buffer_size, @TypeOf(writer)) {
    const bufferedWriter: std.io.BufferedWriter(buffer_size, @TypeOf(writer)) = .{
        .unbuffered_writer = writer
    };
    return .{ .writer = bufferedWriter };
}

test "basic write" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    var stream = binaryStreamWriter(0, list.writer());

    // byte
    const byte_buffer = [3]u8{ 1, 2, 3 };
    _ = try stream.write(byte_buffer[0..]);
    _ = try stream.write_byte(4);

    // boolean
    _ = try stream.write_bool(true);
    _ = try stream.write_bool(false);

    // short
    _ = try stream.write_short(-500, .little);
    _ = try stream.write_short(-500, .big);
    _ = try stream.write_ushort(30000, .little);
    _ = try stream.write_ushort(30000, .big);

    // triad
    _ = try stream.write_triad(-16000, .little);
    _ = try stream.write_triad(-16000, .big);
    _ = try stream.write_utriad(36000, .little);
    _ = try stream.write_utriad(36000, .big);

    // int
    _ = try stream.write_int(-100000, .little);
    _ = try stream.write_int(-100000, .big);
    _ = try stream.write_uint(100000, .little);
    _ = try stream.write_uint(100000, .big);

    // long
    _ = try stream.write_long(-12314352341234234, .little);
    _ = try stream.write_long(-12314352341234234, .big);
    _ = try stream.write_ulong(12314352341234234, .little);
    _ = try stream.write_ulong(12314352341234234, .big);

    // float
    _ = try stream.write_float(123.4345, .little);
    _ = try stream.write_float(123.4345, .big);

    // double
    _ = try stream.write_double(123.4345123123, .little);
    _ = try stream.write_double(123.4345123123, .big);

    // don't forget to flush!
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

    try std.testing.expect(std.mem.eql(u8, list.items, &expected_buffer));
}
