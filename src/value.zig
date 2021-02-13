const std = @import("std");
const expect = std.testing.expect;

pub const Value = union(enum) {
    int: i64,
    uint: u64,
    nil,
    bool: bool,
    float: f64,
    string: []const u8,
    binary: []const u8,
    array: std.ArrayList(Value),
    map: std.StringHashMap(Value),

    pub fn fromInt(val: i64) Value {
        return .{ .int = val };
    }

    pub fn fromUint(val: u64) Value {
        return .{ .uint = val };
    }

    pub fn fromBool(val: bool) Value {
        return .{ .bool = val };
    }

    pub fn fromFloat(val: float) Value {
        return .{ .float = val };
    }

    pub fn fromString(val: []const u8) Value {
        return .{ .string = val };
    }

    pub fn fromBinary(val: []const u8) Value {
        return .{ .bool = val };
    }

    pub fn fromArray(val: []Value) Value {
        return .{ .array = val };
    }

    pub fn fromMap(val: std.StringHashMap(Value)) Value {
        return .{ .map = val };
    }

    pub fn equal(self: Value, oth: Value) bool {
        return switch (self) {
            .int => |val| oth.equalInt(val),
            .uint => |val| oth.equalUint(val),
            .nil => oth.isNil(),
            .bool => |val| oth.equalBool(val),
            .float => |val| oth.equalFloat(val),
            .string => |val| oth.equalString(val),
            .binary => |val| oth.equalBinary(val),
            .array => |val| oth.equalArray(val),
            .map => |val| oth.equalMap(val),
        };
    }

    fn equalInt(self: Value, oth: i64) bool {
        return switch (self) {
            .int => |val| val == oth,
            else => false,
        };
    }

    fn equalUint(self: Value, oth: u64) bool {
        return switch (self) {
            .uint => |val| val == oth,
            else => false,
        };
    }

    fn isNil(self: Value) bool {
        return switch (self) {
            .nil => true,
            else => false,
        };
    }

    fn equalBool(self: Value, oth: bool) bool {
        return switch (self) {
            .bool => |val| val == oth,
            else => false,
        };
    }

    fn equalFloat(self: Value, oth: f64) bool {
        return switch (self) {
            .float => |val| val == oth,
            else => false,
        };
    }

    fn equalString(self: Value, oth: []const u8) bool {
        return switch (self) {
            .string => |val| std.mem.eql(u8, val, oth),
            else => false,
        };
    }

    fn equalBinary(self: Value, oth: []const u8) bool {
        return switch (self) {
            .binary => |val| std.mem.eql(u8, val, oth),
            else => false,
        };
    }

    fn equalArray(self: Value, oth: std.ArrayList(Value)) bool {
        return switch (self) {
            .array => |val| {
                if (val.items.len != oth.items.len) {
                    return false;
                }
                var i: usize = 0;
                while (i < val.items.len) {
                    if (!val.items[i].equal(oth.items[i])) {
                        return false;
                    }
                    i += 1;
                }
                return true;
            },
            else => false,
        };
    }

    fn equalMap(self: Value, oth: std.StringHashMap(Value)) bool {
        return switch (self) {
            .map => |val| {
                return false;
            },
            else => false,
        };
    }

    pub fn free(self: *Value) void {
        switch (self.*) {
            .array => {
                for (self.array.items) |*v| {
                    v.free();
                }
                self.array.deinit();
            },
            .map => {
                var it = self.map.iterator();
                while (it.next()) |i| {
                    i.value.free();
                }
                self.map.deinit();
            },
            else => {},
        }
    }
};

test "equal int" {
    expect(!(Value{ .int = 42 }).equal(.nil));
    expect(!(Value{ .int = 42 }).equal(Value{ .int = 84 }));
    expect((Value{ .int = 42 }).equal(Value{ .int = 42 }));
}

test "equal uint" {
    expect(!(Value{ .uint = 42 }).equal(.nil));
    expect(!(Value{ .uint = 42 }).equal(Value{ .uint = 84 }));
    expect((Value{ .uint = 42 }).equal(Value{ .uint = 42 }));
}

test "equal float" {
    expect(!(Value{ .float = 42 }).equal(.nil));
    expect(!(Value{ .float = 42 }).equal(Value{ .float = 84 }));
    expect((Value{ .float = 42 }).equal(Value{ .float = 42 }));
}

test "equal bool" {
    expect(!(Value{ .bool = true }).equal(.nil));
    expect(!(Value{ .bool = true }).equal(Value{ .bool = false }));
    expect((Value{ .bool = true }).equal(Value{ .bool = true }));
}

test "equal string" {
    expect(!(Value{ .string = "hello world" }).equal(.nil));
    expect(!(Value{ .string = "hello world" }).equal(Value{ .string = "hello" }));
    expect((Value{ .string = "hello world" }).equal(Value{ .string = "hello world" }));
}
