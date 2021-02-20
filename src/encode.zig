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

pub const Encoder = struct {
    allocator: *std.mem.Allocator,
    asBinaryFields: ?std.BufSet = null,

    pub fn free(self: *Encoder) void {
        if (self.asBinaryFields) |*abf| {
            abf.deinit();
        }
    }

    pub fn encodeAsBinary(
        self: *Encoder,
        field: []const u8,
    ) !void {
        if (self.asBinaryFields == null) {
            self.asBinaryFields = std.BufSet.init(self.allocator);
        }
        try self.asBinaryFields.?.put(field);
    }

    pub fn encode(self: *Encoder, val: anytype) EncodeError![]u8 {
        // std.debug.print("tinfo: {}\n", .{@typeInfo(@TypeOf(val))});
        const ti = @typeInfo(@TypeOf(val));
        return switch (ti) {
            .Null => writeNil(self.allocator),
            .Bool => writeBool(self.allocator, val),
            .ComptimeInt => writeIntAny(self.allocator, val),
            .ComptimeFloat => writeFloatAny(self.allocator, val),
            .Int => |intInfo| switch (intInfo.is_signed) {
                true => switch (intInfo.bits) {
                    8 => writeIntAny(self.allocator, val),
                    16 => writeInt16(self.allocator, val),
                    32 => writeInt32(self.allocator, val),
                    64 => writeInt64(self.allocator, val),
                    else => error.UnsupportedType,
                },
                false => switch (intInfo.bits) {
                    8 => writeUintAny(self.allocator, val),
                    16 => writeUint16(self.allocator, val),
                    32 => writeUint32(self.allocator, val),
                    64 => writeUint64(self.allocator, val),
                    else => error.UnsupportedType,
                },
            },
            .Float => |floatInfo| switch (floatInfo.bits) {
                32 => writeFloat32(self.allocator, val),
                64 => writeFloat64(self.allocator, val),
                else => error.UnsupportedType,
            },
            .Optional => {
                if (val) |tmpv| {
                    return self.encode(tmpv);
                } else {
                    return writeNil(self.allocator);
                }
            },
            .Array => |arrayInfo| switch (arrayInfo.child) {
                u8 => writeStrAny(self.allocator, val[0..]),
                else => self.encodeArrayAny(arrayInfo.child, val[0..]),
            },
            .Pointer => |pointerInfo| switch (pointerInfo.size) {
                .One => switch (pointerInfo.child) {
                    u8 => writeStrAny(self.allocator, val),
                    else => self.encode(val.*),
                },
                .Slice => switch (pointerInfo.child) {
                    u8 => writeStrAny(self.allocator, val),
                    else => self.encode(val),
                },
                else => error.UnsupportedType,
            },
            .Struct => self.encodeStruct(@TypeOf(val), val),
            else => error.UnsupportedType,
        };
    }

    fn encodeStruct(self: *Encoder, comptime T: type, v: T) EncodeError![]u8 {
        const ti = @typeInfo(T);
        if (ti.Struct.fields.len <= fix_map_max) {
            return self.encodeFixMap(T, v);
        } else if (ti.Struct.fields.len <= fix_map16_max) {
            return self.encodeMap16(T, v);
        }
        return self.encodeMap32(T, v);
    }

    fn encodeFixMap(self: *Encoder, comptime T: type, v: T) EncodeError![]u8 {
        const len = @typeInfo(T).Struct.fields.len;
        var entries = try self.encodeMapEntries(T, v);
        var out = try self.allocator.alloc(u8, 1 + entries.len);
        out[0] = (Format{ .fix_map = @intCast(u8, len) }).toUint8();
        std.mem.copy(u8, out[1..], entries);
        // now release the elems and joined elems
        self.allocator.free(entries);
        return out;
    }

    fn encodeMapEntries(self: *Encoder, comptime T: type, v: T) EncodeError![]u8 {
        // allocate twice the size as we space for each keys
        // and values.
        const ti = @typeInfo(T);
        var entries = try self.allocator.alloc([]u8, ti.Struct.fields.len * 2);
        var i: usize = 0;
        inline for (ti.Struct.fields) |field| {
            // FIXME(): we have a memory leak here most likely
            // in the case we return an error the error is not
            // freed, but knowing that the only error which can happen
            // in encodeValue is an OutOfMemory error, it's quite
            // certain we would not recover anyway. Will take care of
            // this later
            var encodedkey = try writeStrAny(self.allocator, field.name);
            entries[i] = encodedkey;
            var encodedvalue = try self.encode(@field(v, field.name));
            entries[i + 1] = encodedvalue;
            i += 2;
        }
        // FIXME(): see previous comment, same concerns.
        var out = try std.mem.join(self.allocator, &[_]u8{}, entries);
        // free the slice of encoded elements as they are not required anymore
        for (entries) |e| {
            self.allocator.free(e);
        }
        self.allocator.free(entries);

        return out;
    }

    fn encodeArrayAny(self: *Encoder, comptime T: type, v: []const T) EncodeError![]u8 {
        if (v.len <= fix_array_max) {
            return self.encodeFixArray(T, v);
        } else if (v.len <= array16_max) {
            return self.encodeArray16(T, v);
        }
        return self.encodeArray32(T, v);
    }

    fn encodeFixArray(self: *Encoder, comptime T: type, v: []const T) EncodeError![]u8 {
        var elems = try self.encodeArrayElements(T, v);
        var out = try self.allocator.alloc(u8, 1 + elems.len);
        out[0] = (Format{ .fix_array = @intCast(u8, v.len) }).toUint8();
        std.mem.copy(u8, out[1..], elems);
        // now release the elems and joined elems
        self.allocator.free(elems);
        return out;
    }

    fn encodeArray16(self: *Encoder, comptime T: type, v: []const T) EncodeError![]u8 {
        var elems = try self.encodeArrayElements(T, v);
        var out = try self.allocator.alloc(u8, 1 + @sizeOf(u16) + elems.len);

        out[0] = Format.array16.toUint8();
        std.mem.writeIntBig(u16, out[1 .. 1 + @sizeOf(u16)], @intCast(u16, v.len));
        std.mem.copy(u8, out[1 + @sizeOf(u16) ..], elems);

        // now release the elems and joined elems
        self.allocator.free(elems);
        return out;
    }

    fn encodeArray32(self: *Encoder, comptime T: type, v: []const T) EncodeError![]u8 {
        var elems = try self.encodeArrayElements(T, v);
        var out = try self.allocator.alloc(u8, 1 + @sizeOf(u32) + elems.len);

        out[0] = Format.array32.toUint8();
        std.mem.writeIntBig(u32, out[1 .. 1 + @sizeOf(u32)], @intCast(u32, v.len));
        std.mem.copy(u8, out[1 + @sizeOf(u32) ..], elems);

        // now release the elems and joined elems
        self.allocator.free(elems);
        return out;
    }

    fn encodeArrayElements(self: *Encoder, comptime T: type, v: []const T) EncodeError![]u8 {
        var elems = try self.allocator.alloc([]u8, v.len);
        var i: usize = 0;
        while (i < v.len) {
            // FIXME(): we have a memory leak here most likely
            // in the case we return an error the error is not
            // freed, but knowing that the only error which can happen
            // in encodeValue is an OutOfMemory error, it's quite
            // certain we would not recover anyway. Will take care of
            // this later
            var encoded = try self.encode(v[i]);
            elems[i] = encoded;
            i += 1;
        }
        // FIXME(): see previous comment, same concerns.
        var out = try std.mem.join(self.allocator, &[_]u8{}, elems);
        // free the slice of encoded elements as they are not required anymore
        for (elems) |e| {
            self.allocator.free(e);
        }
        self.allocator.free(elems);

        return out;
    }
};

