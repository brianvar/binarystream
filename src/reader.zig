const std = @import("std");
const varint = @import("varint.zig");

pub const Error = std.Io.Reader.Error || error{
    InvalidBool,
    NonCanonical,
    Overflow,
    TooLong,
    /// A read longer than the underlying reader's buffer (for a fixed reader:
    /// longer than the whole input).
    BufferTooSmall,
    TrailingBytes,
};

/// Holds a pointer to the reader: `std.Io.Reader` implementations find their
/// state from the interface's address, so the interface must not be copied.
///
/// Slices returned by `readBytes`, `readArray` and `readLengthPrefixed` point
/// into the reader's buffer: for a fixed reader, into the input itself; for a
/// streaming reader, they are invalidated by the next read.
pub const BinaryStreamReader = struct {
    const Self = @This();

    reader: *std.Io.Reader,

    pub fn init(reader: *std.Io.Reader) Self {
        return .{ .reader = reader };
    }

    pub fn readByte(self: Self) Error!u8 {
        return self.reader.takeByte();
    }

    /// Fails with `error.BufferTooSmall` when `count` exceeds the reader's
    /// buffer (for a fixed reader: when it exceeds the whole input), and with
    /// `error.EndOfStream` when the input ends first.
    pub fn readBytes(self: Self, count: usize) Error![]const u8 {
        // `take` asserts the buffer can hold `count`; turn that into an error so
        // a length read from untrusted input can't crash the program.
        if (count > self.reader.buffer.len) return error.BufferTooSmall;
        return self.reader.take(count);
    }

    pub fn readArray(self: Self, comptime count: usize) Error!*const [count]u8 {
        return self.reader.takeArray(count);
    }

    pub fn readBool(self: Self) Error!bool {
        return switch (try self.readByte()) {
            0 => false,
            1 => true,
            else => error.InvalidBool,
        };
    }

    pub fn readShort(self: Self, comptime T: type, endian: std.builtin.Endian) Error!T {
        return self.readNumber(2, T, endian);
    }

    pub fn readTriad(self: Self, comptime T: type, endian: std.builtin.Endian) Error!T {
        return self.readNumber(3, T, endian);
    }

    pub fn readInt(self: Self, comptime T: type, endian: std.builtin.Endian) Error!T {
        return self.readNumber(4, T, endian);
    }

    pub fn readLong(self: Self, comptime T: type, endian: std.builtin.Endian) Error!T {
        return self.readNumber(8, T, endian);
    }

    /// Floats are read bit for bit; note that NaN has many encodings.
    pub fn readFloat(self: Self, endian: std.builtin.Endian) Error!f32 {
        return @bitCast(try self.readNumber(4, u32, endian));
    }

    pub fn readDouble(self: Self, endian: std.builtin.Endian) Error!f64 {
        return @bitCast(try self.readNumber(8, u64, endian));
    }

    /// `T` must be exactly `bytes` wide (e.g. `i24` for 3 bytes), so signed
    /// values are never silently zero-extended.
    pub fn readNumber(self: Self, comptime bytes: usize, comptime T: type, endian: std.builtin.Endian) Error!T {
        comptime varint.checkFixed(T, bytes);
        return std.mem.readInt(T, try self.readArray(bytes), endian);
    }

    pub fn readVarUint(self: Self, comptime T: type) Error!T {
        comptime varint.check(T, .unsigned);
        var acc: u128 = 0;
        for (0..varint.maxLen(T)) |i| {
            const byte = try self.readByte();
            const payload: u128 = byte & 0x7f;
            acc |= payload << @intCast(7 * i);
            if (byte & 0x80 == 0) {
                if (i > 0 and payload == 0) return error.NonCanonical;
                if (acc > std.math.maxInt(T)) return error.Overflow;
                return @intCast(acc);
            }
        }
        return error.Overflow;
    }

    /// Signed LEB128 with ZigZag mapping (0, -1, 1, -2, ... -> 0, 1, 2, 3, ...).
    pub fn readVarInt(self: Self, comptime T: type) Error!T {
        comptime varint.check(T, .signed);
        return varint.unzigzag(T, try self.readVarUint(varint.Unsigned(T)));
    }

    pub fn readLengthPrefixed(self: Self, max_len: usize) Error![]const u8 {
        const len = try self.readVarUint(u64);
        if (len > max_len) return error.TooLong;
        return self.readBytes(@intCast(len));
    }

    /// Succeeds only at the end of the input; use after decoding a whole
    /// message so trailing bytes can't ride along unnoticed.
    pub fn expectEnd(self: Self) Error!void {
        _ = self.reader.peekByte() catch |err| switch (err) {
            error.EndOfStream => return,
            else => |e| return e,
        };
        return error.TrailingBytes;
    }
};

