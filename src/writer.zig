const std = @import("std");
const varint = @import("varint.zig");

pub const Error = std.Io.Writer.Error;

/// Holds a pointer to the writer: `std.Io.Writer` implementations find their
/// state from the interface's address, so the interface must not be copied.
pub const BinaryStreamWriter = struct {
    const Self = @This();

    writer: *std.Io.Writer,

    pub fn init(writer: *std.Io.Writer) Self {
        return .{ .writer = writer };
    }

    pub fn write(self: Self, bytes: []const u8) Error!void {
        try self.writer.writeAll(bytes);
    }

    pub fn writeBool(self: Self, value: bool) Error!void {
        try self.writer.writeByte(@intFromBool(value));
    }

    pub fn writeByte(self: Self, value: u8) Error!void {
        try self.writer.writeByte(value);
    }

    pub fn writeShort(self: Self, value: i16, endian: std.builtin.Endian) Error!void {
        try self.writeNumber(i16, value, endian);
    }

    pub fn writeUnsignedShort(self: Self, value: u16, endian: std.builtin.Endian) Error!void {
        try self.writeNumber(u16, value, endian);
    }

    pub fn writeTriad(self: Self, value: i24, endian: std.builtin.Endian) Error!void {
        try self.writeNumber(i24, value, endian);
    }

    pub fn writeUnsignedTriad(self: Self, value: u24, endian: std.builtin.Endian) Error!void {
        try self.writeNumber(u24, value, endian);
    }

    pub fn writeInt(self: Self, value: i32, endian: std.builtin.Endian) Error!void {
        try self.writeNumber(i32, value, endian);
    }

    pub fn writeUnsignedInt(self: Self, value: u32, endian: std.builtin.Endian) Error!void {
        try self.writeNumber(u32, value, endian);
    }

    pub fn writeLong(self: Self, value: i64, endian: std.builtin.Endian) Error!void {
        try self.writeNumber(i64, value, endian);
    }

    pub fn writeUnsignedLong(self: Self, value: u64, endian: std.builtin.Endian) Error!void {
        try self.writeNumber(u64, value, endian);
    }

    pub fn writeFloat(self: Self, value: f32, endian: std.builtin.Endian) Error!void {
        try self.writeNumber(u32, @bitCast(value), endian);
    }

    pub fn writeDouble(self: Self, value: f64, endian: std.builtin.Endian) Error!void {
        try self.writeNumber(u64, @bitCast(value), endian);
    }

    pub fn writeNumber(self: Self, comptime T: type, value: T, endian: std.builtin.Endian) Error!void {
        const bytes = comptime @divExact(@typeInfo(T).int.bits, 8);
        comptime varint.checkFixed(T, bytes);
        var buf: [bytes]u8 = undefined;
        std.mem.writeInt(T, &buf, value, endian);
        try self.writer.writeAll(&buf);
    }

    /// Shortest form only; `readVarUint` rejects any other.
    pub fn writeVarUint(self: Self, comptime T: type, value: T) Error!void {
        comptime varint.check(T, .unsigned);
        var buf: [varint.maxLen(T)]u8 = undefined;
        var v: u64 = value;
        var i: usize = 0;
        while (v >= 0x80) : (i += 1) {
            buf[i] = @as(u8, @truncate(v)) | 0x80;
            v >>= 7;
        }
        buf[i] = @intCast(v);
        try self.writer.writeAll(buf[0 .. i + 1]);
    }

    /// Signed LEB128 with ZigZag mapping (0, -1, 1, -2, ... -> 0, 1, 2, 3, ...).
    pub fn writeVarInt(self: Self, comptime T: type, value: T) Error!void {
        comptime varint.check(T, .signed);
        try self.writeVarUint(varint.Unsigned(T), varint.zigzag(T, value));
    }

    pub fn writeLengthPrefixed(self: Self, bytes: []const u8) Error!void {
        try self.writeVarUint(u64, bytes.len);
        try self.writer.writeAll(bytes);
    }

    pub fn flush(self: Self) Error!void {
        try self.writer.flush();
    }
};

const testing = std.testing;
const BinaryStreamReader = @import("reader.zig").BinaryStreamReader;