pub fn encode(allocator: *std.mem.Allocator, val: anytype) EncodeError![]u8 {
    var encoder = Encoder{
        .allocator = allocator,
    };

    return encoder.encode(val);
}

pub fn writeBinAny(allocator: *std.mem.Allocator, v: []const u8) EncodeError![]u8 {
    if (v.len <= str8_max) {
        return writeBin8(allocator, v);
    } else if (v.len <= str16_max) {
        return writeBin16(allocator, v);
    }
    return writeBin32(allocator, v);
}

fn writeBin8(allocator: *std.mem.Allocator, v: []const u8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 2 + v.len);
    out[0] = Format.bin8.toUint8();
    out[1] = @intCast(u8, v.len);
    std.mem.copy(u8, out[2 .. 2 + v.len], v);
    return out;
}

fn writeBin16(allocator: *std.mem.Allocator, v: []const u8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(u16) + v.len);
    out[0] = Format.bin16.toUint8();
    std.mem.writeIntBig(u16, out[1 .. 1 + @sizeOf(u16)], @intCast(u16, v.len));
    std.mem.copy(u8, out[1 + @sizeOf(u16) .. 1 + @sizeOf(u16) + v.len], v);
    return out;
}

fn writeBin32(allocator: *std.mem.Allocator, v: []const u8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(u32) + v.len);
    out[0] = Format.bin32.toUint8();
    std.mem.writeIntBig(u32, out[1 .. 1 + @sizeOf(u32)], @intCast(u32, v.len));
    std.mem.copy(u8, out[1 + @sizeOf(u32) .. 1 + @sizeOf(u32) + v.len], v);
    return out;
}

