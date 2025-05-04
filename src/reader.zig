const std = @import("std");
const native_endian = @import("builtin").target.cpu.arch.endian();

pub fn BinaryStreamReader(comptime ReaderType: type) type {
    return struct {
        const Self = *const @This();

        reader: ReaderType,

        pub fn read_byte(self: Self) !u8 {
            return self.reader.readByte();
        }

        pub fn read_bytes(self: Self, buffer: []u8) !usize {
            return try self.reader.read(buffer);
        }

        pub fn read_bytes_alloc(self: Self, count: usize, allocator: std.mem.Allocator) ![]u8 {
            const buffer = try allocator.alloc(u8, count);
            errdefer allocator.free(buffer);
            _ = try self.reader.read(buffer);
            return buffer;
        }

        pub fn read_bool(self: Self) !bool {
            return try self.read_byte() != 0;
        }

        pub fn read_short(self: Self, comptime T: type, endian: std.builtin.Endian) !T {
            return self.read_number(2, T, endian);
        }

        pub fn read_triad(self: Self, comptime T: type, endian: std.builtin.Endian) !T {
            return self.read_number(3, T, endian);
        }

        pub fn read_int(self: Self, comptime T: type, endian: std.builtin.Endian) !T {
            return self.read_number(4, T, endian);
        }

        pub fn read_long(self: Self, comptime T: type, endian: std.builtin.Endian) !T {
            return self.read_number(8, T, endian);
        }

        pub fn read_float(self: Self, endian: std.builtin.Endian) !f32 {
            return self.read_floating_point_number(4, f32, endian);
        }

        pub fn read_double(self: Self, endian: std.builtin.Endian) !f64 {
            return self.read_floating_point_number(8, f64, endian);
        }

        pub fn read_number(self: Self, comptime bytes: usize, comptime T: type, endian: std.builtin.Endian) !T {
            var buffer = try self.try_get(bytes);
            const result = std.mem.bytesAsValue(
                T,
                @as([]align(closest_power_of_two(bytes)) u8, @alignCast(buffer[0..bytes]))
            ).*;
            return std.mem.nativeTo(T, result, endian);
        }

        pub fn read_floating_point_number(self: Self, comptime bytes: usize, comptime T: type, endian: std.builtin.Endian) !T {
            var buffer = try self.try_get(bytes);

            // we need this hacks since we can't @byteSwap floats and doubles
            switch(native_endian) {
                .little => {
                    if(endian == .big) {
                        swap_buffer(&buffer);
                    }
                },
                .big => {
                    if(endian == .little) {
                        swap_buffer(&buffer);
                    }
                }
            }

            return std.mem.bytesAsValue(T, @as([]align(closest_power_of_two(bytes)) u8, @alignCast(buffer[0..bytes]))).*;
        }

        fn try_get(self: Self, comptime size: usize) ![size]u8 {
            var buffer: [size]u8 = undefined;
            const n = try self.reader.read(&buffer);
            if(n < 2) {
                return error.NotEnoughBytes;
            }
            return buffer;
        }

        fn swap_buffer(buffer: []u8) void {
            for(0..buffer.len / 2) |i| {
                std.mem.swap(u8, &buffer[i], &buffer[buffer.len - 1 - i]);
            }
        }

        // https://graphics.stanford.edu/%7Eseander/bithacks.html#RoundUpPowerOf2
        fn closest_power_of_two(comptime number: usize) usize {
            var numberCopy = number;
            numberCopy -= 1;
            numberCopy |= numberCopy >> 1;
            numberCopy |= numberCopy >> 2;
            numberCopy |= numberCopy >> 4;
            numberCopy |= numberCopy >> 8;
            numberCopy |= numberCopy >> 16;
            numberCopy |= numberCopy >> 32;
            numberCopy += 1;
            return numberCopy;
        }
    };
}

pub fn binaryStreamReader(reader: anytype) BinaryStreamReader(@TypeOf(reader)) {
    return .{ .reader = reader };
}

test "basic read" {
    const buffer = [_]u8{
        1, 2, 3, 4, // byte
        5, 6, 7, 8, // byte alloc
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

    var list = std.ArrayList(u8).init(std.testing.allocator);
    try list.appendSlice(&buffer);
    defer list.deinit();

    var buffer_stream = std.io.fixedBufferStream(list.items);
    const reader = buffer_stream.reader();
    const stream = binaryStreamReader(reader);

    // byte
    var three_bytes: [3]u8 = undefined;
    try std.testing.expect(try stream.read_bytes(&three_bytes) == 3);
    try std.testing.expect(std.mem.eql(u8, &three_bytes, buffer[0..3]));
    try std.testing.expect(try stream.read_byte() == 4);

    // byte alloc
    const four_bytes_result: []u8 = try stream.read_bytes_alloc(4, std.testing.allocator);
    try std.testing.expect(std.mem.eql(u8, four_bytes_result, buffer[4..8]));
    std.testing.allocator.free(four_bytes_result);

    // bool
    try std.testing.expect(try stream.read_bool() == true);
    try std.testing.expect(try stream.read_bool() == false);

    // short
    try std.testing.expect(try stream.read_short(i16, .little) == -500);
    try std.testing.expect(try stream.read_short(i16, .big) == -500);
    try std.testing.expect(try stream.read_short(u16, .little) == 30000);
    try std.testing.expect(try stream.read_short(u16, .big) == 30000);

    // triad
    try std.testing.expect(try stream.read_triad(i24, .little) == -16000);
    try std.testing.expect(try stream.read_triad(i24, .big) == -16000);
    try std.testing.expect(try stream.read_triad(u24, .little) == 36000);
    try std.testing.expect(try stream.read_triad(u24, .big) == 36000);

    // int
    try std.testing.expect(try stream.read_int(i32, .little) == -100000);
    try std.testing.expect(try stream.read_int(i32, .big) == -100000);
    try std.testing.expect(try stream.read_int(u32, .little) == 100000);
    try std.testing.expect(try stream.read_int(u32, .big) == 100000);

    // long
    try std.testing.expect(try stream.read_long(i64, .little) == -12314352341234234);
    try std.testing.expect(try stream.read_long(i64, .big) == -12314352341234234);
    try std.testing.expect(try stream.read_long(u64, .little) == 12314352341234234);
    try std.testing.expect(try stream.read_long(u64, .big) == 12314352341234234);

    // float
    try std.testing.expect(try stream.read_float(.little) == 123.4345);
    try std.testing.expect(try stream.read_float(.big) == 123.4345);

    // double
    try std.testing.expect(try stream.read_double(.little) == 123.4345123123);
    try std.testing.expect(try stream.read_double(.big) == 123.4345123123);
}
