const std = @import("std");
const Operations = @import("leansrc.zig").Operations;

pub fn CPUProc(
    comptime T: type,
    comptime operation: Operations,
    comptime safeMode: bool,
    allocator: std.mem.Allocator,
    mat1: []const []const T,
    mat2: []const []const T
) ![][]T {
    @setRuntimeSafety(false);
    @setFloatMode(.optimized);

    const rows: usize = mat1.len;
    const columns: usize = mat1[0].len;
    if (rows != mat2.len or columns != mat2[0].len) return error.UnmatchedScheme;

    const deviceMode: type = comptime if (safeMode) SafeCPUDevice else FastCPUDevice;
    const calcFunc: fn (comptime type, T, T) callconv(.Inline) T = comptime switch (operation) {
        Operations.Add => deviceMode.Add,
        Operations.Sub => deviceMode.Sub,
        Operations.Mul => deviceMode.Mul,
        Operations.Div => deviceMode.Div,
    };

    var matrix: [][]T = try allocator.alloc([]T, rows);
    errdefer allocator.free(matrix);

    var rowsfield: []T = try allocator.alloc(T, rows * columns);
    errdefer allocator.free(rowsfield);

    for (0..rows) |rowIndex| {
        matrix[rowIndex] = rowsfield[
            rowIndex * columns..
            rowIndex * columns + columns
        ];

        for (0..columns) |columnIndex| {
            matrix[rowIndex][columnIndex] = calcFunc(
                T,
                mat1[rowIndex][columnIndex],
                mat2[rowIndex][columnIndex]
            );
        }
    }

    return matrix;
}

pub const SafeCPUDevice = struct {
    pub inline fn Add(comptime T: type, a: T, b: T) T { 
        if (T == comptime_int) return a + b;
        const ov = @addWithOverflow(a, b);
        if (ov[1] == 0) return ov[0] else @panic("Add overflow.");
    }
    pub inline fn Sub(comptime T: type, a: T, b: T) T { 
        if (T == comptime_int) return a - b;
        const ov = @subWithOverflow(a, b);
        if (ov[1] == 0) return ov[0] else @panic("Sub overflow.");
    }
    pub inline fn Mul(comptime T: type, a: T, b: T) T {
        if (T == comptime_int) return a * b;
        const ov = @mulWithOverflow(a, b);
        if (ov[1] == 0) return ov[0] else @panic("Mul overflow.");
    }
    pub inline fn Div(comptime T: type, a: T, b: T) T {
        if (b == 0) @panic("Division by zero error.");
        return if (@typeInfo(T) == .Float) a / b else (a + b / 2) / b;
    }
};

pub const FastCPUDevice = struct {
    pub inline fn Add(comptime T: type, a: T, b: T) T { return a +| b; }
    pub inline fn Sub(comptime T: type, a: T, b: T) T { return a -| b; }
    pub inline fn Mul(comptime T: type, a: T, b: T) T { return a *| b; }
    pub inline fn Div(comptime T: type, a: T, b: T) T { return if (b == 0) a else a / b; }
};