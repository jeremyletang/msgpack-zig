const std = @import("std");
const msgpack = @import("msgpack");
const expect = std.testing.expect;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // build a map which is going to hold our values
    var values = std.StringHashMap(msgpack.Value).init(&gpa.allocator);
    try values.put("s", msgpack.Value{ .string = "string" });
    try values.put("u", msgpack.Value{ .uint = 123456 });
    try values.put("b", msgpack.Value{ .bool = true });
    try values.put("i", msgpack.Value{ .int = -12343 });
    var array = try std.ArrayList(msgpack.Value).initCapacity(&gpa.allocator, 2);
    try array.append(.{ .uint = 1 });
    try array.append(.{ .string = "hello" });
    try values.put("a", msgpack.Value{ .array = array });
    var m = std.StringHashMap(msgpack.Value).init(&gpa.allocator);
    try m.put("s", msgpack.Value{ .string = "hello world" });
    try values.put("m", msgpack.Value{ .map = m });
    try values.put("n", .nil);

    var orig = msgpack.Value{ .map = values };
    defer orig.free();

    // msgpack encode the value
    var encoded = try msgpack.encodeValue(&gpa.allocator, orig);
    defer gpa.allocator.free(encoded);

    // then let's decode it again
    var decoded = try msgpack.decodeValue(&gpa.allocator, encoded);
    defer decoded.free();

    // now let's compare the orginal value and the decoded one
    expect(std.mem.eql(u8, values.get("s").?.string, decoded.map.get("s").?.string));
    expect(values.get("u").?.uint == decoded.map.get("u").?.uint);
    expect(values.get("b").?.bool == decoded.map.get("b").?.bool);
    expect(values.get("i").?.int == decoded.map.get("i").?.int);
    expect(values.get("a").?.array.items[0].uint == decoded.map.get("a").?.array.items[0].uint);
    expect(std.mem.eql(u8, values.get("a").?.array.items[1].string, decoded.map.get("a").?.array.items[1].string));
    expect(std.mem.eql(u8, values.get("m").?.map.get("s").?.string, decoded.map.get("m").?.map.get("s").?.string));
    expect(values.get("n").?.nil == decoded.map.get("n").?.nil);

    // we can use the value.equal method as well.
    expect(orig.equal(decoded));

    decoded.dump();
}
