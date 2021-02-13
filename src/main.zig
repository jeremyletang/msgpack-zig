const std = @import("std");

const decode = @import("decode.zig");
const encode = @import("encode.zig");
const format = @import("format.zig");
const value = @import("value.zig");
const expect = std.testing.expect;

// {"booltrue":true, "boolfalse": false, "int": 42, "float": 1.21, "nil": null}
const hexdata = "85a8626f6f6c74727565c3a9626f6f6c66616c7365c2a3696e742aa5666c6f6174cb3ff35c28f5c28f5ca36e696cc0";

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // convert hex data into bytes
    var data = try arena.allocator.alloc(u8, hexdata.len / 2);
    try std.fmt.hexToBytes(data, hexdata);

    // const v = try decode.read(data);

    // const hex = "88a173a6737472696e67a175ce0001e240a162c3a166cbc0a238a57e670e2ca169d1cfc9a1619201a568656c6c6fa16d81a173ab68656c6c6f20776f726c64a16ec0";
    // var data2: [hex.len / 2]u8 = undefined;
    // try std.fmt.hexToBytes(data2[0..], hex);
    // var v2 = try decode.decodeValue(&arena.allocator, data2[0..]);

    // std.log.info("u: {}", .{v2.map.getEntry("u")});

    // // var items = v2.map.items();
    // // for (items) |*i| {
    // //     std.log.info("VALUE: {}", .{i});
    // // }

    // v2.free(&arena.allocator);
}

test "test encode / decode map" {
    var values = std.StringHashMap(value.Value).init(std.testing.allocator);
    try values.put("s", value.Value{ .string = "string" });
    try values.put("u", value.Value{ .uint = 123456 });
    try values.put("b", value.Value{ .bool = true });
    try values.put("i", value.Value{ .int = -12343 });
    var array = [_]value.Value{ .{ .uint = 1 }, .{ .string = "hello" } };
    try values.put("a", value.Value{ .array = array[0..] });
    var m = std.StringHashMap(value.Value).init(std.testing.allocator);
    try m.put("s", value.Value{ .string = "hello world" });
    try values.put("m", value.Value{ .map = m });
    try values.put("n", .nil);

    var val = value.Value{ .map = values };
    var encoded = try encode.encodeValue(std.testing.allocator, val);
    var decoded = try decode.decodeValue(std.testing.allocator, encoded);

    expect(std.mem.eql(u8, values.get("s").?.string, decoded.map.get("s").?.string));
    expect(values.get("u").?.uint == decoded.map.get("u").?.uint);
    expect(values.get("b").?.bool == decoded.map.get("b").?.bool);
    expect(values.get("i").?.int == decoded.map.get("i").?.int);
    expect(values.get("a").?.array[0].uint == decoded.map.get("a").?.array[0].uint);
    expect(std.mem.eql(u8, values.get("a").?.array[1].string, decoded.map.get("a").?.array[1].string));
    expect(std.mem.eql(u8, values.get("m").?.map.get("s").?.string, decoded.map.get("m").?.map.get("s").?.string));
    expect(values.get("n").?.nil == decoded.map.get("n").?.nil);

    decoded.free(std.testing.allocator);
    std.testing.allocator.free(encoded);

    // we deinit ourself the map we created
    m.deinit();
    val.map.deinit();
}
