const std = @import("std");
const format = @import("format.zig");
const value = @import("value.zig");
const expect = std.testing.expect;
const Format = format.Format;

const DecodeError = error{
    EmptyInput,
    TruncatedInput,
    ReservedFormat,
    AllocError,
    InvalidMapKeyType,
};

const ValueWithRest = struct {
    v: value.Value,
    rest: []const u8,
};

pub fn decodeValue(alloc: *std.mem.Allocator, buf: []const u8) DecodeError!value.Value {
    var val = try readValueWithRest(alloc, buf);
    return val.v;
}

fn readValueWithRest(alloc: *std.mem.Allocator, buf: []const u8) DecodeError!ValueWithRest {
    if (buf.len == 0) {
        return error.EmptyInput;
    }
    return switch (format.from_u8(buf[0])) {
        Format.positive_fix_int => |i| ValueWithRest{ .v = value.Value{ .uint = i }, .rest = buf[1..] },
        Format.fix_map => |len| readFixMapValue(alloc, buf[1..], len),
        Format.fix_array => |len| readFixArrayValue(alloc, buf[1..], len),
        Format.fix_str => |len| ValueWithRest{ .v = value.Value{ .string = try readFixStr(buf[1..], len) }, .rest = buf[1 + len ..] },
        Format.nil => ValueWithRest{ .v = .nil, .rest = buf[1..] },
        Format.never_used => error.ReservedFormat,
        Format.bool_false => ValueWithRest{ .v = value.Value{ .bool = false }, .rest = buf[1..] },
        Format.bool_true => ValueWithRest{ .v = value.Value{ .bool = true }, .rest = buf[1..] },
        Format.bin8 => {
            var v = value.Value{ .string = try readBin8(buf[1..]) };
            return ValueWithRest{ .v = v, .rest = buf[1 + 1 + v.binary.len ..] };
        },
        Format.bin16 => {
            var v = value.Value{ .string = try readBin16(buf[1..]) };
            return ValueWithRest{ .v = v, .rest = buf[1 + 2 + v.binary.len ..] };
        },
        Format.bin32 => {
            var v = value.Value{ .string = try readBin32(buf[1..]) };
            return ValueWithRest{ .v = v, .rest = buf[1 + 4 + v.binary.len ..] };
        },
        Format.float32 => ValueWithRest{ .v = value.Value{ .float = try readFloat32(f32, buf[1..]) }, .rest = buf[5..] },
        Format.float64 => ValueWithRest{ .v = value.Value{ .float = try readFloat64(f64, buf[1..]) }, .rest = buf[9..] },
        Format.uint8 => ValueWithRest{ .v = value.Value{ .uint = try readUint8(u8, buf[1..]) }, .rest = buf[1..] },
        Format.uint16 => ValueWithRest{ .v = value.Value{ .uint = try readUint16(u64, buf[1..]) }, .rest = buf[3..] },
        Format.uint32 => ValueWithRest{ .v = value.Value{ .uint = try readUint32(u32, buf[1..]) }, .rest = buf[5..] },
        Format.uint64 => ValueWithRest{ .v = value.Value{ .uint = try readUint64(u64, buf[1..]) }, .rest = buf[9..] },
        Format.int8 => ValueWithRest{ .v = value.Value{ .int = try readInt8(i8, buf[1..]) }, .rest = buf[1..] },
        Format.int16 => ValueWithRest{ .v = value.Value{ .int = try readInt16(i16, buf[1..]) }, .rest = buf[3..] },
        Format.int32 => ValueWithRest{ .v = value.Value{ .int = try readInt32(i32, buf[1..]) }, .rest = buf[5..] },
        Format.int64 => ValueWithRest{ .v = value.Value{ .int = try readInt64(i64, buf[1..]) }, .rest = buf[9..] },
        Format.str8 => {
            var v = value.Value{ .string = try readStr8(buf[1..]) };
            return ValueWithRest{ .v = v, .rest = buf[1 + 1 + v.string.len ..] };
        },
        Format.str16 => {
            var v = value.Value{ .string = try readStr16(buf[1..]) };
            return ValueWithRest{ .v = v, .rest = buf[1 + 2 + v.string.len ..] };
        },
        Format.str32 => {
            var v = value.Value{ .string = try readStr32(buf[1..]) };
            return ValueWithRest{ .v = v, .rest = buf[1 + 4 + v.string.len ..] };
        },
        Format.negative_fix_int => |i| ValueWithRest{ .v = value.Value{ .int = @intCast(i64, i) }, .rest = buf[1..] },
        else => unreachable,
    };
}

