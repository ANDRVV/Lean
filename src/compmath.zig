// Copyright (c) 2024 Andrea Vaccaro
//
// This file is part of lean, which is MIT licensed.
// See http://opensource.org/licenses/MIT

const std = @import("std");
const Operations = @import("leansrc.zig").Operations;
const Devices = @import("leansrc.zig").Devices;

inline fn GetCompFunc(comptime T: type, comptime mode: Devices, comptime operation: Operations) fn (comptime type, T, T) callconv(.Inline) T {
    // Select the CPU class to use based on the safeMode.
    const deviceMode: type = switch (mode) {
        .SingleThreaded => |st_mode| switch (st_mode) {
            .FastCPU => FastCPUDevice,
            .FixedCPU => FixedCPUDevice,
            .SafeCPU => SafeCPUDevice
        },

        .MultiThreaded => |mt_mode| switch (mt_mode) {
            .FastCPU => FastCPUDevice,
            .FixedCPU => FixedCPUDevice,
            .SafeCPU => SafeCPUDevice
        }
    };

    // Select the operation to perform calculation.
    return switch (operation) {
        Operations.Add => deviceMode.Add,
        Operations.Sub => deviceMode.Sub,
        Operations.Mul => deviceMode.Mul,
        Operations.Div => deviceMode.Div,
    };
}  

/// CPUProcST is a function that performs matrix basic operations on the CPU without threads.
pub fn CPUProcST(
    comptime T: type,
    comptime operation: Operations,
    comptime mode: Devices,
    allocator: std.mem.Allocator,
    mat1: []const []T,
    mat2: []const []const T
) ![][]T {
    comptime {
        const isFastMode: bool = switch (mode) {
            .SingleThreaded => mode.SingleThreaded,
            .MultiThreaded => mode.MultiThreaded
        } == .FastCPU;

        if (isFastMode) {
            // Disable runtime safety on this block to increase performance.
            @setRuntimeSafety(false);
            // Set the floating point mode to hint to the LLVM
            // to optimize the calculation removing the overhead.
            @setFloatMode(.optimized);
        }
    }

    // Get the operation to perform calculation.
    const calcFunc: fn (comptime type, T, T) callconv(.Inline) T = comptime GetCompFunc(T, mode, operation);

    const rows: usize = mat1.len;
    const columns: usize = mat1[0].len;
    if (rows != mat2.len or columns != mat2[0].len) return error.UnmatchedScheme;

    // Preallocate the memory for the new matrix.
    const matrix: [][]T = try allocator.alloc([]T, rows);
    errdefer allocator.free(matrix);

    for (0..rows) |rowIndex| {
        // Get the row of the matrix
        var matrixAR: []T = matrix[rowIndex];

        // Add capacity to a row with a chunk
        matrixAR = try allocator.alloc(T, columns);
        errdefer {
            allocator.free(matrix);
            allocator.free(matrixAR);
        }
        
        // Get alias of the row of the mat1 and mat2
        const mat1AR: []T = mat1[rowIndex];
        const mat2AR: []const T = mat2[rowIndex];

        for (0..columns) |columnIndex| {
            // Calculate and substitute the calculed value in the matrix.
            matrixAR[columnIndex] = calcFunc(
                T,
                mat1AR[columnIndex],
                mat2AR[columnIndex]
            );
        }
    }
    
    return matrix;
}

/// SafeCPUDevice is a struct that contains CPU operations with safe mode.
pub const SafeCPUDevice = struct {

    /// Add is a function that adds two values with overflow checking.
    pub inline fn Add(comptime T: type, a: T, b: T) T { 
        const v: T, const ov: u1 = @addWithOverflow(a, b);
        if (ov == 0) return v else @panic("Add overflow.");
    }

    /// Sub is a function that subtracts two values with overflow checking.
    pub inline fn Sub(comptime T: type, a: T, b: T) T { 
        const v: T, const ov: u1 = @subWithOverflow(a, b);
        if (ov == 0) return v else @panic("Sub overflow.");
    }

    /// Mul is a function that multiplies two values with overflow checking.
    pub inline fn Mul(comptime T: type, a: T, b: T) T {
        const v: T, const ov: u1 = @mulWithOverflow(a, b);
        if (ov == 0) return v else @panic("Mul overflow.");
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

/// FastCPUDevice is a struct that contains CPU operations with fixed mode.
pub const FixedCPUDevice = struct {

    /// Add is a function that adds two values: return not-added value if there is an error.
    pub inline fn Add(comptime T: type, a: T, b: T) T { 
        const v: T, const ov: u1 = @addWithOverflow(a, b);
        return if (ov == 0) v else a;
    }

    /// Sub is a function that subtracts two values: return not-subtracted value if there is an error.
    pub inline fn Sub(comptime T: type, a: T, b: T) T { 
        const v: T, const ov: u1 = @subWithOverflow(a, b);
        return if (ov == 0) v else a;
    }

    /// Mul is a function that multiplies two values: return not-multiplied value if there is an error.
    pub inline fn Mul(comptime T: type, a: T, b: T) T {
        const v: T, const ov: u1 = @mulWithOverflow(a, b);
        return if (ov == 0) v else a;
    }

    /// Div is a function that divides two values: return not-divided value if there is an error.
    pub const Div = FastCPUDevice.Div;
};