test "basic write" {
    var out: [256]u8 = undefined;
    var w: std.Io.Writer = .fixed(&out);
    const stream: BinaryStreamWriter = .init(&w);

    try stream.write(&.{ 1, 2, 3 });
    try stream.writeByte(4);

    try stream.writeBool(true);
    try stream.writeBool(false);

    try stream.writeShort(-500, .little);
    try stream.writeShort(-500, .big);
    try stream.writeUnsignedShort(30000, .little);
    try stream.writeUnsignedShort(30000, .big);

    try stream.writeTriad(-16000, .little);
    try stream.writeTriad(-16000, .big);
    try stream.writeUnsignedTriad(36000, .little);
    try stream.writeUnsignedTriad(36000, .big);

    try stream.writeInt(-100000, .little);
    try stream.writeInt(-100000, .big);
    try stream.writeUnsignedInt(100000, .little);
    try stream.writeUnsignedInt(100000, .big);

    try stream.writeLong(-12314352341234234, .little);
    try stream.writeLong(-12314352341234234, .big);
    try stream.writeUnsignedLong(12314352341234234, .little);
    try stream.writeUnsignedLong(12314352341234234, .big);

    try stream.writeFloat(123.4345, .little);
    try stream.writeFloat(123.4345, .big);
    try stream.writeDouble(123.4345123123, .little);
    try stream.writeDouble(123.4345123123, .big);

    try stream.flush();

    const expected =
        [_]u8{ 1, 2, 3, 4 } ++
        [_]u8{ 1, 0 } ++
        [_]u8{ 12, 254 } ++
        [_]u8{ 254, 12 } ++
        [_]u8{ 48, 117 } ++
        [_]u8{ 117, 48 } ++
        [_]u8{ 128, 193, 255 } ++
        [_]u8{ 255, 193, 128 } ++
        [_]u8{ 160, 140, 0 } ++
        [_]u8{ 0, 140, 160 } ++
        [_]u8{ 96, 121, 254, 255 } ++
        [_]u8{ 255, 254, 121, 96 } ++
        [_]u8{ 160, 134, 1, 0 } ++
        [_]u8{ 0, 1, 134, 160 } ++
        [_]u8{ 198, 205, 15, 107, 41, 64, 212, 255 } ++
        [_]u8{ 255, 212, 64, 41, 107, 15, 205, 198 } ++
        [_]u8{ 58, 50, 240, 148, 214, 191, 43, 0 } ++
        [_]u8{ 0, 43, 191, 214, 148, 240, 50, 58 } ++
        [_]u8{ 119, 222, 246, 66 } ++
        [_]u8{ 66, 246, 222, 119 } ++
        [_]u8{ 108, 194, 186, 12, 207, 219, 94, 64 } ++
        [_]u8{ 64, 94, 219, 207, 12, 186, 194, 108 };
    try testing.expectEqualSlices(u8, &expected, w.buffered());
}

test "a full fixed writer fails instead of truncating" {
    var out: [3]u8 = undefined;
    var w: std.Io.Writer = .fixed(&out);
    const stream: BinaryStreamWriter = .init(&w);
    try testing.expectError(error.WriteFailed, stream.writeInt(1, .little));
}

test "allocating writer works through the interface pointer" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    const stream: BinaryStreamWriter = .init(&aw.writer);
    for (0..1000) |i| try stream.writeVarUint(u64, i * 1_000_003);
    try stream.writeLengthPrefixed("tail");

    var r: std.Io.Reader = .fixed(aw.written());
    const reader: BinaryStreamReader = .init(&r);
    for (0..1000) |i| try testing.expectEqual(i * 1_000_003, try reader.readVarUint(u64));
    try testing.expectEqualStrings("tail", try reader.readLengthPrefixed(16));
    try reader.expectEnd();
}

test "varint round trips" {
    var out: [16]u8 = undefined;
    const unsigned = [_]u64{ 0, 1, 127, 128, 255, 256, 16383, 16384, std.math.maxInt(u32), std.math.maxInt(u64) - 1, std.math.maxInt(u64) };
    for (unsigned) |value| {
        var w: std.Io.Writer = .fixed(&out);
        try BinaryStreamWriter.init(&w).writeVarUint(u64, value);
        var r: std.Io.Reader = .fixed(w.buffered());
        const reader: BinaryStreamReader = .init(&r);
        try testing.expectEqual(value, try reader.readVarUint(u64));
        try reader.expectEnd();
    }
    const signed = [_]i64{ 0, 1, -1, 63, -64, 64, -65, std.math.maxInt(i64), std.math.minInt(i64) };
    for (signed) |value| {
        var w: std.Io.Writer = .fixed(&out);
        try BinaryStreamWriter.init(&w).writeVarInt(i64, value);
        var r: std.Io.Reader = .fixed(w.buffered());
        const reader: BinaryStreamReader = .init(&r);
        try testing.expectEqual(value, try reader.readVarInt(i64));
        try reader.expectEnd();
    }
    var w: std.Io.Writer = .fixed(&out);
    try BinaryStreamWriter.init(&w).writeVarUint(u8, 255);
    try BinaryStreamWriter.init(&w).writeVarInt(i8, -128);
    try testing.expectEqualSlices(u8, &.{ 0xff, 0x01, 0xff, 0x01 }, w.buffered());
}
