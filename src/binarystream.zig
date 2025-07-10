const std = @import("std");
const writer = @import("writer.zig");
const reader = @import("reader.zig");

pub const BinaryStreamWriter = writer.BinaryStreamWriter;
pub const BinaryStreamReader = reader.BinaryStreamReader;

test {
    std.testing.refAllDecls(@This());
}
