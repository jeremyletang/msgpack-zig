const std = @import("std");
const format = @import("format.zig");
const value = @import("value.zig");
const expect = std.testing.expect;
const Format = format.Format;

pub const DecodeError = error{
    EmptyInput,
    TruncatedInput,
    ReservedFormat,
    ReservedFormatInInput,
    InvalidMapKeyType,
    InvalidType,
    InvalidNumberSize,
    NilFormatWithNonOptionalType,
} || error{OutOfMemory};

pub const Decoder = struct {
    allocator: *std.mem.Allocator,
    strictNumberSize: bool = true,
    allowUnknownStructFields: bool = false,

    pub fn decode(self: *Decoder, comptime T: type, buf: []const u8) DecodeError!T {
        if (buf.len == 0) {
            return error.EmptyInput;
        }

        const fmt = format.from_u8(buf[0]);
        return switch (@typeInfo(T)) {
            .Null => switch (fmt) {
                Format.nil => null,
                else => error.InvalidType,
            },
            .Bool => switch (fmt) {
                Format.bool_true => true,
                Format.bool_false => false,
                else => error.InvalidType,
            },
            .Int => |intInfo| switch (intInfo.is_signed) {
                true => readIntAny(T, buf, self.strictNumberSize),
                false => readUintAny(T, buf, self.strictNumberSize),
            },
            .Float => readFloatAny(T, buf, self.strictNumberSize),
            .Optional => |optionalInfo| switch (fmt) {
                Format.nil => null,
                else => try self.decode(optionalInfo.child, buf),
            },
            .Array => |arrayInfo| switch (arrayInfo.child) {
                u8 => readStrOrBinAny(self.allocator, buf),
                else => self.decodeArrayAny(arrayInfo.child, buf),
            },
            .Pointer => |pointerInfo| switch (pointerInfo.size) {
                .One => switch (pointerInfo.child) {
                    u8 => readStrOrBinAny(self.allocator, buf),
                    else => self.decode(pointerInfo.child, buf),
                },
                .Slice => switch (pointerInfo.child) {
                    u8 => readStrOrBinAny(self.allocator, buf),
                    else => self.decode(pointerInfo.child, buf),
                },
                else => error.UnsupportedType,
            },

            else => switch (fmt) {
                Format.nil => error.NilFormatWithNonOptionalType,
                Format.never_used => error.ReservedFormatInInput,
                else => unreachable,
            },
        };
    }

    fn decodeArrayAny(comptime T: type, buf: []const u8) DecodeError!T {
        unreachable;
    }
};

pub fn decode(comptime T: type, allocator: *std.mem.Allocator, buf: []const u8) DecodeError!T {
    var decoder = Decoder{
        .allocator = allocator,
    };

    return decoder.decode(T, buf);
}

fn readStrOrBinAny(
    allocator: *std.mem.Allocator,
    buf: []const u8,
) DecodeError![]u8 {
    var str = try readStrOrBinAnyConst(allocator, buf);
    var out = try allocator.alloc(u8, str.len);
    std.mem.copy(u8, out, str);
    return out;
}

fn readStrOrBinAnyConst(
    allocator: *std.mem.Allocator,
    buf: []const u8,
) DecodeError![]const u8 {
    return switch (format.from_u8(buf[0])) {
        Format.fix_str => |len| readFixStr(buf[1..], len),
        Format.str8 => readStr8(buf[1..]),
        Format.str16 => readStr16(buf[1..]),
        Format.str32 => readStr32(buf[1..]),
        Format.bin8 => readBin8(buf[1..]),
        Format.bin16 => readBin16(buf[1..]),
        Format.bin32 => readBin32(buf[1..]),
        else => error.InvalidType,
    };
}

fn readFloatAny(comptime T: type, buf: []const u8, strictSize: bool) DecodeError!T {
    const bits = @typeInfo(T).Float.bits;
    const fmt = format.from_u8(buf[0]);
    var fbuf = buf[1..];

    // first check if we are actually decoding a float
    switch (fmt) {
        Format.float32 => {},
        Format.float64 => {},
        else => return error.InvalidType,
    }

    return switch (bits) {
        32 => switch (fmt) {
            Format.float32 => readFloat32(T, fbuf),
            else => error.InvalidNumberSize,
        },
        64 => switch (strictSize) {
            true => switch (fmt) {
                Format.float64 => readFloat64(T, fbuf),
                else => error.InvalidNumberSize,
            },
            false => switch (fmt) {
                Format.float32 => readFloat32(T, fbuf),
                Format.float64 => readFloat64(T, fbuf),
                else => error.InvalidNumberSize,
            },
        },
        else => error.InvalidType,
    };
}

