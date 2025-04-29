const std = @import("std");

pub fn BinaryStream(comptime buffer_size: usize, comptime WriterType: type) type {
    return struct {
        const Self = *@This();

        buffer: std.io.BufferedWriter(buffer_size, WriterType),

        pub fn write(self: Self, value: []const u8) !usize {
            return try self.buffer.write(value);
        }

        pub fn write_bool(self: Self, value: bool) !usize {
            const data = [1]u8{ @intFromBool(value) };
            return try self.buffer.write(data[0..]);
        }

        pub fn write_byte(self: Self, value: u8) !usize {
            const data = [1]u8{ value };
            return try self.buffer.write(data[0..]);
        }

        pub fn write_short(self: Self, value: i16, endian: std.builtin.Endian) !usize {
            const data = std.mem.toBytes(std.mem.nativeTo(i16, value, endian));
            return try self.buffer.write(data[0..]);
        }

        pub fn write_ushort(self: Self, value: u16, endian: std.builtin.Endian) !usize {
            const data = std.mem.toBytes(std.mem.nativeTo(u16, value, endian));
            return try self.buffer.write(data[0..]);
        }

        pub fn flush(self: Self) !void {
            try self.buffer.flush();
        }
    };
}

pub fn binaryStream(comptime buffer_size: usize, writer: anytype) BinaryStream(buffer_size, @TypeOf(writer)) {
    const bufferedWriter: std.io.BufferedWriter(buffer_size, @TypeOf(writer)) = .{
        .unbuffered_writer = writer
    };
    return .{ .buffer = bufferedWriter };
}

test "basic write" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    const byte_buffer = [3]u8{ 1, 2, 3 };

    var stream = binaryStream(0, list.writer());

    // bytes
    _ = try stream.write(byte_buffer[0..]);
    _ = try stream.write_byte(4);

    // booleans
    _ = try stream.write_bool(true);
    _ = try stream.write_bool(false);

    // short
    _ = try stream.write_short(-500, .little);
    _ = try stream.write_short(-500, .big);
    _ = try stream.write_ushort(30000, .little);
    _ = try stream.write_ushort(30000, .big);

    // don't forget to flush!
    try stream.flush();

    // https://www.eso.org/~ndelmott/ascii.html
    const expected_buffer = [_]u8{
        1, 2, 3, 4, // bytes
        1, 0, // booleans
        12, 254, // little-endian short (-500)
        254, 12, // big-endian short (-500)
        48, 117, // little-endian ushort (30000 == 0u)
        117, 48, // big-endian ushort (30000 == u0)
    };

    try std.testing.expect(std.mem.eql(u8, list.items, &expected_buffer));
}
