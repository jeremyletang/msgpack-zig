const std = @import("std");
const Format = @import("format.zig").Format;
const testing = std.testing;
const value = @import("value.zig");
const builtin = @import("builtin");

pub const fix_map_max = 15;
pub const map16_max = 65535;
pub const fix_array_max = 15;
pub const array16_max = 65535;
const fix_str_max = 31;
const str8_max = 255;
const str16_max = 65535;
pub const neg_int_fix_min = -32;
pub const pos_int_fix_max = 127;
pub const uint8_max = 255;
pub const uint16_max = 65535;
pub const uint32_max = 4294967295;
pub const uint64_max = 18446744073709551615;
pub const int8_max = 127;
pub const int16_max = 32767;
pub const int32_max = 2147483647;
pub const int64_max = 9223372036854775807;
pub const int8_min = -128;
pub const int16_min = -32768;
pub const int32_min = -int32_max - 1;
pub const int64_min = -int64_max - 1;

pub const EncodeError = error{
    UnsupportedType,
    OutOfMemory,
};

pub fn encode(allocator: *std.mem.Allocator, val: anytype) EncodeError![]u8 {
    std.debug.print("tinfo: {}\n", .{@typeInfo(@TypeOf(val))});
    const ti = @typeInfo(@TypeOf(val));
    return switch (ti) {
        .Null => encodeNil(allocator),
        .Bool => encodeBool(allocator, val),
        .ComptimeInt => encodeIntAny(allocator, val),
        .ComptimeFloat => encodeFloatAny(allocator, val),
        .Int => |intInfo| switch (intInfo.is_signed) {
            true => switch (intInfo.bits) {
                8 => encodeIntAny(allocator, val),
                16 => encodeInt16(allocator, val),
                32 => encodeInt32(allocator, val),
                64 => encodeInt64(allocator, val),
                else => error.UnsupportedType,
            },
            false => switch (intInfo.bits) {
                8 => encodeUintAny(allocator, val),
                16 => encodeUint16(allocator, val),
                32 => encodeUint32(allocator, val),
                64 => encodeUint64(allocator, val),
                else => error.UnsupportedType,
            },
        },
        .Float => |floatInfo| switch (floatInfo.bits) {
            32 => encodeFloat32(allocator, val),
            64 => encodeFloat64(allocator, val),
            else => error.UnsupportedType,
        },
        .Optional => {
            if (val) |tmpv| {
                return encode(allocator, tmpv);
            } else {
                return encodeNil(allocator);
            }
        },
        .Array => |arrayInfo| switch (arrayInfo.child) {
            u8 => encodeStrAny(allocator, val[0..]),
            else => encodeArrayAny(arrayInfo.child, allocator, val[0..]),
        },
        .Pointer => |pointerInfo| switch (pointerInfo.size) {
            .One => switch (pointerInfo.child) {
                u8 => encodeStrAny(allocator, val),
                else => encode(allocator, val.*),
            },
            .Slice => switch (pointerInfo.child) {
                u8 => encodeStrAny(allocator, val),
                else => encode(allocator, val),
            },
            else => error.UnsupportedType,
        },
        .Struct => encodeStruct(@TypeOf(val), allocator, val),
        else => error.UnsupportedType,
    };
}

fn encodeStruct(comptime T: type, allocator: *std.mem.Allocator, v: T) EncodeError![]u8 {
    const ti = @typeInfo(T);
    if (ti.Struct.fields.len <= fix_map_max) {
        return encodeFixMap(T, allocator, v);
    } else if (ti.Struct.fields.len <= fix_map16_max) {
        return encodeMap16(T, allocator, v);
    }
    return encodeMap32(T, allocator, v);
}

fn encodeFixMap(comptime T: type, allocator: *std.mem.Allocator, v: T) EncodeError![]u8 {
    const len = @typeInfo(T).Struct.fields.len;
    var entries = try encodeMapEntries(T, allocator, v);
    var out = try allocator.alloc(u8, 1 + entries.len);
    out[0] = (Format{ .fix_map = @intCast(u8, len) }).toUint8();
    std.mem.copy(u8, out[1..], entries);
    // now release the elems and joined elems
    allocator.free(entries);
    return out;
}

fn encodeMapEntries(comptime T: type, allocator: *std.mem.Allocator, v: T) EncodeError![]u8 {
    // allocate twice the size as we space for each keys
    // and values.
    const ti = @typeInfo(T);
    var entries = try allocator.alloc([]u8, ti.Struct.fields.len * 2);
    var i: usize = 0;
    inline for (ti.Struct.fields) |field| {
        // FIXME(): we have a memory leak here most likely
        // in the case we return an error the error is not
        // freed, but knowing that the only error which can happen
        // in encodeValue is an OutOfMemory error, it's quite
        // certain we would not recover anyway. Will take care of
        // this later
        var encodedkey = try encodeStrAny(allocator, field.name);
        entries[i] = encodedkey;
        var encodedvalue = try encode(allocator, @field(v, field.name));
        entries[i + 1] = encodedvalue;
        i += 2;
    }
    // FIXME(): see previous comment, same concerns.
    var out = try std.mem.join(allocator, &[_]u8{}, entries);
    // free the slice of encoded elements as they are not required anymore
    for (entries) |e| {
        allocator.free(e);
    }
    allocator.free(entries);

    return out;
}

