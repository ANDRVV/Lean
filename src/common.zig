const std = @import("std");

pub fn DeepClone(
    allocator: std.mem.Allocator,
    comptime T: type,
    src: std.ArrayList([]T)
) !std.ArrayListAligned([]T, null) {
    var result = std.ArrayList([]T).init(allocator);
    for (src.items) |row| {
        const newRow = try allocator.alloc(T, row.len);
        for (row, 0..) |item, i| {
            newRow[i] = item;
        }
        try result.append(newRow);
    }
    return result;
}

pub inline fn EqualCheck(
    T: type,
    mat1: []const []const T,
    mat2: []const []const T
) bool {
    return mat1.len == mat2.len and mat1[0].len == mat2[0].len;
}