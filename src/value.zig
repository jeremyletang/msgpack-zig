const std = @import("std");

pub const Value = union(enum) {
    int: i64,
    uint: u64,
    nil,
    bool: bool,
    float: f64,
    string: []u8,
    array: []Value,
    map: std.AutoArrayHashMap([]u8, Value),
};