const testing = std.testing;
const BinaryStreamWriter = @import("writer.zig").BinaryStreamWriter;

test "basic read" {
    const buffer =
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
    var input = buffer;

    var r: std.Io.Reader = .fixed(&input);
    const stream: BinaryStreamReader = .init(&r);

    try testing.expectEqualSlices(u8, buffer[0..3], try stream.readBytes(3));
    try testing.expectEqual(4, try stream.readByte());

    try testing.expectEqual(true, try stream.readBool());
    try testing.expectEqual(false, try stream.readBool());

    try testing.expectEqual(-500, try stream.readShort(i16, .little));
    try testing.expectEqual(-500, try stream.readShort(i16, .big));
    try testing.expectEqual(30000, try stream.readShort(u16, .little));
    try testing.expectEqual(30000, try stream.readShort(u16, .big));

    try testing.expectEqual(-16000, try stream.readTriad(i24, .little));
    try testing.expectEqual(-16000, try stream.readTriad(i24, .big));
    try testing.expectEqual(36000, try stream.readTriad(u24, .little));
    try testing.expectEqual(36000, try stream.readTriad(u24, .big));

    try testing.expectEqual(-100000, try stream.readInt(i32, .little));
    try testing.expectEqual(-100000, try stream.readInt(i32, .big));
    try testing.expectEqual(100000, try stream.readInt(u32, .little));
    try testing.expectEqual(100000, try stream.readInt(u32, .big));

    try testing.expectEqual(-12314352341234234, try stream.readLong(i64, .little));
    try testing.expectEqual(-12314352341234234, try stream.readLong(i64, .big));
    try testing.expectEqual(12314352341234234, try stream.readLong(u64, .little));
    try testing.expectEqual(12314352341234234, try stream.readLong(u64, .big));

    try testing.expectEqual(123.4345, try stream.readFloat(.little));
    try testing.expectEqual(123.4345, try stream.readFloat(.big));
    try testing.expectEqual(123.4345123123, try stream.readDouble(.little));
    try testing.expectEqual(123.4345123123, try stream.readDouble(.big));

    try stream.expectEnd();
    // Float reads must not byte-swap the input in place.
    try testing.expectEqualSlices(u8, &buffer, &input);
}

test "bool is strict" {
    var r: std.Io.Reader = .fixed(&.{2});
    try testing.expectError(error.InvalidBool, BinaryStreamReader.init(&r).readBool());
}

test "short input is an error, not a crash" {
    var r: std.Io.Reader = .fixed(&.{ 1, 2, 3 });
    const stream: BinaryStreamReader = .init(&r);
    try testing.expectError(error.EndOfStream, stream.readInt(u32, .little));
    try testing.expectError(error.BufferTooSmall, stream.readBytes(1000));

    var huge: std.Io.Reader = .fixed(&.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01 });
    try testing.expectError(error.BufferTooSmall, BinaryStreamReader.init(&huge).readLengthPrefixed(std.math.maxInt(usize)));

    var empty: std.Io.Reader = .fixed(&.{});
    try testing.expectError(error.EndOfStream, BinaryStreamReader.init(&empty).readByte());
    try BinaryStreamReader.init(&empty).expectEnd();
}

test "streaming reader with a small buffer rejects oversized reads" {
    const data = [_]u8{0x7f} ++ @as([127]u8, @splat(0xaa));
    var source: std.Io.Reader = .fixed(&data);
    var buf: [16]u8 = undefined;
    var limited = source.limited(.unlimited, &buf);
    const stream: BinaryStreamReader = .init(&limited.interface);
    try testing.expectError(error.BufferTooSmall, stream.readLengthPrefixed(1000));
}

test "streaming reader reads through the interface pointer" {
    const data = [_]u8{ 0xac, 0x02, 3, 'a', 'b', 'c', 1 };
    var source: std.Io.Reader = .fixed(&data);
    var buf: [4]u8 = undefined;
    var limited = source.limited(.unlimited, &buf);
    const stream: BinaryStreamReader = .init(&limited.interface);
    try testing.expectEqual(300, try stream.readVarUint(u16));
    try testing.expectEqualStrings("abc", try stream.readLengthPrefixed(4));
    try testing.expectEqual(true, try stream.readBool());
    try stream.expectEnd();
}

