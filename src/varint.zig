const std = @import("std");

pub fn check(comptime T: type, comptime signedness: std.builtin.Signedness) void {
    const info = @typeInfo(T);
    if (info != .int or info.int.signedness != signedness or info.int.bits < 8 or info.int.bits > 64)
        @compileError("expected an " ++ @tagName(signedness) ++ " integer of 8 to 64 bits, got " ++ @typeName(T));
}

pub fn checkFixed(comptime T: type, comptime bytes: usize) void {
    const info = @typeInfo(T);
    if (info != .int or info.int.bits != bytes * 8)
        @compileError(std.fmt.comptimePrint("expected a {d}-bit integer, got {s}", .{ bytes * 8, @typeName(T) }));
}

pub fn maxLen(comptime T: type) usize {
    return (@typeInfo(T).int.bits + 6) / 7;
}

pub fn Unsigned(comptime T: type) type {
    return @Int(.unsigned, @typeInfo(T).int.bits);
}

pub fn zigzag(comptime T: type, value: T) Unsigned(T) {
    const bits = @typeInfo(T).int.bits;
    const u: Unsigned(T) = @bitCast(value);
    const sign: Unsigned(T) = @bitCast(value >> (bits - 1));
    return (u << 1) ^ sign;
}

pub fn unzigzag(comptime T: type, value: Unsigned(T)) T {
    return @bitCast((value >> 1) ^ (0 -% (value & 1)));
}

test "zigzag" {
    const cases = [_]struct { i64, u64 }{
        .{ 0, 0 },  .{ -1, 1 },                                          .{ 1, 2 },
        .{ -2, 3 }, .{ std.math.maxInt(i64), std.math.maxInt(u64) - 1 }, .{ std.math.minInt(i64), std.math.maxInt(u64) },
    };
    for (cases) |c| {
        try std.testing.expectEqual(c[1], zigzag(i64, c[0]));
        try std.testing.expectEqual(c[0], unzigzag(i64, c[1]));
    }
    try std.testing.expectEqual(255, zigzag(i8, -128));
    try std.testing.expectEqual(-128, unzigzag(i8, 255));
}
