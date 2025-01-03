// Copyright (c) 2025 Andrea Vaccaro
//
// This file is part of Lean, which is MIT licensed.
// See http://opensource.org/licenses/MIT

const std = @import("std");
const leansrc = @import("../leansrc.zig");
const compdev = @import("../compmath.zig");
const stdlean = @import("../common.zig");
const Devices = leansrc.Devices;
const Operations = leansrc.Operations;

pub fn Linalg(comptime T: type, comptime compdevice: Devices) type {
    return struct {
        const Self = @This();
        const device: Devices = compdevice;

        allocator: std.mem.Allocator,

        const ModuleAdd: fn (T, T) callconv(.Inline) T = compdev.GetCompFunc(T, device, Operations.Add);
        const ModuleSub: fn (T, T) callconv(.Inline) T = compdev.GetCompFunc(T, device, Operations.Sub);
        const ModuleMul: fn (T, T) callconv(.Inline) T = compdev.GetCompFunc(T, device, Operations.Mul);
        const ModuleDiv: fn (T, T) callconv(.Inline) T = compdev.GetCompFunc(T, device, Operations.Div);
        const ModulePow: fn (T, T) callconv(.Inline) T = compdev.GetCompFunc(T, device, Operations.Pow);

        /// Check if the matrix is square.
        inline fn isSquare(mat: []const []const T) bool { return mat.len == mat[0].len; }
        /// Check if 2 matrix have the same scheme.
        inline fn hasSameScheme(mat1: []const []const T, mat2: []const []const T) bool {
            return mat1.len == mat2.len and mat1[0].len == mat2[0].len;
        }

        // Perform matrix linear-algebra multiplication
        pub fn Matmul(self: *Self, mat1: []const []const T, mat2: []const []const T) ![][]T {
            if (!hasSameScheme(mat1, mat2)) return error.UnmatchedScheme;

            const mat1rows = mat1.len;
            const mat1columns = mat1[0].len;
            const mat2columns = mat2[0].len;

            const newMatrix: [][]T = try stdlean.DeepClone(T, self.allocator, mat1);

            for (0..mat1rows) |rowIndex| {
                for (0..mat2columns) |columnIndex| {
                    var sum: T = 0;
                    for (0..mat1columns) |k| {
                        const prod = ModuleMul(
                            mat1[rowIndex][k],
                            mat2[k][columnIndex]
                        );

                        sum = ModuleAdd(sum, prod);
                    }
                    newMatrix[rowIndex][columnIndex] = sum;
                }
            }

            return newMatrix;
        }

        /// Perform scalar operation with a specific operation
        pub fn Scalar(self: *Self, mat: []const []const T, comptime op: Operations, scalar: T) ![][]T {
            const rows = mat.len;
            const columns = mat[0].len;

            var newMatrix: [][]T = try stdlean.DeepClone(T, self.allocator, mat);

            if (op == Operations.Pow) {
                if (@typeInfo(scalar) == .Float) return error.OperationNotSupported;
                if (scalar == 1) return newMatrix;

                if (scalar == 0) {
                    if (!isSquare(mat)) return error.NonSquareMatrix;
                    return try stdlean.GenIdentityMatrix(T, self.allocator, rows, columns);
                }

                if (scalar < 0) newMatrix = try self.Inverse(mat);
                    
                for (1..@abs(scalar)) |_| newMatrix = try self.Matmul(newMatrix, mat);

                return newMatrix;
            }

            const module: fn (T, T) callconv(.Inline) T = comptime switch (op) {
                Operations.Add => ModuleAdd,
                Operations.Sub => ModuleSub,
                Operations.Mul => ModuleMul,
                Operations.Div => ModuleDiv,

                else => {}
            };

            for (0..rows) |rowIndex| {
                for (0..columns) |columnIndex| {
                    newMatrix[rowIndex][columnIndex] = module(
                        mat[rowIndex][columnIndex],
                        scalar
                    );
                }
            }

            return newMatrix;
        }

        // Private function: raw determinant function
        fn _det(self: *Self, mat: []const []const T) T {
            comptime if (stdlean.isUnsigned(T)) @compileError("Operation not permitted.");

            const matRows = mat.len;

            if (matRows == 2) return mat[0][0] * mat[1][1] - mat[0][1] * mat[1][0];
            
            var det: T = 0;
            for (0..matRows) |coefIndex| {
                const exp = ModuleMul(
                    mat[0][coefIndex],
                    self.Cofactor(mat, 0, coefIndex) catch unreachable
                );

                det = ModuleAdd(det, exp);
            }

            return det;
        }

        // Get specific cofactor of matrix
        pub fn Cofactor(self: *Self, mat: []const []const T, row: usize, column: usize) !T {
            comptime if (stdlean.isUnsigned(T)) @compileError("Operation not permitted.");

            const matRows = mat.len;
            const matColumns = mat[0].len;

            if (row >= matRows) return error.RowOutOfRange;
            if (column >= matColumns) return error.ColumnOutOfRange;

            var subMatrix = stdlean.GenMatrixWithScheme(
                T, 
                self.allocator, 
                matRows - 1, 
                matColumns - 1
            ) catch unreachable;

            var i: usize = 0;
            var j: usize = 0;
            for (0..matRows) |r| {
                if (r == row) continue;

                j = 0;
                for (0..matColumns) |c| {
                    if (c == column) continue;

                    subMatrix[i][j] = mat[r][c];
                    j += 1;
                }
                i += 1;
            }

            const sign: T = if ((row + column) % 2 == 0) 1 else -1;
            return ModuleMul(
                sign,
                self._det(subMatrix)
            );
        }

        // Get determinant of matrix
        pub fn Determinant(self: *Self, mat: []const []const T) !T {
            return if (!isSquare(mat)) error.NonSquareMatrix else self._det(mat);
        }

        // Get inverse of matrix
        pub fn Inverse(self: *Self, mat: []const []const T) ![][]T {
            const det = try self.Determinant(mat);
            if (det == 0) return error.DeterminantEqualToZero;

            const rows = mat.len;
            const columns = mat[0].len;

            var adjMatrix: [][]T = try stdlean.GenMatrixWithScheme(
                T,
                self.allocator,
                rows,
                columns
            );
            
            if (rows == 2) {
                adjMatrix[0][0] = mat[1][1];
                adjMatrix[1][0] = -mat[1][0];
                adjMatrix[0][1] = -mat[0][1];
                adjMatrix[1][1] = mat[0][0];
            } else {
               for (0..rows) |rowIndex| {
                    for (0..columns) |columnIndex| {
                        adjMatrix[columnIndex][rowIndex] = self.Cofactor(
                            mat,
                            rowIndex,
                            columnIndex
                        );
                    }
                } 
            }

            return try self.Scalar(
                adjMatrix,
                Operations.Mul,
                ModuleDiv(1, det)
            );
        }

        /// Get transpose of matrix
        pub fn Transpose(self: *Self, mat: []const []const T) ![][]T {
            const matrixCopy: [][]T = try stdlean.DeepClone(T, self.allocator, mat);

            const rows = mat.len;
            const columns = mat[0].len;

            for (0..rows) |rowIndex| {
                for (0..columns) |columnIndex| {
                    matrixCopy[columnIndex][rowIndex] = mat[rowIndex][columnIndex];
                }
            }

            return matrixCopy;
        }
    };
}