fn readIntAny(comptime T: type, buf: []const u8, strictSize: bool) DecodeError!T {
    const bits = @typeInfo(T).Int.bits;
    const fmt = format.from_u8(buf[0]);
    var intbuf = buf[1..];

    // first check if we are actually decoding a int
    switch (fmt) {
        Format.negative_fix_int => {},
        Format.int8 => {},
        Format.int16 => {},
        Format.int32 => {},
        Format.int64 => {},
        else => return error.InvalidType,
    }

    return switch (bits) {
        8 => switch (fmt) {
            Format.negative_fix_int => |val| val,
            Format.int8 => readInt8(T, intbuf),
            else => error.InvalidNumberSize,
        },
        16 => switch (strictSize) {
            true => switch (fmt) {
                Format.int16 => readInt16(T, intbuf),
                else => error.InvalidNumberSize,
            },
            false => switch (fmt) {
                Format.negative_fix_int => |val| @intCast(i16, val),
                Format.int8 => readInt8(T, intbuf),
                Format.int16 => readInt16(T, intbuf),
                else => error.InvalidNumberSize,
            },
        },
        32 => switch (strictSize) {
            true => switch (fmt) {
                Format.int32 => readInt32(T, intbuf),
                else => error.InvalidNumberSize,
            },
            false => switch (fmt) {
                Format.negative_fix_int => |val| @intCast(i32, val),
                Format.int8 => readInt8(T, intbuf),
                Format.int16 => readInt16(T, intbuf),
                Format.int32 => readInt32(T, intbuf),
                else => error.InvalidNumberSize,
            },
        },
        64 => switch (strictSize) {
            true => switch (fmt) {
                Format.int64 => readInt64(T, intbuf),
                else => error.InvalidNumberSize,
            },
            false => switch (fmt) {
                Format.negative_fix_int => |val| @intCast(i64, val),
                Format.int8 => readInt8(T, intbuf),
                Format.int16 => readInt16(T, intbuf),
                Format.int32 => readInt32(T, intbuf),
                Format.int64 => readInt64(T, intbuf),
                else => error.InvalidNumberSize,
            },
        },
        else => error.InvalidType,
    };
}

fn readUintAny(comptime T: type, buf: []const u8, strictSize: bool) DecodeError!T {
    const bits = @typeInfo(T).Int.bits;
    const fmt = format.from_u8(buf[0]);
    var intbuf = buf[1..];

    // first check if we are actually decoding a uint
    switch (fmt) {
        Format.positive_fix_int => {},
        Format.uint8 => {},
        Format.uint16 => {},
        Format.uint32 => {},
        Format.uint64 => {},
        else => return error.InvalidType,
    }

    return switch (bits) {
        8 => switch (fmt) {
            Format.positive_fix_int => |val| val,
            Format.uint8 => readUint8(T, intbuf),
            else => error.InvalidNumberSize,
        },
        16 => switch (strictSize) {
            true => switch (fmt) {
                Format.uint16 => readUint16(T, intbuf),
                else => error.InvalidNumberSize,
            },
            false => switch (fmt) {
                Format.positive_fix_int => |val| @intCast(u16, val),
                Format.uint8 => readUint8(T, intbuf),
                Format.uint16 => readUint16(T, intbuf),
                else => error.InvalidNumberSize,
            },
        },
        32 => switch (strictSize) {
            true => switch (fmt) {
                Format.uint32 => readInt32(T, intbuf),
                else => error.InvalidNumberSize,
            },
            false => switch (fmt) {
                Format.positive_fix_int => |val| @intCast(u32, val),
                Format.uint8 => readUint8(T, intbuf),
                Format.uint16 => readUint16(T, intbuf),
                Format.uint32 => readUint32(T, intbuf),
                else => error.InvalidNumberSize,
            },
        },
        64 => switch (strictSize) {
            true => switch (fmt) {
                Format.uint64 => readUint64(T, intbuf),
                else => error.InvalidNumberSize,
            },
            false => switch (fmt) {
                Format.positive_fix_int => |val| @intCast(u64, val),
                Format.uint8 => readUint8(T, intbuf),
                Format.uint16 => readUint16(T, intbuf),
                Format.uint32 => readUint32(T, intbuf),
                Format.uint64 => readUint64(T, intbuf),
                else => error.InvalidNumberSize,
            },
        },
        else => error.InvalidType,
    };
}

