const std = @import("std");

const decode = @import("decode.zig");
const encode = @import("encode.zig");
const format = @import("format.zig");
const value = @import("value.zig");

// {"booltrue":true, "boolfalse": false, "int": 42, "float": 1.21, "nil": null}
const hexdata = "85a8626f6f6c74727565c3a9626f6f6c66616c7365c2a3696e742aa5666c6f6174cb3ff35c28f5c28f5ca36e696cc0";

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // convert hex data into bytes
    var data = try arena.allocator.alloc(u8, hexdata.len / 2);
    try std.fmt.hexToBytes(data, hexdata);

    // const v = try decode.read(data);

    const hex = "942ac3a6737472696e67cb404535c28f5c28f6"; // "[42, true, "string", 42.42]"
    var bytes: [hex.len / 2]u8 = undefined;
    try std.fmt.hexToBytes(bytes[0..], hex);
    var values = [4]value.Value{ .{ .uint = 42 }, .{ .bool = true }, .{ .string = "string" }, .{ .float = 42.42 } };

    var encoded = try encode.encodeValue(&arena.allocator, value.Value{ .array = values[0..] });

    std.log.info("{}|{}", .{ bytes[0], encoded[0] });
    std.log.info("{}|{}", .{ bytes.len, bytes });
    std.log.info("{}|{}", .{ encoded.len, encoded });

    arena.allocator.free(encoded);

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

test "test suite" {}