fn readFixMapValue(allocator: *std.mem.Allocator, buf: []const u8, len: u8) DecodeError!ValueWithRest {
    return readMapValue(allocator, buf, len);
}

fn readMapValue(allocator: *std.mem.Allocator, buf: []const u8, len: u8) DecodeError!ValueWithRest {
    var m = std.StringHashMap(value.Value).init(allocator);
    if (len == 0) {
        return ValueWithRest{ .v = value.Value{ .map = m }, .rest = buf };
    }

    var i: usize = 0;
    var rest = buf;
    while (i < len) {
        // first element is a string
        var key: []const u8 = undefined;
        switch (format.from_u8(rest[0])) {
            Format.fix_str => |slen| {
                key = try readFixStr(rest[1..], slen);
                rest = rest[1 + slen ..];
            },
            Format.str8 => {
                key = try readStr8(rest[1..]);
                rest = rest[1 + 1 + key.len ..];
            },
            Format.str16 => {
                key = try readStr16(rest[1..]);
                rest = rest[1 + 2 + key.len ..];
            },
            Format.str32 => {
                key = try readStr32(rest[1..]);
                rest = rest[1 + 4 + key.len ..];
            },
            else => return error.InvalidMapKeyType,
        }

        var val = try readValueWithRest(allocator, rest);
        rest = val.rest;
        m.put(key, val.v) catch |err| return error.AllocError;
        i += 1;
    }

    return ValueWithRest{ .v = value.Value{ .map = m }, .rest = rest };
}

fn readFixArrayValue(allocator: *std.mem.Allocator, buf: []const u8, len: u8) DecodeError!ValueWithRest {
    return readArrayValue(allocator, buf, len);
}

fn readArray16Value(allocator: *std.mem.Allocator, buf: []const u8) DecodeError!ValueWithRest {
    return readArrayValue(allocator, try readUint16(u16, buf), buf[2..]);
}

fn readArray32Value(allocator: *std.mem.Allocator, buf: []const u8) DecodeError!ValueWithRest {
    return readArrayValue(allocator, try readUint32(u32, buf), buf[2..]);
}

fn readArrayValue(allocator: *std.mem.Allocator, buf: []const u8, len: usize) DecodeError!ValueWithRest {
    if (len == 0) {
        return ValueWithRest{ .v = value.Value{ .array = ([_]value.Value{})[0..] }, .rest = buf };
    }

    var array = allocator.alloc(value.Value, len) catch |err| return error.AllocError;
    var i: usize = 0;
    var buff = buf;
    while (i < len) {
        var val = try readValueWithRest(allocator, buff);
        buff = val.rest;
        array[i] = val.v;
        i += 1;
    }

    return ValueWithRest{ .v = value.Value{ .array = array }, .rest = buff };
}

fn readBin8(buf: []const u8) DecodeError![]const u8 {
    var n = try readUint8(u8, buf);
    var sbuf = buf[1..];
    if (sbuf.len < n) {
        return error.TruncatedInput;
    }
    return sbuf[0..n];
}

fn readBin16(buf: []const u8) DecodeError![]const u8 {
    var n = try readUint16(u16, buf);
    var sbuf = buf[2..];
    if (sbuf.len < n) {
        return error.TruncatedInput;
    }
    return sbuf[0..n];
}

fn readBin32(buf: []const u8) DecodeError![]const u8 {
    var n = try readUint32(u32, buf);
    var sbuf = buf[4..];
    if (sbuf.len < n) {
        return error.TruncatedInput;
    }
    return sbuf[0..n];
}

fn readFixStr(buf: []const u8, len: u8) DecodeError![]const u8 {
    if (buf.len < len) {
        return error.TruncatedInput;
    }
    return buf[0..len];
}

