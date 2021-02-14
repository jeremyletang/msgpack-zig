const std = @import("std");
const encode = @import("encode.zig");
const value = @import("value.zig");
const testing = std.testing;
const Format = @import("format.zig").Format;

const EncodeError = encode.EncodeError;

pub fn encodeValue(allocator: *std.mem.Allocator, v: value.Value) EncodeError![]u8 {
    return switch (v) {
        .int => |val| encode.encodeIntAny(allocator, val),
        .uint => |val| encode.encodeUintAny(allocator, val),
        .nil => encode.encodeNil(allocator),
        .bool => |val| encode.encodeBool(allocator, val),
        .float => |val| encode.encodeFloatAny(allocator, val),
        .string => |val| encode.encodeStrAny(allocator, val),
        .binary => |val| encode.encodeBinAny(allocator, val),
        .array => |val| encodeArrayValue(allocator, val),
        .map => |val| encodeMapValue(allocator, val),
    };
}

fn encodeMapValue(allocator: *std.mem.Allocator, v: std.StringHashMap(value.Value)) EncodeError![]u8 {
    if (v.count() <= encode.fix_map_max) {
        return encodeFixMapValue(allocator, v);
    } else if (v.count() <= encode.map16_max) {
        return encodeMap16Value(allocator, v);
    }
    return encodeMap32Value(allocator, v);
}

fn encodeFixMapValue(allocator: *std.mem.Allocator, v: std.StringHashMap(value.Value)) EncodeError![]u8 {
    var entries = try encodeMapValueEntries(allocator, v);
    var out = try allocator.alloc(u8, 1 + entries.len);
    out[0] = (Format{ .fix_map = @intCast(u8, v.count()) }).toUint8();
    std.mem.copy(u8, out[1..], entries);
    // now release the elems and joined elems
    allocator.free(entries);
    return out;
}

fn encodeMap16Value(allocator: *std.mem.Allocator, v: std.StringHashMap(value.Value)) EncodeError![]u8 {
    var entries = try encodeMapValueEntries(allocator, v);
    var out = try allocator.alloc(u8, 1 + @sizeOf(u16) + entries.len);

    out[0] = Format.map16.toUint8();
    std.mem.writeIntBig(u16, out[1 .. 1 + @sizeOf(u16)], @intCast(u16, v.count()));
    std.mem.copy(u8, out[1 + @sizeOf(u16) ..], entries);

    // now release the elems and joined elems
    allocator.free(entries);

    return out;
}

fn encodeMap32Value(allocator: *std.mem.Allocator, v: std.StringHashMap(value.Value)) EncodeError![]u8 {
    var entries = try encodeMapValueEntries(allocator, v);
    var out = try allocator.alloc(u8, 1 + @sizeOf(u32) + entries.len);

    out[0] = Format.map32.toUint8();
    std.mem.writeIntBig(u32, out[1 .. 1 + @sizeOf(u32)], @intCast(u32, v.count()));
    std.mem.copy(u8, out[1 + @sizeOf(u32) ..], entries);

    // now release the elems and joined elems
    allocator.free(entries);

    return out;
}

