// Copyright (c) 2024 Andrea Vaccaro
//
// This file is part of lean, which is MIT licensed.
// See http://opensource.org/licenses/MIT

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

pub fn GetOptimalCapacity(cap: usize) usize {
    var new: usize = cap;
    while (new <= cap) new +|= new / 2 + 8;
    return new;
}