pub fn writeStrAny(allocator: *std.mem.Allocator, v: []const u8) EncodeError![]u8 {
    if (v.len <= fix_str_max) {
        return writeFixStr(allocator, v);
    } else if (v.len <= str8_max) {
        return writeStr8(allocator, v);
    } else if (v.len <= str16_max) {
        return writeStr16(allocator, v);
    }

    return writeStr32(allocator, v);
}

fn writeFixStr(allocator: *std.mem.Allocator, v: []const u8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + v.len);
    out[0] = (Format{ .fix_str = @intCast(u8, v.len) }).toUint8();
    std.mem.copy(u8, out[1 .. 1 + v.len], v);
    return out;
}

fn writeStr8(allocator: *std.mem.Allocator, v: []const u8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 2 + v.len);
    out[0] = Format.str8.toUint8();
    out[1] = @intCast(u8, v.len);
    std.mem.copy(u8, out[2 .. 2 + v.len], v);
    return out;
}

fn writeStr16(allocator: *std.mem.Allocator, v: []const u8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(u16) + v.len);
    out[0] = Format.str16.toUint8();
    std.mem.writeIntBig(u16, out[1 .. 1 + @sizeOf(u16)], @intCast(u16, v.len));
    std.mem.copy(u8, out[1 + @sizeOf(u16) .. 1 + @sizeOf(u16) + v.len], v);
    return out;
}

fn writeStr32(allocator: *std.mem.Allocator, v: []const u8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(u32) + v.len);
    out[0] = Format.str32.toUint8();
    std.mem.writeIntBig(u32, out[1 .. 1 + @sizeOf(u32)], @intCast(u32, v.len));
    std.mem.copy(u8, out[1 + @sizeOf(u32) .. 1 + @sizeOf(u32) + v.len], v);
    return out;
}

pub fn writeFloatAny(allocator: *std.mem.Allocator, v: f64) EncodeError![]u8 {
    if (v >= std.math.f32_min and v <= std.math.f32_max) {
        return writeFloat32(allocator, @floatCast(f32, v));
    }
    return writeFloat64(allocator, v);
}

fn writeFloat32(allocator: *std.mem.Allocator, v: f32) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(f32));
    out[0] = Format.float32.toUint8();
    std.mem.writeIntBig(u32, out[1 .. 1 + @sizeOf(u32)], @bitCast(u32, v));
    return out;
}

fn writeFloat64(allocator: *std.mem.Allocator, v: f64) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(f64));
    out[0] = Format.float64.toUint8();
    std.mem.writeIntBig(u64, out[1 .. 1 + @sizeOf(u64)], @bitCast(u64, v));
    return out;
}