fn encodeMapValueEntries(allocator: *std.mem.Allocator, v: std.StringHashMap(value.Value)) EncodeError![]u8 {
    // allocate twice the size as we space for each keys
    // and values.
    var entries = try allocator.alloc([]u8, v.count() * 2);
    var i: usize = 0;
    var it = v.iterator();
    while (it.next()) |entry| {
        // FIXME(): we have a memory leak here most likely
        // in the case we return an error the error is not
        // freed, but knowing that the only error which can happen
        // in encodeValue is an OutOfMemory error, it's quite
        // certain we would not recover anyway. Will take care of
        // this later
        var encodedkey = try encode.encodeStrAny(allocator, entry.key);
        entries[i] = encodedkey;
        var encodedvalue = try encodeValue(allocator, entry.value);
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

fn encodeArrayValue(allocator: *std.mem.Allocator, v: std.ArrayList(value.Value)) EncodeError![]u8 {
    if (v.items.len <= encode.fix_array_max) {
        return encodeFixArrayValue(allocator, v);
    } else if (v.items.len <= encode.array16_max) {
        return encodeArray16Value(allocator, v);
    }
    return encodeArray32Value(allocator, v);
}

fn encodeFixArrayValue(allocator: *std.mem.Allocator, v: std.ArrayList(value.Value)) EncodeError![]u8 {
    var elems = try encodeArrayValueElements(allocator, v);
    var out = try allocator.alloc(u8, 1 + elems.len);
    out[0] = (Format{ .fix_array = @intCast(u8, v.items.len) }).toUint8();
    std.mem.copy(u8, out[1..], elems);
    // now release the elems and joined elems
    allocator.free(elems);
    return out;
}

fn encodeArray16Value(allocator: *std.mem.Allocator, v: std.ArrayList(value.Value)) EncodeError![]u8 {
    var elems = try encodeArrayValueElements(allocator, v);
    var out = try allocator.alloc(u8, 1 + @sizeOf(u16) + elems.len);

    out[0] = Format.array16.toUint8();
    std.mem.writeIntBig(u16, out[1 .. 1 + @sizeOf(u16)], @intCast(u16, v.items.len));
    std.mem.copy(u8, out[1 + @sizeOf(u16) ..], elems);

    // now release the elems and joined elems
    allocator.free(elems);

    return out;
}

fn encodeArray32Value(allocator: *std.mem.Allocator, v: std.ArrayList(value.Value)) EncodeError![]u8 {
    var elems = try encodeArrayValueElements(allocator, v);
    var out = try allocator.alloc(u8, 1 + @sizeOf(u32) + elems.len);

    out[0] = Format.array32.toUint8();
    std.mem.writeIntBig(u32, out[1 .. 1 + @sizeOf(u32)], @intCast(u32, v.items.len));
    std.mem.copy(u8, out[1 + @sizeOf(u32) ..], elems);

    // now release the elems and joined elems
    allocator.free(elems);

    return out;
}

fn encodeArrayValueElements(allocator: *std.mem.Allocator, v: std.ArrayList(value.Value)) EncodeError![]u8 {
    var elems = try allocator.alloc([]u8, v.items.len);
    var i: usize = 0;
    while (i < v.items.len) {
        // FIXME(): we have a memory leak here most likely
        // in the case we return an error the error is not
        // freed, but knowing that the only error which can happen
        // in encodeValue is an OutOfMemory error, it's quite
        // certain we would not recover anyway. Will take care of
        // this later
        var encoded = try encodeValue(allocator, v.items[i]);
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

test "encode value: nil" {
    const hex = "c0";
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var encoded = try encodeValue(std.testing.allocator, .nil);
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode value: bool false" {
    const hex = "c2";
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var encoded = try encodeValue(std.testing.allocator, value.Value{ .bool = false });
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode value: bool true" {
    const hex = "c3";
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var encoded = try encodeValue(std.testing.allocator, value.Value{ .bool = true });
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode value: fix positive int" {
    const hex = "64"; // 100
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var encoded = try encodeValue(std.testing.allocator, value.Value{ .uint = 100 });
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode value: uint8" {
    const hex = "cc80"; // 128
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var encoded = try encodeValue(std.testing.allocator, value.Value{ .uint = 128 });
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode value: uint16" {
    const hex = "cd0640"; // 1600
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var encoded = try encodeValue(std.testing.allocator, value.Value{ .uint = 1600 });
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode value: uint32" {
    const hex = "ce00bbdef8"; // 12312312
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var encoded = try encodeValue(std.testing.allocator, value.Value{ .uint = 12312312 });
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode value: uint64" {
    const hex = "cf0000001caab5c3b3"; // 123123123123
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var encoded = try encodeValue(std.testing.allocator, value.Value{ .uint = 123123123123 });
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode value: negative fix int" {
    const hex = "e0"; // -32
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var encoded = try encodeValue(std.testing.allocator, value.Value{ .int = -32 });
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode value: int8" {
    const hex = "d085"; // -123
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var encoded = try encodeValue(std.testing.allocator, value.Value{ .int = -123 });
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode value: int16" {
    const hex = "d1fb30"; // -1232
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var encoded = try encodeValue(std.testing.allocator, value.Value{ .int = -1232 });
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode value: int32" {
    const hex = "d2fffe1eb4"; // -123212
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var encoded = try encodeValue(std.testing.allocator, value.Value{ .int = -123212 });
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode value: int64" {
    const hex = "d3fffffffd2198eb05"; // -12321232123
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var encoded = try encodeValue(std.testing.allocator, value.Value{ .int = -12321232123 });
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode value: fix str" {
    const hex = "ab68656c6c6f20776f726c64"; // "hello world"
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var encoded = try encodeValue(std.testing.allocator, value.Value{ .string = "hello world" });
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode value: str8" {
    const hex = "d92368656c6c6f20776f726c642068656c6c6f20776f726c642068656c6c6f20776f726c64"; // "hello world hello world hello world"
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var encoded = try encodeValue(std.testing.allocator, value.Value{ .string = "hello world hello world hello world" });
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

test "encode value: str16" {
    const hex = "da0132617364617364617364617364617364617364617364617364617364617364617364617364617364617364617364617364647361617364617364617364617364617364617364617364617364617364617364617364617364617364617364617364617364647361617364617364617364617364617364617364617364617364617364617364617364617364617364617364617364617364647361617364617364617364617364617364617364617364617364617364617364617364617364617364617364617364617364647361617364617364617364617364617364617364617364617364617364617364617364617364617364617364617364617364617364617364617364617364617364617364617364617364617364617364647361617364617364617364617364617364617364647361"; // "hello world hello world hello world"
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);

    var encoded = try encodeValue(std.testing.allocator, value.Value{ .string = "asdasdasdasdasdasdasdasdasdasdasdasdasdasdasdasddsaasdasdasdasdasdasdasdasdasdasdasdasdasdasdasdasddsaasdasdasdasdasdasdasdasdasdasdasdasdasdasdasdasddsaasdasdasdasdasdasdasdasdasdasdasdasdasdasdasdasddsaasdasdasdasdasdasdasdasdasdasdasdasdasdasdasdasdasdasdasdasdasdasdasdasdasdasddsaasdasdasdasdasdasddsa" });
    testing.expect(std.mem.eql(u8, bytes[0..], encoded));
    std.testing.allocator.free(encoded);
}

// FIXME(): this test is working as expected, but the encoded float is
// f32 while the reference example generate r64...
// test "encode value: fix array" {
//     const hex = "942ac3a6737472696e67cb404535c28f5c28f6"; // "[42, true, "string", 42.42]"
//     var bytes: [hex.len / 2]u8 = undefined;
//     try std.fmt.hexToBytes(bytes[0..], hex);
//     var values = [4]value.Value{ .{ .uint = 42 }, .{ .bool = true }, .{ .string = "string" }, .{ .float = 42.42 } };

//     var encoded = try encodeValue(std.testing.allocator, value.Value{ .array = values[0..] });
//     testing.expect(std.mem.eql(u8, bytes[0..], encoded));
//     std.testing.allocator.free(encoded);
// }
