const std = @import("std");

const FIXSTR_SIZE: u8 = 0x1f;
const FIXARRAY_SIZE: u8 = 0x0f;
const FIXMAP_SIZE: u8 = 0x0f;

pub fn from_u8(u: u8) Format {
    return Format.from_u8(u);
}

pub const Format = union(enum) {
    positive_fix_int: u8,
    fix_map: u8,
    fix_array: u8,
    fix_str: u8,
    nil,
    never_used,
    bool_false,
    bool_true,
    bin8,
    bin16,
    bin32,
    ext8,
    ext16,
    ext32,
    float32,
    float64,
    uint8,
    uint16,
    uint32,
    uint64,
    int8,
    int16,
    int32,
    int64,
    fix_ext1,
    fix_ext2,
    fix_ext4,
    fix_ext8,
    fix_ext16,
    str8,
    str16,
    str32,
    array16,
    array32,
    map16,
    map32,
    negative_fix_int: i8,

    pub fn from_u8(f: u8) Format {
        if (f >= 0x00 and f <= 0x7f) {
            return .{ .positive_fix_int = f };
        } else if (f >= 0x80 and f <= 0x8f) {
            return .{ .fix_map = f & FIXMAP_SIZE };
        } else if (f >= 0x90 and f <= 0x9f) {
            return .{ .fix_array = f & FIXARRAY_SIZE };
        } else if (f >= 0xa0 and f <= 0xbf) {
            return .{ .fix_str = f & FIXSTR_SIZE };
        } else if (f >= 0xe0 and f <= 0xff) {
            var sl = [1]u8{f};
            return .{ .negative_fix_int = std.mem.readIntSliceBig(i8, sl[0..]) };
        }

        return switch (f) {
            0xc0 => .nil,
            0xc1 => .never_used,
            0xc2 => .bool_false,
            0xc3 => .bool_true,
            0xc4 => .bin8,
            0xc5 => .bin16,
            0xc6 => .bin32,
            0xc7 => .ext8,
            0xc8 => .ext16,
            0xc9 => .ext32,
            0xca => .float32,
            0xcb => .float64,
            0xcc => .uint8,
            0xcd => .uint16,
            0xce => .uint32,
            0xcf => .uint64,
            0xd0 => .int8,
            0xd1 => .int16,
            0xd2 => .int32,
            0xd3 => .int64,
            0xd4 => .fix_ext1,
            0xd5 => .fix_ext2,
            0xd6 => .fix_ext4,
            0xd7 => .fix_ext8,
            0xd8 => .fix_ext16,
            0xd9 => .str8,
            0xda => .str16,
            0xdb => .str32,
            0xdc => .array16,
            0xdd => .array32,
            0xde => .map16,
            0xdf => .map32,
            else => unreachable,
        };
    }

    pub fn to_u8(f: Format) u8 {
        return switch (f) {
            .positive_fix_int => |u| u,
            .fix_map => |u| u,
            .fix_array => |u| u,
            .fix_str => |u| u,
            .nil => 0xc0,
            .never_used => 0xc1,
            .bool_false => 0xc2,
            .bool_true => 0xc3,
            .bin8 => 0xc4,
            .bin16 => 0xc5,
            .bin32 => 0xc6,
            .ext8 => 0xc7,
            .ext16 => 0xc8,
            .ext32 => 0xc9,
            .float32 => 0xca,
            .float64 => 0xcb,
            .uint8 => 0xcc,
            .uint16 => 0xcd,
            .uint32 => 0xce,
            .uint64 => 0xcf,
            .int8 => 0xd0,
            .int16 => 0xd1,
            .int32 => 0xd2,
            .int64 => 0xd3,
            .fix_ext1 => 0xd4,
            .fix_ext2 => 0xd5,
            .fix_ext4 => 0xd6,
            .fix_ext8 => 0xd7,
            .fix_ext16 => 0xd8,
            .str8 => 0xd9,
            .str16 => 0xda,
            .str32 => 0xdb,
            .array16 => 0xdc,
            .array32 => 0xdd,
            .map16 => 0xde,
            .map32 => 0xdf,
            .negative_fix_int => |u| @intCast(u8, u),
        };
    }
};
