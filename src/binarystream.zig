const std = @import("std");
const writer = @import("writer.zig");
const reader = @import("reader.zig");

pub const BinaryStreamWriter = writer.BinaryStreamWriter;
pub const BinaryStreamReader = reader.BinaryStreamReader;
pub const WriteError = writer.Error;
pub const ReadError = reader.Error;

test {
    std.testing.refAllDecls(@This());
    _ = @import("varint.zig");
}
