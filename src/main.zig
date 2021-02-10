const std = @import("std");

const decode = @import("decode.zig");
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

    const v = try decode.decode(data);

    // const f = Format.from_u8(0xd4);
    // std.log.info("All your codebase are belong to us. {}, {}", .{ f, f.to_u8() });
}