fn encodeArrayAny(comptime T: type, allocator: *std.mem.Allocator, v: []const T) EncodeError![]u8 {
    if (v.len <= fix_array_max) {
        return encodeFixArray(T, allocator, v);
    } else if (v.len <= array16_max) {
        return encodeArray16(T, allocator, v);
    }
    return encodeArray32(T, allocator, v);
}

fn encodeFixArray(comptime T: type, allocator: *std.mem.Allocator, v: []const T) EncodeError![]u8 {
    var elems = try encodeArrayElements(T, allocator, v);
    var out = try allocator.alloc(u8, 1 + elems.len);
    out[0] = (Format{ .fix_array = @intCast(u8, v.len) }).toUint8();
    std.mem.copy(u8, out[1..], elems);
    // now release the elems and joined elems
    allocator.free(elems);
    return out;
}

fn encodeArray16(comptime T: type, allocator: *std.mem.Allocator, v: []const T) EncodeError![]u8 {
    var elems = try encodeArrayElements(T, allocator, v);
    var out = try allocator.alloc(u8, 1 + @sizeOf(u16) + elems.len);

    out[0] = Format.array16.toUint8();
    std.mem.writeIntBig(u16, out[1 .. 1 + @sizeOf(u16)], @intCast(u16, v.len));
    std.mem.copy(u8, out[1 + @sizeOf(u16) ..], elems);

    // now release the elems and joined elems
    allocator.free(elems);
    return out;
}
fn encodeArray32(comptime T: type, allocator: *std.mem.Allocator, v: []const T) EncodeError![]u8 {
    var elems = try encodeArrayElements(T, allocator, v);
    var out = try allocator.alloc(u8, 1 + @sizeOf(u32) + elems.len);

    out[0] = Format.array32.toUint8();
    std.mem.writeIntBig(u32, out[1 .. 1 + @sizeOf(u32)], @intCast(u32, v.len));
    std.mem.copy(u8, out[1 + @sizeOf(u32) ..], elems);

    // now release the elems and joined elems
    allocator.free(elems);
    return out;
}

fn encodeArrayElements(comptime T: type, allocator: *std.mem.Allocator, v: []const T) EncodeError![]u8 {
    var elems = try allocator.alloc([]u8, v.len);
    var i: usize = 0;
    while (i < v.len) {
        // FIXME(): we have a memory leak here most likely
        // in the case we return an error the error is not
        // freed, but knowing that the only error which can happen
        // in encodeValue is an OutOfMemory error, it's quite
        // certain we would not recover anyway. Will take care of
        // this later
        var encoded = try encode(allocator, v[i]);
        elems[i] = encoded;
        i += 1;
    }
    // FIXME(): see previous comment, same concerns.
    var out = try std.mem.join(allocator, &[_]u8{}, elems);
    // free the slice of encoded elements as they are not required anymore
    for (elems) |e| {
        allocator.free(e);
    }
    allocator.free(elems);

    return out;
}

pub fn encodeBinAny(allocator: *std.mem.Allocator, v: []const u8) EncodeError![]u8 {
    if (v.len <= str8_max) {
        return encodeBin8(allocator, v);
    } else if (v.len <= str16_max) {
        return encodeBin16(allocator, v);
    }
    return encodeBin32(allocator, v);
}

fn encodeBin8(allocator: *std.mem.Allocator, v: []const u8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 2 + v.len);
    out[0] = Format.bin8.toUint8();
    out[1] = @intCast(u8, v.len);
    std.mem.copy(u8, out[2 .. 2 + v.len], v);
    return out;
}

fn encodeBin16(allocator: *std.mem.Allocator, v: []const u8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(u16) + v.len);
    out[0] = Format.bin16.toUint8();
    std.mem.writeIntBig(u16, out[1 .. 1 + @sizeOf(u16)], @intCast(u16, v.len));
    std.mem.copy(u8, out[1 + @sizeOf(u16) .. 1 + @sizeOf(u16) + v.len], v);
    return out;
}

fn encodeBin32(allocator: *std.mem.Allocator, v: []const u8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(u32) + v.len);
    out[0] = Format.bin32.toUint8();
    std.mem.writeIntBig(u32, out[1 .. 1 + @sizeOf(u32)], @intCast(u32, v.len));
    std.mem.copy(u8, out[1 + @sizeOf(u32) .. 1 + @sizeOf(u32) + v.len], v);
    return out;
}

