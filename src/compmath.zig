const std = @import("std");
const Operations = @import("leansrc.zig").Operations;

/// CPUProc is a function that performs matrix basic operations on the CPU.
pub fn CPUProc(
    comptime T: type,
    comptime operation: Operations,
    comptime safeMode: bool,
    allocator: std.mem.Allocator,
    mat1: []const []const T,
    mat2: []const []const T
) ![][]T {
    // Disable runtime safety on this block to increase performance.
    @setRuntimeSafety(false);
    // Set the floating point mode to hint to the LLVM
    // to optimize the calculation removing the overhead.
    @setFloatMode(.optimized);

    const rows: usize = mat1.len;
    const columns: usize = mat1[0].len;
    if (rows != mat2.len or columns != mat2[0].len) return error.UnmatchedScheme;

    // Select the CPU class to use based on the safeMode.
    const deviceMode: type = comptime if (safeMode) SafeCPUDevice else FastCPUDevice;
    // Select the operation to perform based on the operation.
    const calcFunc: fn (comptime type, T, T) callconv(.Inline) T = comptime switch (operation) {
        Operations.Add => deviceMode.Add,
        Operations.Sub => deviceMode.Sub,
        Operations.Mul => deviceMode.Mul,
        Operations.Div => deviceMode.Div,
    };

    // Preallocate the memory for the new matrix.
    var matrix: [][]T = try allocator.alloc([]T, rows);
    errdefer allocator.free(matrix);

    // Preallocate the memory for the rows field.
    var rowsfield: []T = try allocator.alloc(T, rows * columns);
    errdefer allocator.free(rowsfield);

    for (0..rows) |rowIndex| {
        // Add capacity to a row with a chunk
        matrix[rowIndex] = rowsfield[
            rowIndex * columns..
            rowIndex * columns + columns
        ];

        for (0..columns) |columnIndex| {
            // Calculate and substitute the calculed value in the matrix.
            matrix[rowIndex][columnIndex] = calcFunc(
                T,
                mat1[rowIndex][columnIndex],
                mat2[rowIndex][columnIndex]
            );
        }
    }

    return matrix;
}

/// SafeCPUDevice is a struct that contains CPU operations with safe mode.
pub const SafeCPUDevice = struct {
    /// Add is a function that adds two values with overflow checking.
    pub inline fn Add(comptime T: type, a: T, b: T) T { 
        if (T == comptime_int) return a + b;
        const ov = @addWithOverflow(a, b);
        if (ov[1] == 0) return ov[0] else @panic("Add overflow.");
    }

    /// Sub is a function that subtracts two values with overflow checking.
    pub inline fn Sub(comptime T: type, a: T, b: T) T { 
        if (T == comptime_int) return a - b;
        const ov = @subWithOverflow(a, b);
        if (ov[1] == 0) return ov[0] else @panic("Sub overflow.");
    }

    /// Mul is a function that multiplies two values with overflow checking.
    pub inline fn Mul(comptime T: type, a: T, b: T) T {
        if (T == comptime_int) return a * b;
        const ov = @mulWithOverflow(a, b);
        if (ov[1] == 0) return ov[0] else @panic("Mul overflow.");
    }

    /// Div is a function that divides two values with division by zero checking and type match.
    pub inline fn Div(comptime T: type, a: T, b: T) T {
        if (b == 0) @panic("Division by zero error.");
        return if (@typeInfo(T) == .Float) a / b else (a + b / 2) / b;
    }
};

/// FastCPUDevice is a struct that contains CPU operations with fast mode.
pub const FastCPUDevice = struct {
    /// Add is a function that make wrapping addition.
    pub inline fn Add(comptime T: type, a: T, b: T) T { return a +| b; }

    /// Sub is a function that make wrapping subtraction.
    pub inline fn Sub(comptime T: type, a: T, b: T) T { return a -| b; }

    /// Mul is a function that make wrapping multiplication.
    pub inline fn Mul(comptime T: type, a: T, b: T) T { return a *| b; }
    
    /// Div is a function that divides 2 values if b is not equal to 0, else return the undivided value.
    pub inline fn Div(comptime T: type, a: T, b: T) T { return if (b == 0) a else a / b; }
};