pub fn readBin8(buf: []const u8) DecodeError![]const u8 {
    var n = try readUint8(u8, buf);
    var sbuf = buf[1..];
    if (sbuf.len < n) {
        return error.TruncatedInput;
    }
    return sbuf[0..n];
}

pub fn readBin16(buf: []const u8) DecodeError![]const u8 {
    var n = try readUint16(u16, buf);
    var sbuf = buf[2..];
    if (sbuf.len < n) {
        return error.TruncatedInput;
    }
    return sbuf[0..n];
}

pub fn readBin32(buf: []const u8) DecodeError![]const u8 {
    var n = try readUint32(u32, buf);
    var sbuf = buf[4..];
    if (sbuf.len < n) {
        return error.TruncatedInput;
    }
    return sbuf[0..n];
}

pub fn readFixStr(buf: []const u8, len: u8) DecodeError![]const u8 {
    if (buf.len < len) {
        return error.TruncatedInput;
    }
    return buf[0..len];
}

pub fn readStr8(buf: []const u8) DecodeError![]const u8 {
    var n = try readUint8(u8, buf);
    var sbuf = buf[1..];
    if (sbuf.len < n) {
        return error.TruncatedInput;
    }
    return sbuf[0..n];
}

pub fn readStr16(buf: []const u8) DecodeError![]const u8 {
    var n = try readUint16(u16, buf);
    var sbuf = buf[2..];
    if (sbuf.len < n) {
        return error.TruncatedInput;
    }
    return sbuf[0..n];
}

pub fn readStr32(buf: []const u8) DecodeError![]const u8 {
    var n = try readUint32(u32, buf);
    var sbuf = buf[4..];
    if (sbuf.len < n) {
        return error.TruncatedInput;
    }
    return sbuf[0..n];
}

pub fn readUint8(comptime U: type, buf: []const u8) DecodeError!U {
    if (buf.len < @sizeOf(u8)) {
        return error.TruncatedInput;
    }
    return std.mem.readIntBig(u8, buf[0..@sizeOf(u8)]);
}

pub fn readUint16(comptime U: type, buf: []const u8) DecodeError!U {
    if (buf.len < @sizeOf(u16)) {
        return error.TruncatedInput;
    }
    return std.mem.readIntBig(u16, buf[0..@sizeOf(u16)]);
}

pub fn readUint32(comptime U: type, buf: []const u8) DecodeError!U {
    if (buf.len < @sizeOf(u32)) {
        return error.TruncatedInput;
    }
    return std.mem.readIntBig(u32, buf[0..@sizeOf(u32)]);
}

pub fn readUint64(comptime U: type, buf: []const u8) DecodeError!U {
    if (buf.len < @sizeOf(u64)) {
        return error.TruncatedInput;
    }
    return std.mem.readIntBig(u64, buf[0..@sizeOf(u64)]);
}

pub fn readInt8(comptime I: type, buf: []const u8) DecodeError!I {
    if (buf.len < @sizeOf(i8)) {
        return error.TruncatedInput;
    }
    return std.mem.readIntBig(i8, buf[0..@sizeOf(i8)]);
}

pub fn readInt16(comptime I: type, buf: []const u8) DecodeError!I {
    if (buf.len < @sizeOf(i16)) {
        return error.TruncatedInput;
    }
    return std.mem.readIntBig(i16, buf[0..@sizeOf(i16)]);
}

pub fn readInt32(comptime I: type, buf: []const u8) DecodeError!I {
    if (buf.len < @sizeOf(i32)) {
        return error.TruncatedInput;
    }
    return std.mem.readIntBig(i32, buf[0..@sizeOf(i32)]);
}

pub fn readInt64(comptime I: type, buf: []const u8) DecodeError!I {
    if (buf.len < @sizeOf(i64)) {
        return error.TruncatedInput;
    }
    return std.mem.readIntBig(i64, buf[0..@sizeOf(i64)]);
}

pub fn readFloat32(comptime F: type, buf: []const u8) DecodeError!F {
    if (buf.len < @sizeOf(f32)) {
        return error.TruncatedInput;
    }
    return @bitCast(f32, std.mem.readIntBig(u32, buf[0..@sizeOf(f32)]));
}