pub fn encodeStrAny(allocator: *std.mem.Allocator, v: []const u8) EncodeError![]u8 {
    if (v.len <= fix_str_max) {
        return encodeFixStr(allocator, v);
    } else if (v.len <= str8_max) {
        return encodeStr8(allocator, v);
    } else if (v.len <= str16_max) {
        return encodeStr16(allocator, v);
    }

    return encodeStr32(allocator, v);
}

fn encodeFixStr(allocator: *std.mem.Allocator, v: []const u8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + v.len);
    out[0] = (Format{ .fix_str = @intCast(u8, v.len) }).toUint8();
    std.mem.copy(u8, out[1 .. 1 + v.len], v);
    return out;
}

fn encodeStr8(allocator: *std.mem.Allocator, v: []const u8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 2 + v.len);
    out[0] = Format.str8.toUint8();
    out[1] = @intCast(u8, v.len);
    std.mem.copy(u8, out[2 .. 2 + v.len], v);
    return out;
}

fn encodeStr16(allocator: *std.mem.Allocator, v: []const u8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(u16) + v.len);
    out[0] = Format.str16.toUint8();
    std.mem.writeIntBig(u16, out[1 .. 1 + @sizeOf(u16)], @intCast(u16, v.len));
    std.mem.copy(u8, out[1 + @sizeOf(u16) .. 1 + @sizeOf(u16) + v.len], v);
    return out;
}

fn encodeStr32(allocator: *std.mem.Allocator, v: []const u8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(u32) + v.len);
    out[0] = Format.str32.toUint8();
    std.mem.writeIntBig(u32, out[1 .. 1 + @sizeOf(u32)], @intCast(u32, v.len));
    std.mem.copy(u8, out[1 + @sizeOf(u32) .. 1 + @sizeOf(u32) + v.len], v);
    return out;
}

pub fn encodeFloatAny(allocator: *std.mem.Allocator, v: f64) EncodeError![]u8 {
    if (v >= std.math.f32_min and v <= std.math.f32_max) {
        return encodeFloat32(allocator, @floatCast(f32, v));
    }
    return encodeFloat64(allocator, v);
}

fn encodeFloat32(allocator: *std.mem.Allocator, v: f32) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(f32));
    out[0] = Format.float32.toUint8();
    std.mem.writeIntBig(u32, out[1 .. 1 + @sizeOf(u32)], @bitCast(u32, v));
    return out;
}

fn encodeFloat64(allocator: *std.mem.Allocator, v: f64) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(f64));
    out[0] = Format.float64.toUint8();
    std.mem.writeIntBig(u64, out[1 .. 1 + @sizeOf(u64)], @bitCast(u64, v));
    return out;
}

pub fn encodeIntAny(allocator: *std.mem.Allocator, v: i64) EncodeError![]u8 {
    if (v >= neg_int_fix_min and v <= 0) {
        return encodeNegativeFixInt(allocator, @intCast(i8, v));
    } else if (v >= int8_min and v <= int8_max) {
        return encodeInt8(allocator, @intCast(i8, v));
    } else if (v >= int16_min and v <= int16_max) {
        return encodeInt16(allocator, @intCast(i16, v));
    } else if (v >= int32_min and v <= int32_max) {
        return encodeInt32(allocator, @intCast(i32, v));
    }
    return encodeInt64(allocator, v);
}

fn encodeNegativeFixInt(allocator: *std.mem.Allocator, v: i8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, @sizeOf(i8));
    std.mem.writeIntBig(i8, out[0..@sizeOf(i8)], v);
    return out;
}

fn encodeInt8(allocator: *std.mem.Allocator, v: i8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(i8));
    out[0] = Format.int8.toUint8();
    std.mem.writeIntBig(i8, out[1 .. 1 + @sizeOf(i8)], v);
    return out;
}

fn encodeInt16(allocator: *std.mem.Allocator, v: i16) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(i16));
    out[0] = Format.int16.toUint8();
    std.mem.writeIntBig(i16, out[1 .. 1 + @sizeOf(i16)], v);
    return out;
}

fn encodeInt32(allocator: *std.mem.Allocator, v: i32) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(i32));
    out[0] = Format.int32.toUint8();
    std.mem.writeIntBig(i32, out[1 .. 1 + @sizeOf(i32)], v);
    return out;
}

fn encodeInt64(allocator: *std.mem.Allocator, v: i64) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(i64));
    out[0] = Format.int64.toUint8();
    std.mem.writeIntBig(i64, out[1 .. 1 + @sizeOf(i64)], v);
    return out;
}

