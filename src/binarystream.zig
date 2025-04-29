const std = @import("std");
const testing = std.testing;

pub fn BinaryStream(comptime buffer_size: usize, comptime WriterType: type) type {
    return struct {
        const Self = *@This();

        buffer: std.io.BufferedWriter(buffer_size, WriterType),

        pub fn write(self: Self, value: []const u8) !usize {
            return try self.buffer.write(value);
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

    const buf = [3]u8{ 1, 2, 3 };

    var stream = binaryStream(0, list.writer());
    _ = try stream.write(buf[0..]);
    try stream.buffer.flush();

    try std.testing.expect(std.mem.eql(u8, list.items, &buf));
}
