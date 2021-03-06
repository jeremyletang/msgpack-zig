const std = @import("std");
const format = @import("format.zig");
const value = @import("value.zig");
const expect = std.testing.expect;

pub const encodeValue = @import("encode_value.zig").encodeValue;
pub const decodeValue = @import("decode_value.zig").decodeValue;
pub const encode = @import("encode.zig").encode;
pub const decode = @import("decode.zig").decode;
pub const Decoder = @import("decoder.zig").Decoder;
pub const Encoder = @import("encoder.zig").Encoder;
pub const Value = value.Value;

pub fn valid(allocator: *std.mem.Allocator, buf: []const u8) bool {
    if (decodeValue(allocator, buf)) |foo| {
        return true;
    }
    return false;
}

test "test encode / decode map" {
    var values = std.StringHashMap(value.Value).init(std.testing.allocator);
    try values.put("s", value.Value{ .string = "string" });
    try values.put("u", value.Value{ .uint = 123456 });
    try values.put("b", value.Value{ .bool = true });
    try values.put("i", value.Value{ .int = -12343 });
    var array = try std.ArrayList(value.Value).initCapacity(std.testing.allocator, 2);
    try array.append(.{ .uint = 1 });
    try array.append(.{ .string = "hello" });
    try values.put("a", value.Value{ .array = array });
    var m = std.StringHashMap(value.Value).init(std.testing.allocator);
    try m.put("s", value.Value{ .string = "hello world" });
    try values.put("m", value.Value{ .map = m });
    try values.put("n", .nil);

    var val = value.Value{ .map = values };
    var encoded = try encodeValue(std.testing.allocator, val);
    var decoded = try decodeValue(std.testing.allocator, encoded);

    expect(std.mem.eql(u8, values.get("s").?.string, decoded.map.get("s").?.string));
    expect(values.get("u").?.uint == decoded.map.get("u").?.uint);
    expect(values.get("b").?.bool == decoded.map.get("b").?.bool);
    expect(values.get("i").?.int == decoded.map.get("i").?.int);
    expect(values.get("a").?.array.items[0].uint == decoded.map.get("a").?.array.items[0].uint);
    expect(std.mem.eql(u8, values.get("a").?.array.items[1].string, decoded.map.get("a").?.array.items[1].string));
    expect(std.mem.eql(u8, values.get("m").?.map.get("s").?.string, decoded.map.get("m").?.map.get("s").?.string));
    expect(values.get("n").?.nil == decoded.map.get("n").?.nil);

    decoded.free();
    std.testing.allocator.free(encoded);
    val.free();
}
