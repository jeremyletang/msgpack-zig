const std = @import("std");
const format = @import("format.zig");
const value = @import("value.zig");
const expect = std.testing.expect;
const Format = format.Format;

const DecodeError = error{
    EmptyInput,
    TruncatedInput,
    ReservedFormat,
};

pub fn read(buf: []const u8) DecodeError!value.Value {
    if (buf.len == 0) {
        return error.EmptyInput;
    }
    return switch (format.from_u8(buf[0])) {
        Format.nil => .nil,
        Format.never_used => error.ReservedFormat,
        Format.bool_false => value.Value{ .bool = false },
        Format.bool_true => value.Value{ .bool = true },
        Format.float32 => read_f32(buf[1..]),
        Format.float64 => read_f64(buf[1..]),
        Format.uint8 => read_u8(buf[1..]),
        Format.uint16 => read_u16(buf[1..]),
        Format.uint32 => read_u32(buf[1..]),
        Format.uint64 => read_u64(buf[1..]),
        Format.int8 => read_i8(buf[1..]),
        Format.int16 => read_i16(buf[1..]),
        Format.int32 => read_i32(buf[1..]),
        Format.int64 => read_i64(buf[1..]),
        Format.positive_fix_int => |i| value.Value{ .uint = i },
        Format.negative_fix_int => |i| value.Value{ .int = @intCast(i64, i) },
        else => unreachable,
    };
}

fn read_u8(buf: []const u8) DecodeError!value.Value {
    if (buf.len < 1) {
        return error.TruncatedInput;
    }
    return value.Value{ .uint = buf[0] };
}

fn read_u16(buf: []const u8) DecodeError!value.Value {
    if (buf.len < 2) {
        return error.TruncatedInput;
    }
    return value.Value{ .uint = std.mem.readIntSliceBig(u16, buf) };
}

fn read_u32(buf: []const u8) DecodeError!value.Value {
    if (buf.len < 4) {
        return error.TruncatedInput;
    }
    return value.Value{ .uint = std.mem.readIntSliceBig(u32, buf) };
}

fn read_u64(buf: []const u8) DecodeError!value.Value {
    if (buf.len < 8) {
        return error.TruncatedInput;
    }
    return value.Value{ .uint = std.mem.readIntSliceBig(u64, buf) };
}

fn read_i8(buf: []const u8) DecodeError!value.Value {
    if (buf.len < 1) {
        return error.TruncatedInput;
    }
    return value.Value{ .int = std.mem.readIntSliceBig(i8, buf) };
}

fn read_i16(buf: []const u8) DecodeError!value.Value {
    if (buf.len < 2) {
        return error.TruncatedInput;
    }
    return value.Value{ .int = std.mem.readIntSliceBig(i16, buf) };
}

fn read_i32(buf: []const u8) DecodeError!value.Value {
    if (buf.len < 4) {
        return error.TruncatedInput;
    }
    return value.Value{ .int = std.mem.readIntSliceBig(i32, buf) };
}

fn read_i64(buf: []const u8) DecodeError!value.Value {
    if (buf.len < 8) {
        return error.TruncatedInput;
    }
    return value.Value{ .int = std.mem.readIntSliceBig(i64, buf) };
}

fn read_f32(buf: []const u8) DecodeError!value.Value {
    if (buf.len < 4) {
        return error.TruncatedInput;
    }
    return value.Value{ .float = @bitCast(f32, std.mem.readIntSliceBig(u32, buf)) };
}

fn read_f64(buf: []const u8) DecodeError!value.Value {
    if (buf.len < 8) {
        return error.TruncatedInput;
    }
    return value.Value{ .float = @bitCast(f64, std.mem.readIntSliceBig(u64, buf)) };
}

test "empty input" {
    var data: [0]u8 = undefined;

    if (read(data[0..])) {
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
    var v = try read(data[0..]);
    expect(v == .nil);
}

test "decode false" {
    const hex = "c2";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try read(data[0..]);
    expect(v.bool == false);
}

test "decode true" {
    const hex = "c3";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try read(data[0..]);
    expect(v.bool == true);
}

test "decode uint8" {
    const hex = "cc80"; // 128
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try read(data[0..]);
    expect(v.uint == 128);
}

test "decode uint8 truncated error" {
    const hex = "cc";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    if (read(data[0..])) {
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
    var v = try read(data[0..]);
    expect(v.uint == 1600);
}

test "decode uint16 truncated error" {
    const hex = "cd06";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    if (read(data[0..])) {
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
    var v = try read(data[0..]);
    expect(v.uint == 12312312);
}

test "decode uint32 truncated error" {
    const hex = "ce00bbde";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    if (read(data[0..])) {
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
    var v = try read(data[0..]);
    expect(v.uint == 123123123123);
}

test "decode uint64 truncated error" {
    const hex = "cf0000001caab5c3";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    if (read(data[0..])) {
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
    var v = try read(data[0..]);
    expect(v.int == -123);
}

test "decode int8 truncated error" {
    const hex = "d0";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    if (read(data[0..])) {
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
    var v = try read(data[0..]);
    expect(v.int == -1232);
}

test "decode int16 truncated error" {
    const hex = "d1fb";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    if (read(data[0..])) {
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
    var v = try read(data[0..]);
    expect(v.int == -123212);
}

test "decode int32 truncated error" {
    const hex = "d2fffe1e";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    if (read(data[0..])) {
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
    var v = try read(data[0..]);
    expect(v.int == -12321232123);
}

test "decode int64 truncated error" {
    const hex = "d3fffffffd2198eb";
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    if (read(data[0..])) {
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
    var v = try read(data[0..]);
    expect(v.float == 4.548399448394775);
}

test "decode float 64" {
    const hex = "cb40918c7df3b645a2"; // 1123.123
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try read(data[0..]);
    expect(v.float == 1123.123);
}

test "decode positive fix int" {
    const hex = "0c"; // 12
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try read(data[0..]);
    expect(v.uint == 12);
}

test "decode negative fix int" {
    const hex = "e0"; // -32
    var data: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(data[0..], hex);
    var v = try read(data[0..]);
    expect(v.int == -32);
}
