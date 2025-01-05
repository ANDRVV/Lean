// Copyright (c) 2025 Andrea Vaccaro
//
// This file is part of Lean, which is MIT licensed.
// See http://opensource.org/licenses/MIT

const std = @import("std");
const stdlean = @import("common.zig");
const Operations = @import("leansrc.zig").Operations;
const Devices = @import("leansrc.zig").Devices;

pub inline fn GetCompFunc(
    comptime T: type,
    comptime mode: Devices,
    comptime operation: Operations
) fn (T, T) callconv(.Inline) T {
    // Select the CPU class to use based on the safeMode.
    const deviceMode: type = switch (mode) {
        .SingleThreaded => |st_mode| switch (st_mode) {
            .FastCPU => FastCPUDevice(T),
            .FixedCPU => FixedCPUDevice(T),
            .SafeCPU => SafeCPUDevice(T)
        },

        .MultiThreaded => |mt_mode| switch (mt_mode) {
            .FastCPU => FastCPUDevice(T),
            .FixedCPU => FixedCPUDevice(T),
            .SafeCPU => SafeCPUDevice(T)
        }
    };

    // Select the operation to perform calculation.
    return switch (operation) {
        Operations.Add => deviceMode.Add,
        Operations.Sub => deviceMode.Sub,
        Operations.Mul => deviceMode.Mul,
        Operations.Div => deviceMode.Div,
        Operations.Pow => deviceMode.Pow
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
        if (operation == Operations.Pow) return error.OperationNotSupported;

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
    const calcFunc: fn (T, T) callconv(.Inline) T = comptime GetCompFunc(T, mode, operation);

    const rows: usize = mat1.len;
    const columns: usize = mat1[0].len;

    // Preallocate the memory for the new matrix.
    const matrix: [][]T = try stdlean.GenMatrixWithScheme(T, allocator, rows, columns);

    for (0..rows) |rowIndex| {
        
        // Get alias of the row of the mat1 and mat2
        const mat1AR: []T = mat1[rowIndex];
        const mat2AR: []const T = mat2[rowIndex];

        for (0..columns) |columnIndex| {
            // Calculate and substitute the calculed value in the matrix.
            matrix[rowIndex][columnIndex] = calcFunc(
                mat1AR[columnIndex],
                mat2AR[columnIndex]
            );
        }
    }
    
    return matrix;
}

/// SafeCPUDevice is a struct that contains CPU operations with safe mode.
pub fn SafeCPUDevice(comptime T: type) type {
    return struct {
        /// Add is a function that adds two values with overflow checking.
        pub inline fn Add(a: T, b: T) T {
            if (comptime isFloat(T) ) {
                const r = a + b;
                if (isValid(r)) return r else @panic("Overflow or invalid result.");
            } else {
                const v: T, const ov: u1 = @addWithOverflow(a, b);
                if (ov == 0) return v else @panic("Add overflow.");
            }
        }

        /// Sub is a function that subtracts two values with overflow checking.
        pub inline fn Sub(a: T, b: T) T {
            if (comptime isFloat(T) ) {
                const r = a - b;
                if (isValid(r)) return r else @panic("Overflow or invalid result.");
            } else {
                const v: T, const ov: u1 = @subWithOverflow(a, b);
                if (ov == 0) return v else @panic("Sub overflow.");
            }
        }

        /// Mul is a function that multiplies two values with overflow checking.
        pub inline fn Mul(a: T, b: T) T {
            if (comptime isFloat(T) ) {
                const r = a * b;
                if (isValid(r)) return r else @panic("Overflow or invalid result.");
            } else {
                const v: T, const ov: u1 = @mulWithOverflow(a, b);
                if (ov == 0) return v else @panic("Mul overflow.");
            }
        }

        /// Div is a function that divides two values with division by zero checking and type match.
        pub inline fn Div(a: T, b: T) T {
            if (b == 0) @panic("Division by zero error.");
            if (comptime isFloat(T) ) {
                const r = a / b;
                if (isValid(r)) return r else @panic("Invalid result.");
            } else return @divFloor(a, b);
        }

        /// Pow is a function that calculates the power of a value.
        pub const Pow: fn (a: T, b: T) callconv(.Inline) T = GenericOperations(T, false).Pow;
    };
}

/// FastCPUDevice is a struct that contains CPU operations with fast mode.
pub fn FastCPUDevice(comptime T: type) type {
    return struct {
        /// Add is a function that make wrapping addition.
        pub inline fn Add(a: T, b: T) T { return a + b; }

        /// Sub is a function that make wrapping subtraction.
        pub inline fn Sub(a: T, b: T) T { return a - b; }

        /// Mul is a function that make wrapping multiplication.
        pub inline fn Mul(a: T, b: T) T { return a * b; }
        
        /// Div is a function that divides 2 values if b is not equal to 0, else return the undivided value.
        pub inline fn Div(a: T, b: T) T { return a / b; }

        /// Pow is a function that calculates the power of a value.
        pub const Pow: fn (a: T, b: T) callconv(.Inline) T = GenericOperations(T, true).Pow;
    };
}

/// FastCPUDevice is a struct that contains CPU operations with fixed mode.
pub fn FixedCPUDevice(comptime T: type) type {
    return struct {
        /// Add is a function that adds two values: return not-added value if there is an error.
        pub inline fn Add(a: T, b: T) T { 
            if (comptime isFloat(T) ) {
                const r = a + b;
                return if (isValid(r)) r else a;
            } else {
                const v: T, const ov: u1 = @addWithOverflow(a, b);
                return if (ov == 0) v else a;
            }
        }

        /// Sub is a function that subtracts two values: return not-subtracted value if there is an error.
        pub inline fn Sub(a: T, b: T) T { 
            if (comptime isFloat(T) ) {
                const r = a - b;
                return if (isValid(r)) r else a;
            } else {
                const v: T, const ov: u1 = @subWithOverflow(a, b);
                return if (ov == 0) v else a;
            }
        }

        /// Mul is a function that multiplies two values: return not-multiplied value if there is an error.
        pub inline fn Mul(a: T, b: T) T {
            if (comptime isFloat(T) ) {
                const r = a * b;
                return if (isValid(r)) r else a;
            } else {
                const v: T, const ov: u1 = @mulWithOverflow(a, b);
                return if (ov == 0) v else a;
            }
        }

        /// Div is a function that divides two values: return not-divided value if there is an error.
        pub const Div: fn (a: T, b: T) callconv(.Inline) T = FastCPUDevice(T).Div;

        /// Pow is a function that calculates the power of a value.
        pub const Pow: fn (a: T, b: T) callconv(.Inline) T = GenericOperations(T, false).Pow;
    };
}

inline fn isFloat(comptime T: type) bool {
    return @typeInfo(T) == std.builtin.Type.Float;
}

inline fn isValid(x: anytype) bool {
    return !(std.math.isNan(x) or std.math.isInf(x));
}

fn GenericOperations(comptime T: type, comptime isFastMode: bool) type {
    return struct {
        inline fn Pow(a: T, b: T) T {
            comptime if (isFastMode) {
                // Disable runtime safety on this block to increase performance.
                @setRuntimeSafety(false);
                // Set the floating point mode to hint to the LLVM
                // to optimize the calculation removing the overhead.
                @setFloatMode(.optimized);
            };

            if (b == 0 or a == 1) return 1;
            if (a == 0) return 0;
            if (b == 1) return a;
            if (b == 2) return a * a;

            if (comptime isFloat(T)) {
                if (b == 0.5) return @sqrt(a);

                return std.math.pow(T, a, b);
            }

            return std.math.powi(T, a, b) catch unreachable;
        }
    };
}