fn readStr8(buf: []const u8) DecodeError![]const u8 {
    var n = try readUint8(u8, buf);
    var sbuf = buf[1..];
    if (sbuf.len < n) {
        return error.TruncatedInput;
    }
    return sbuf[0..n];
}

fn readStr16(buf: []const u8) DecodeError![]const u8 {
    var n = try readUint16(u16, buf);
    var sbuf = buf[2..];
    if (sbuf.len < n) {
        return error.TruncatedInput;
    }
    return sbuf[0..n];
}

fn readStr32(buf: []const u8) DecodeError![]const u8 {
    var n = try readUint32(u32, buf);
    var sbuf = buf[4..];
    if (sbuf.len < n) {
        return error.TruncatedInput;
    }
    return sbuf[0..n];
}

fn readUint8(comptime U: type, buf: []const u8) DecodeError!U {
    if (buf.len < @sizeOf(u8)) {
        return error.TruncatedInput;
    }
    return std.mem.readIntBig(u8, buf[0..@sizeOf(u8)]);
}

fn readUint16(comptime U: type, buf: []const u8) DecodeError!U {
    if (buf.len < @sizeOf(u16)) {
        return error.TruncatedInput;
    }
    return std.mem.readIntBig(u16, buf[0..@sizeOf(u16)]);
}

fn readUint32(comptime U: type, buf: []const u8) DecodeError!U {
    if (buf.len < @sizeOf(u32)) {
        return error.TruncatedInput;
    }
    return std.mem.readIntBig(u32, buf[0..@sizeOf(u32)]);
}

fn readUint64(comptime U: type, buf: []const u8) DecodeError!U {
    if (buf.len < @sizeOf(u64)) {
        return error.TruncatedInput;
    }
    return std.mem.readIntBig(u64, buf[0..@sizeOf(u64)]);
}

fn readInt8(comptime I: type, buf: []const u8) DecodeError!I {
    if (buf.len < @sizeOf(i8)) {
        return error.TruncatedInput;
    }
    return std.mem.readIntBig(i8, buf[0..@sizeOf(i8)]);
}

fn readInt16(comptime I: type, buf: []const u8) DecodeError!I {
    if (buf.len < @sizeOf(i16)) {
        return error.TruncatedInput;
    }
    return std.mem.readIntBig(i16, buf[0..@sizeOf(i16)]);
}

fn readInt32(comptime I: type, buf: []const u8) DecodeError!I {
    if (buf.len < @sizeOf(i32)) {
        return error.TruncatedInput;
    }
    return std.mem.readIntBig(i32, buf[0..@sizeOf(i32)]);
}

fn readInt64(comptime I: type, buf: []const u8) DecodeError!I {
    if (buf.len < @sizeOf(i64)) {
        return error.TruncatedInput;
    }
    return std.mem.readIntBig(i64, buf[0..@sizeOf(i64)]);
}

fn readFloat32(comptime F: type, buf: []const u8) DecodeError!F {
    if (buf.len < @sizeOf(f32)) {
        return error.TruncatedInput;
    }
    return @bitCast(f32, std.mem.readIntBig(u32, buf[0..@sizeOf(f32)]));
}

fn readFloat64(comptime F: type, buf: []const u8) DecodeError!F {
    if (buf.len < @sizeOf(f64)) {
        return error.TruncatedInput;
    }
    return @bitCast(f64, std.mem.readIntBig(u64, buf[0..@sizeOf(f64)]));
}