test "varuint vectors" {
    const Case = struct { bytes: []const u8, value: u64 };
    const cases = [_]Case{
        .{ .bytes = &.{0x00}, .value = 0 },
        .{ .bytes = &.{0x01}, .value = 1 },
        .{ .bytes = &.{0x7f}, .value = 127 },
        .{ .bytes = &.{ 0x80, 0x01 }, .value = 128 },
        .{ .bytes = &.{ 0xac, 0x02 }, .value = 300 },
        .{ .bytes = &.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01 }, .value = std.math.maxInt(u64) },
    };
    for (cases) |c| {
        var r: std.Io.Reader = .fixed(c.bytes);
        const stream: BinaryStreamReader = .init(&r);
        try testing.expectEqual(c.value, try stream.readVarUint(u64));
        try stream.expectEnd();
    }
}

test "varuint rejects non-canonical, overflowing and truncated input" {
    const Case = struct { bytes: []const u8, err: Error };
    const cases = [_]Case{
        .{ .bytes = &.{ 0x80, 0x00 }, .err = error.NonCanonical },
        .{ .bytes = &.{ 0x81, 0x80, 0x00 }, .err = error.NonCanonical },
        .{ .bytes = &.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x02 }, .err = error.Overflow },
        .{ .bytes = &.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x81, 0x00 }, .err = error.Overflow },
        .{ .bytes = &.{0x80}, .err = error.EndOfStream },
        .{ .bytes = &.{}, .err = error.EndOfStream },
    };
    for (cases) |c| {
        var r: std.Io.Reader = .fixed(c.bytes);
        try testing.expectError(c.err, BinaryStreamReader.init(&r).readVarUint(u64));
    }

    var r8: std.Io.Reader = .fixed(&.{ 0xac, 0x02 });
    try testing.expectError(error.Overflow, BinaryStreamReader.init(&r8).readVarUint(u8));
    var r8b: std.Io.Reader = .fixed(&.{ 0x80, 0x80, 0x01 });
    try testing.expectError(error.Overflow, BinaryStreamReader.init(&r8b).readVarUint(u8));
}

test "every varuint accepted has exactly one encoding" {
    var prng: std.Random.DefaultPrng = .init(0x5eed);
    const random = prng.random();
    var input: [12]u8 = undefined;
    var out: [16]u8 = undefined;
    var accepted: usize = 0;
    for (0..200_000) |_| {
        random.bytes(&input);
        const len = random.intRangeAtMost(usize, 1, input.len);
        if (random.boolean()) input[len - 1] &= 0x7f;
        if (random.boolean()) input[len - 1] = 0;
        var r: std.Io.Reader = .fixed(input[0..len]);
        const value = BinaryStreamReader.init(&r).readVarUint(u64) catch continue;
        accepted += 1;
        var w: std.Io.Writer = .fixed(&out);
        try BinaryStreamWriter.init(&w).writeVarUint(u64, value);
        try testing.expectEqualSlices(u8, input[0..r.seek], w.buffered());
    }
    try testing.expect(accepted > 1000);
}

test "length prefixed" {
    var r: std.Io.Reader = .fixed(&.{ 3, 'a', 'b', 'c', 5, 'x' });
    const stream: BinaryStreamReader = .init(&r);
    try testing.expectEqualStrings("abc", try stream.readLengthPrefixed(3));
    try testing.expectError(error.TooLong, stream.readLengthPrefixed(4));

    var r2: std.Io.Reader = .fixed(&.{ 5, 'x' });
    try testing.expectError(error.BufferTooSmall, BinaryStreamReader.init(&r2).readLengthPrefixed(10));
    var r3: std.Io.Reader = .fixed(&.{ 2, 'x', 'y', 'z', 9 });
    const s3: BinaryStreamReader = .init(&r3);
    _ = try s3.readLengthPrefixed(2);
    try testing.expectError(error.EndOfStream, s3.readBytes(3));
}

test "expectEnd" {
    var r: std.Io.Reader = .fixed(&.{ 1, 2 });
    const stream: BinaryStreamReader = .init(&r);
    _ = try stream.readByte();
    try testing.expectError(error.TrailingBytes, stream.expectEnd());
    _ = try stream.readByte();
    try stream.expectEnd();
}
