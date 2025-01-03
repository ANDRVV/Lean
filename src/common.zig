// Copyright (c) 2025 Andrea Vaccaro
//
// This file is part of Lean, which is MIT licensed.
// See http://opensource.org/licenses/MIT

const std = @import("std");

pub fn DeepClone(
    comptime T: type,
    allocator: std.mem.Allocator,
    matrix: []const []const T
) ![][]T {
    const rows = matrix.len;
    const columns = matrix[0].len;

    const newMatrix: [][]T = try allocator.alloc([]T, rows);
    errdefer allocator.free(newMatrix);

    for (0..rows) |rowIndex| {
        newMatrix[rowIndex] = try allocator.alloc(T, columns);
        errdefer {
            allocator.free(newMatrix);
            allocator.free(newMatrix[rowIndex]);
        }

        for (0..columns) |columnIndex| {
            newMatrix[rowIndex][columnIndex] = matrix[rowIndex][columnIndex];
        }
    }

    return newMatrix;
}

pub fn GenMatrixWithScheme(
    comptime T: type,
    allocator: std.mem.Allocator,
    rows: usize,
    columns: usize
) ![][]T {
    const matrix: [][]T = try allocator.alloc([]T, rows);
    errdefer allocator.free(matrix);

    for (0..rows) |rowIndex| {
        // Add capacity to a row with a chunk
        matrix[rowIndex] = try allocator.alloc(T, columns);
        errdefer {
            allocator.free(matrix);
            allocator.free(matrix[rowIndex]);
        }

        for (0..columns) |columnIndex| {
            matrix[rowIndex][columnIndex] = 0;
        }
    }

    return matrix;
}

pub fn GenIdentityMatrix(
    comptime T: type,
    allocator: std.mem.Allocator,
    rows: usize,
    columns: usize
) ![][]T {
    const matrix: [][]T = try GenMatrixWithScheme(T, allocator, rows, columns);

    for (0..rows) |rowIndex| {
        for (0..columns) |columnIndex| {
            if (rowIndex == columnIndex) matrix[rowIndex][columnIndex] = 1;
        }
    }

    return matrix;
}

pub fn GetOptimalCapacity(cap: usize) usize {
    var new: usize = cap;
    while (new <= cap) new +|= new / 2 + 8;
    return new;
}

pub fn isUnsigned(comptime T: type) bool {
    return switch (@typeInfo(T)) {
       .Int => |i| i.signedness == .unsigned,
       .Float => false,
       else => @compileError("Invalid type."),
    };
}