pub fn encodeUintAny(allocator: *std.mem.Allocator, v: u64) EncodeError![]u8 {
    if (v <= pos_int_fix_max) {
        return encodePositiveFixInt(allocator, @intCast(u8, v));
    } else if (v <= uint8_max) {
        return encodeUint8(allocator, @intCast(u8, v));
    } else if (v <= uint16_max) {
        return encodeUint16(allocator, @intCast(u16, v));
    } else if (v <= uint32_max) {
        return encodeUint32(allocator, @intCast(u32, v));
    }
    return encodeUint64(allocator, v);
}

fn encodePositiveFixInt(allocator: *std.mem.Allocator, v: u8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, @sizeOf(u8));
    std.mem.writeIntBig(u8, out[0..@sizeOf(u8)], v);
    return out;
}

fn encodeUint8(allocator: *std.mem.Allocator, v: u8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(u8));
    out[0] = Format.uint8.toUint8();
    std.mem.writeIntBig(u8, out[1 .. 1 + @sizeOf(u8)], v);
    return out;
}

fn encodeUint16(allocator: *std.mem.Allocator, v: u16) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(u16));
    out[0] = Format.uint16.toUint8();
    std.mem.writeIntBig(u16, out[1 .. 1 + @sizeOf(u16)], v);
    return out;
}

fn encodeUint32(allocator: *std.mem.Allocator, v: u32) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(u32));
    out[0] = Format.uint32.toUint8();
    std.mem.writeIntBig(u32, out[1 .. 1 + @sizeOf(u32)], v);
    return out;
}

fn encodeUint64(allocator: *std.mem.Allocator, v: u64) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(u64));
    out[0] = Format.uint64.toUint8();
    std.mem.writeIntBig(u64, out[1 .. 1 + @sizeOf(u64)], v);
    return out;
}

pub fn encodeNil(allocator: *std.mem.Allocator) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1);
    out[0] = Format.nil.toUint8();
    return out;
}

pub fn encodeBool(allocator: *std.mem.Allocator, v: bool) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1);
    switch (v) {
        true => out[0] = Format.bool_true.toUint8(),
        false => out[0] = Format.bool_false.toUint8(),
    }
    return out;
}

// encode native types

test "encode nil" {
    const hex = "c0";
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var encoded = try encode(std.testing.allocator, null);
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode optional bool true" {
    const hex = "c3";
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var b: ?bool = true;

    var encoded = try encode(std.testing.allocator, b);
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode bool true" {
    const hex = "c3";
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var encoded = try encode(std.testing.allocator, true);
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode uint64" {
    const hex = "cf0000001caab5c3b3"; // 123123123123
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var u: u64 = 123123123123;

    var encoded = try encode(std.testing.allocator, u);
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode comptime_int" {
    const hex = "d3fffffffd2198eb05"; // -12321232123
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var encoded = try encode(std.testing.allocator, -12321232123);
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode int64" {
    const hex = "d3fffffffd2198eb05"; // -12321232123
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var i: i64 = -12321232123;
    var encoded = try encode(std.testing.allocator, i);
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode str8 (literal)" {
    const hex = "d92368656c6c6f20776f726c642068656c6c6f20776f726c642068656c6c6f20776f726c64"; // "hello world hello world hello world"
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var encoded = try encode(std.testing.allocator, "hello world hello world hello world");
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode str8 (const)" {
    const hex = "d92368656c6c6f20776f726c642068656c6c6f20776f726c642068656c6c6f20776f726c64"; // "hello world hello world hello world"
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var str: []const u8 = "hello world hello world hello world";
    var encoded = try encode(std.testing.allocator, str);
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode str8" {
    const hex = "d92368656c6c6f20776f726c642068656c6c6f20776f726c642068656c6c6f20776f726c64"; // "hello world hello world hello world"
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var orig = "hello world hello world hello world";
    var str: []u8 = try std.testing.allocator.alloc(u8, orig.len);
    defer std.testing.allocator.free(str);
    std.mem.copy(u8, str, orig);
    var encoded = try encode(std.testing.allocator, str);
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode fix array" {
    const hex = "9acd03e8cd07d0cd0bb8cd0fa0cd1388cd1770cd1b58cd1f40cd2328cd2710"; // [1000,2000,3000,4000,5000,6000,7000,8000,9000,10000]
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var array = [_]u16{ 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000 };
    var encoded = try encode(std.testing.allocator, array);
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode struct" {
    const hex = "9acd03e8cd07d0cd0bb8cd0fa0cd1388cd1770cd1b58cd1f40cd2328cd2710"; // [1000,2000,3000,4000,5000,6000,7000,8000,9000,10000]
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    const s = struct {
        string: []const u8 = "string",
        int: i32 = -32,
        uint: u64 = 64,
        boul: bool = true,
    };

    var _s = s{};

    var encoded = try encode(std.testing.allocator, &_s);
    // testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.debug.print("map: {}\n", .{encoded});

    std.testing.allocator.free(encoded);
}