pub fn readFloat64(comptime F: type, buf: []const u8) DecodeError!F {
    if (buf.len < @sizeOf(f64)) {
        return error.TruncatedInput;
    }
    return @bitCast(f64, std.mem.readIntBig(u64, buf[0..@sizeOf(f64)]));
}

test "empty input" {
    var data: [0]u8 = undefined;

    if (decode(i32, std.testing.allocator, data[0..])) {
        @panic("unexpected OK with empty input");
    } else |err| switch (err) {
        error.EmptyInput => {},
        else => @panic("invalid error received, expected empty input"),
    }
}

test "decode nil" {
    const hex = "c0";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decode(?bool, std.testing.allocator, data[0..]);
    expect(v == null);
}

test "decode bool false" {
    const hex = "c2";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decode(?bool, std.testing.allocator, data[0..]);
    expect(v == false);

    // null
    var hex2 = "c0";
    var data2: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data2[0..], hex2);
    v = try decode(?bool, std.testing.allocator, data2[0..]);
    expect(v == null);
}

test "decode bool true" {
    const hex = "c3";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decode(?bool, std.testing.allocator, data[0..]);
    expect(v == true);
}

test "decode int8" {
    const hex = "d085"; // -123
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    // decode strict first
    var v = try decode(i8, std.testing.allocator, data[0..]);
    expect(v == -123);

    // decode error now trying to use wrong type with strict setting
    if (decode(i32, std.testing.allocator, data[0..])) {
        @panic("unexpected OK with wrong type and strict");
    } else |err| switch (err) {
        error.InvalidNumberSize => {},
        else => @panic("invalid error received, expected truncated input"),
    }

    // decode non-strict
    var decoder = Decoder{
        .allocator = std.testing.allocator,
        .strictNumberSize = false,
    };

    var v2 = try decoder.decode(i64, data[0..]);
    expect(v2 == -123);
}

test "decode int16" {
    const hex = "d1fb30"; // -1232
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    // decode strict first
    var v = try decode(i16, std.testing.allocator, data[0..]);
    expect(v == -1232);

    // decode error now trying to use wrong type with strict setting
    if (decode(i32, std.testing.allocator, data[0..])) {
        @panic("unexpected OK with wrong type and strict");
    } else |err| switch (err) {
        error.InvalidNumberSize => {},
        else => @panic("invalid error received, expected truncated input"),
    }

    // decode non-strict
    var decoder = Decoder{
        .allocator = std.testing.allocator,
        .strictNumberSize = false,
    };

    var v2 = try decoder.decode(i64, data[0..]);
    expect(v2 == -1232);

    // decode non-strict but error for size too small
    // decode error now trying to use wrong type with strict setting
    if (decoder.decode(i8, data[0..])) {
        @panic("unexpected OK with wrong type and strict");
    } else |err| switch (err) {
        error.InvalidNumberSize => {},
        else => @panic("invalid error received, expected truncated input"),
    }
}

test "decode float32" {
    const hex = "ca40918c7d"; // 4.548399448394775
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    // decode strict first
    var v = try decode(f32, std.testing.allocator, data[0..]);
    expect(v == 4.548399448394775);

    // decode non-strict
    var decoder = Decoder{
        .allocator = std.testing.allocator,
        .strictNumberSize = false,
    };

    var v2 = try decoder.decode(f64, data[0..]);
    expect(v2 == 4.548399448394775);

    // decode non-strict but error for size too small
    // decode error now trying to use wrong type with strict setting
    if (decoder.decode(i8, data[0..])) {
        @panic("unexpected OK with wrong type and strict");
    } else |err| switch (err) {
        error.InvalidType => {},
        else => @panic("invalid error received, expected InvalidType"),
    }
}

test "decode const str8" {
    const hex = "d92368656c6c6f20776f726c642068656c6c6f20776f726c642068656c6c6f20776f726c64"; // "hello world hello world hello world"
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decode([]const u8, std.testing.allocator, data[0..]);
    defer std.testing.allocator.free(v);
    expect(std.mem.eql(u8, "hello world hello world hello world", v));
}

test "decode str8" {
    const hex = "d92368656c6c6f20776f726c642068656c6c6f20776f726c642068656c6c6f20776f726c64"; // "hello world hello world hello world"
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decode([]u8, std.testing.allocator, data[0..]);
    defer std.testing.allocator.free(v);
    expect(std.mem.eql(u8, "hello world hello world hello world", v));
}
