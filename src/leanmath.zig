const std = @import("std");
const Devices = @import("leansrc.zig").Devices;
const stdlean = @import("common.zig");

pub fn CPUComputing(arena: std.heap.ArenaAllocator, comptime T: type) type {
    return struct {
        pub inline fn Add(
            mat1: []const []const T,
            mat2: []const []const T
        ) ![]const []const T {
            return try CalcAlg(
                mat1, 
                mat2, 
                std.math.add
            );
        }

        pub inline fn Sub(
            mat1: []const []const T,
            mat2: []const []const T
        ) ![]const []const T {
            return try CalcAlg(
                mat1, 
                mat2, 
                std.math.sub
            );
        }

        pub inline fn Mul(
            mat1: []const []const T,
            mat2: []const []const T
        ) ![]const []const T {
            return try CalcAlg(
                mat1, 
                mat2, 
                std.math.mul
            );
        }

        pub inline fn Div(
            mat1: []const []const T,
            mat2: []const []const T
        ) ![]const []const T {
            const div = struct {
                fn func(a: T, b: T) T {
                    return if (@typeInfo(T) == .Float) {
                        a / b;
                    } else {
                        (a + b / 2) / b;
                    };
                }
            };

            return try CalcAlg(
                mat1, 
                mat2, 
                div.func
            );
        }

        fn CalcAlg(
            mat1: []const []const T,
            mat2: []const []const T,
            calcFunc: fn(comptime T: type, a: T, b: T) (error{Overflow}!T)
        ) ![]const []const T {
            if (!stdlean.EqualCheck(T, mat1, mat2)) return error.UnmatchedScheme;

            var matrix = std.ArrayList([]T).init(arena.allocator());

            for (mat1) |row| {
                var column = try arena.allocator().alloc(T, row.len);
                for (0..row.len) |itemIndex| {
                    column[itemIndex] = try calcFunc(
                        T, 
                        mat1[itemIndex], 
                        mat2[itemIndex]
                    );
                }
                matrix.append(column);
            }
        }
    };
}