pub fn writeIntAny(allocator: *std.mem.Allocator, v: i64) EncodeError![]u8 {
    if (v >= neg_int_fix_min and v <= 0) {
        return writeNegativeFixInt(allocator, @intCast(i8, v));
    } else if (v >= int8_min and v <= int8_max) {
        return writeInt8(allocator, @intCast(i8, v));
    } else if (v >= int16_min and v <= int16_max) {
        return writeInt16(allocator, @intCast(i16, v));
    } else if (v >= int32_min and v <= int32_max) {
        return writeInt32(allocator, @intCast(i32, v));
    }
    return writeInt64(allocator, v);
}

fn writeNegativeFixInt(allocator: *std.mem.Allocator, v: i8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, @sizeOf(i8));
    std.mem.writeIntBig(i8, out[0..@sizeOf(i8)], v);
    return out;
}

fn writeInt8(allocator: *std.mem.Allocator, v: i8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(i8));
    out[0] = Format.int8.toUint8();
    std.mem.writeIntBig(i8, out[1 .. 1 + @sizeOf(i8)], v);
    return out;
}

fn writeInt16(allocator: *std.mem.Allocator, v: i16) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(i16));
    out[0] = Format.int16.toUint8();
    std.mem.writeIntBig(i16, out[1 .. 1 + @sizeOf(i16)], v);
    return out;
}

fn writeInt32(allocator: *std.mem.Allocator, v: i32) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(i32));
    out[0] = Format.int32.toUint8();
    std.mem.writeIntBig(i32, out[1 .. 1 + @sizeOf(i32)], v);
    return out;
}

fn writeInt64(allocator: *std.mem.Allocator, v: i64) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(i64));
    out[0] = Format.int64.toUint8();
    std.mem.writeIntBig(i64, out[1 .. 1 + @sizeOf(i64)], v);
    return out;
}

pub fn writeUintAny(allocator: *std.mem.Allocator, v: u64) EncodeError![]u8 {
    if (v <= pos_int_fix_max) {
        return writePositiveFixInt(allocator, @intCast(u8, v));
    } else if (v <= uint8_max) {
        return writeUint8(allocator, @intCast(u8, v));
    } else if (v <= uint16_max) {
        return writeUint16(allocator, @intCast(u16, v));
    } else if (v <= uint32_max) {
        return writeUint32(allocator, @intCast(u32, v));
    }
    return writeUint64(allocator, v);
}

fn writePositiveFixInt(allocator: *std.mem.Allocator, v: u8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, @sizeOf(u8));
    std.mem.writeIntBig(u8, out[0..@sizeOf(u8)], v);
    return out;
}

fn writeUint8(allocator: *std.mem.Allocator, v: u8) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(u8));
    out[0] = Format.uint8.toUint8();
    std.mem.writeIntBig(u8, out[1 .. 1 + @sizeOf(u8)], v);
    return out;
}

fn writeUint16(allocator: *std.mem.Allocator, v: u16) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(u16));
    out[0] = Format.uint16.toUint8();
    std.mem.writeIntBig(u16, out[1 .. 1 + @sizeOf(u16)], v);
    return out;
}

fn writeUint32(allocator: *std.mem.Allocator, v: u32) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(u32));
    out[0] = Format.uint32.toUint8();
    std.mem.writeIntBig(u32, out[1 .. 1 + @sizeOf(u32)], v);
    return out;
}

fn writeUint64(allocator: *std.mem.Allocator, v: u64) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1 + @sizeOf(u64));
    out[0] = Format.uint64.toUint8();
    std.mem.writeIntBig(u64, out[1 .. 1 + @sizeOf(u64)], v);
    return out;
}

pub fn writeNil(allocator: *std.mem.Allocator) EncodeError![]u8 {
    var out = try allocator.alloc(u8, 1);
    out[0] = Format.nil.toUint8();
    return out;
}

pub fn writeBool(allocator: *std.mem.Allocator, v: bool) EncodeError![]u8 {
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
    // std.debug.print("map: {}\n", .{encoded});
    std.testing.allocator.free(encoded);
}

test "encoder set encode as binary" {
    var encoder = Encoder{
        .allocator = std.testing.allocator,
    };
    defer encoder.free();

    try encoder.encodeAsBinary("hello");
}