test "empty input" {
    var data: [0]u8 = undefined;

    if (decodeValue(std.testing.allocator, data[0..])) {
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
    var v = try decodeValue(std.testing.allocator, data[0..]);
    expect(v == .nil);
}

test "decode false" {
    const hex = "c2";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decodeValue(std.testing.allocator, data[0..]);
    expect(v.bool == false);
}

test "decode true" {
    const hex = "c3";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decodeValue(std.testing.allocator, data[0..]);
    expect(v.bool == true);
}

test "decode uint8" {
    const hex = "cc80"; // 128
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decodeValue(std.testing.allocator, data[0..]);
    expect(v.uint == 128);
}

test "decode uint8 truncated error" {
    const hex = "cc";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    if (decodeValue(std.testing.allocator, data[0..])) {
        @panic("unexpected OK with empty input");
    } else |err| switch (err) {
        error.TruncatedInput => {},
        else => @panic("invalid error received, expected truncated input"),
    }
}

test "decode uint16" {
    const hex = "cd0640"; // 1600
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decodeValue(std.testing.allocator, data[0..]);
    expect(v.uint == 1600);
}

test "decode uint16 truncated error" {
    const hex = "cd06";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    if (decodeValue(std.testing.allocator, data[0..])) {
        @panic("unexpected OK with empty input");
    } else |err| switch (err) {
        error.TruncatedInput => {},
        else => @panic("invalid error received, expected truncated input"),
    }
}

test "decode uint32" {
    const hex = "ce00bbdef8"; // 12312312
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decodeValue(std.testing.allocator, data[0..]);
    expect(v.uint == 12312312);
}

test "decode uint32 truncated error" {
    const hex = "ce00bbde";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    if (decodeValue(std.testing.allocator, data[0..])) {
        @panic("unexpected OK with empty input");
    } else |err| switch (err) {
        error.TruncatedInput => {},
        else => @panic("invalid error received, expected truncated input"),
    }
}

test "decode uint64" {
    const hex = "cf0000001caab5c3b3"; // 123123123123
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decodeValue(std.testing.allocator, data[0..]);
    expect(v.uint == 123123123123);
}

test "decode uint64 truncated error" {
    const hex = "cf0000001caab5c3";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    if (decodeValue(std.testing.allocator, data[0..])) {
        @panic("unexpected OK with empty input");
    } else |err| switch (err) {
        error.TruncatedInput => {},
        else => @panic("invalid error received, expected truncated input"),
    }
}

test "decode int8" {
    const hex = "d085"; // -123
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decodeValue(std.testing.allocator, data[0..]);
    expect(v.int == -123);
}

test "decode int8 truncated error" {
    const hex = "d0";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    if (decodeValue(std.testing.allocator, data[0..])) {
        @panic("unexpected OK with empty input");
    } else |err| switch (err) {
        error.TruncatedInput => {},
        else => @panic("invalid error received, expected truncated input"),
    }
}

test "decode int16" {
    const hex = "d1fb30"; // -1232
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decodeValue(std.testing.allocator, data[0..]);
    expect(v.int == -1232);
}

test "decode int16 truncated error" {
    const hex = "d1fb";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    if (decodeValue(std.testing.allocator, data[0..])) {
        @panic("unexpected OK with empty input");
    } else |err| switch (err) {
        error.TruncatedInput => {},
        else => @panic("invalid error received, expected truncated input"),
    }
}

test "decode int32" {
    const hex = "d2fffe1eb4"; // -123212
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decodeValue(std.testing.allocator, data[0..]);
    expect(v.int == -123212);
}

test "decode int32 truncated error" {
    const hex = "d2fffe1e";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    if (decodeValue(std.testing.allocator, data[0..])) {
        @panic("unexpected OK with empty input");
    } else |err| switch (err) {
        error.TruncatedInput => {},
        else => @panic("invalid error received, expected truncated input"),
    }
}

test "decode int64" {
    const hex = "d3fffffffd2198eb05"; // -12321232123
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decodeValue(std.testing.allocator, data[0..]);
    expect(v.int == -12321232123);
}

test "decode int64 truncated error" {
    const hex = "d3fffffffd2198eb";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    if (decodeValue(std.testing.allocator, data[0..])) {
        @panic("unexpected OK with empty input");
    } else |err| switch (err) {
        error.TruncatedInput => {},
        else => @panic("invalid error received, expected truncated input"),
    }
}

test "decode float 32" {
    const hex = "ca40918c7d"; // 4.548399448394775
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decodeValue(std.testing.allocator, data[0..]);
    expect(v.float == 4.548399448394775);
}

test "decode float 64" {
    const hex = "cb40918c7df3b645a2"; // 1123.123
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decodeValue(std.testing.allocator, data[0..]);
    expect(v.float == 1123.123);
}

test "decode positive fix int" {
    const hex = "0c"; // 12
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decodeValue(std.testing.allocator, data[0..]);
    expect(v.uint == 12);
}

test "decode negative fix int" {
    const hex = "e0"; // -32
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decodeValue(std.testing.allocator, data[0..]);
    expect(v.int == -32);
}

test "decode fix str" {
    const hex = "ab68656c6c6f20776f726c64"; // "hello world"
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decodeValue(std.testing.allocator, data[0..]);
    expect(std.mem.eql(u8, "hello world", v.string));
}

test "decode fix str truncated" {
    const hex = "ab68656c6c6f20776f"; // "hello world"
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    if (decodeValue(std.testing.allocator, data[0..])) {
        @panic("unexpected OK with empty input");
    } else |err| switch (err) {
        error.TruncatedInput => {},
        else => @panic("invalid error received, expected truncated input"),
    }
}

test "decode str8" {
    const hex = "d92368656c6c6f20776f726c642068656c6c6f20776f726c642068656c6c6f20776f726c64"; // "hello world hello world hello world"
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decodeValue(std.testing.allocator, data[0..]);
    expect(std.mem.eql(u8, "hello world hello world hello world", v.string));
}

test "decode empty array" {
    const hex = "90"; // "[]"
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decodeValue(std.testing.allocator, data[0..]);
    expect(v.array.len == 0);
}

test "decode array many types" {
    const hex = "942ac3a6737472696e67cb404535c28f5c28f6"; // "[42, true, "string", 42.42]"
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decodeValue(std.testing.allocator, data[0..]);
    expect(v.array.len == 4);
    expect(v.array[0].uint == 42);
    expect(v.array[1].bool == true);
    expect(std.mem.eql(u8, v.array[2].string, "string"));
    expect(v.array[3].float == 42.42);

    v.free(std.testing.allocator);
}

test "decode empty map" {
    const hex = "80"; // {}
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decodeValue(std.testing.allocator, data[0..]);
    expect(v.map.count() == 0);
    v.free(std.testing.allocator);
}

test "decode map many fields" {
    // {
    //   "s": "string",
    //   "u": 123456,
    //   "b": true,
    //   "f": -2332.32323,
    //   "i": -12343,
    //   "a": [1, "hello"],
    //   "m": {
    //     "s": "hello world"
    //   },
    //   "n": null
    // }
    const hex = "88a173a6737472696e67a175ce0001e240a162c3a166cbc0a238a57e670e2ca169d1cfc9a1619201a568656c6c6fa16d81a173ab68656c6c6f20776f726c64a16ec0";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try decodeValue(std.testing.allocator, data[0..]);
    expect(v.map.count() == 8);
    expect(std.mem.eql(u8, v.map.get("s").?.string, "string"));
    expect(v.map.get("u").?.uint == 123456);
    expect(v.map.get("b").?.bool == true);
    expect(v.map.get("f").?.float == -2332.32323);
    expect(v.map.get("i").?.int == -12343);
    expect(v.map.get("a").?.array[0].uint == 1);
    expect(std.mem.eql(u8, v.map.get("a").?.array[1].string, "hello"));
    expect(std.mem.eql(u8, v.map.get("m").?.map.get("s").?.string, "hello world"));
    expect(v.map.get("n").? == .nil);
    v.free(std.testing.allocator);
}

// test "decode str16" {
//     const hex = "da2368656c6c6f20776f726c642068656c6c6f20776f726c642068656c6c6f20776f726c64"; // "hello world hello world hello world"
//     var data: [hex.len / 2]u8 = undefined;
//     try std.fmt.hexToBytes(data[0..], hex);
//     var v = try read(data[0..]);
//     expect(std.mem.eql(u8, "hello world hello world hello world", v.string));
// }

// test "decode str32" {
//     const hex = "db2368656c6c6f20776f726c642068656c6c6f20776f726c642068656c6c6f20776f726c64"; // "hello world hello world hello world"
//     var data: [hex.len / 2]u8 = undefined;
//     try std.fmt.hexToBytes(data[0..], hex);
//     var v = try read(data[0..]);
//     expect(std.mem.eql(u8, "hello world hello world hello world", v.string));
// }
