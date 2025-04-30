const std = @import("std");
const writer = @import("writer.zig");
const reader = @import("reader.zig");

pub const BinaryStreamWriter = writer.BinaryStreamWriter;
pub const binaryStreamWriter = writer.binaryStreamWriter;

pub const BinaryStreamReader = reader.BinaryStreamReader;
pub const binaryStreamReader = reader.binaryStreamReader;

test {
    std.testing.refAllDecls(@This());
}
