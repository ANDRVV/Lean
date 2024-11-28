const std = @import("std");

/// ArenaAllocator: fastest allocation for small allocations
const ArenaAllocator = std.heap.ArenaAllocator; 

pub const LeanErrors = error {
    SetAllocationFailure,
    GetItemNotFound,
    WrongMatrixScheme,
    ColumnOutOfRange,
    RowOutOfRange,
    UnitializedMatrix,
    UnmatchedScheme
};

/// Use Lean on custom numeric type
pub fn BasedValue(comptime T: type) type {
    return struct {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        var matrix = std.ArrayList([]T).init(arena.allocator());

        pub inline fn rows() usize { return matrix.items.len; }
        pub inline fn columns() usize { return matrix.items[0].len; }
        pub inline fn scheme() [2]usize { return .{matrix.items[0].len, matrix.items.len}; }
        pub inline fn size() usize { return matrix.items[0].len * matrix.items.len; }
        pub inline fn content() [][]T { return matrix.items; }

        /// Set 2D Array
        pub fn Set(comptime mat: []const []const T) !void {
            const rowlen = mat[0].len;
            for (mat[1..]) |slice| if (slice.len != rowlen) return error.WrongMatrixScheme;

            Destroy();

            try matrix.ensureTotalCapacity(mat.len);

            for (mat) |slice| {
                const newRow = try arena.allocator().dupe(T, slice);
                matrix.append(newRow) catch return error.SetAllocationFailure;
            }
        }

        /// Gets a value from index
        pub fn Get(comptime column: usize, comptime row: usize) !T {
            if (row >= rows() or column >= columns())
                return error.GetItemNotFound;
            return matrix.items[row][column];
        }

        /// Join as a single list
        pub fn AsArray() ![]T {
            var marray = try arena.allocator().alloc(T, size());
            var i: usize = 0;
            for (matrix.items) |slice| {
                for (slice) |value| {
                    marray[i] = value;
                    i += 1;
                }
            }
            return marray;
        }

        /// Adds a row
        pub inline fn AddRow(row: []const T) !void {
            const mutable = try arena.allocator().dupe(T, row);
            try matrix.append(mutable);
        }

        /// Adds a column
        pub fn AddColumn(column: []const T) !void {
            if (rows() != column.len) return error.UnmatchedScheme;
            
            const rowLength = columns();

            for (column, 0..) |value, i| {
                const updated = try arena.allocator().alloc(T, rowLength + 1);
                @memcpy(updated[0..rowLength], matrix.items[i]);
                updated[rowLength] = value;
                matrix.items[i] = updated;
            }
        }

        /// Convert linear index as coordinates (x, y)
        pub inline fn IndexAsCoordinates(comptime index: usize) ![2]usize {
            return .{index / columns(), index % columns()};
        }

        /// Gets x, y of max value
        pub inline fn MaxCoordinates() ![2]usize {
            const marray = try AsArray();
            const index = std.mem.indexOfMax(T, marray);
            return IndexAsCoordinates(index);
        }

        /// Gets x, y of min value
        pub inline fn MinCoordinates() ![2]usize {
            const marray = try AsArray();
            const index = std.mem.indexOfMin(T, marray);
            return IndexAsCoordinates(index);
        }

        /// Gets max value
        pub inline fn Max() !T {
            const marray = try AsArray();
            return std.mem.max(T, marray);
        }

        /// Gets min value
        pub inline fn Min() !T {
            const marray = try AsArray();
            return std.mem.min(T, marray);
        }

        /// Return the sum of all values
        pub inline fn Sum() !usize {
            return Map( 
                struct {
                    fn f(a: usize, b: usize) usize { return a + b; }
                }.f
            );
        }

        /// Return the product of all values
        pub inline fn Prod() !usize {
            return Map( 
                struct {
                    fn f(a: usize, b: usize) usize { return a * b; }
                }.f
            );
        }

        /// Return the result of all operations among all values
        pub fn Map(transformer: fn (usize, usize) usize) !usize {
            const marray = try AsArray();
            
            var res: usize = 0;
            for (marray) |value| {
                res = transformer(res, value);
            }
            return res;
        }

        /// Concatenate with another matrix
        pub fn Insert(comptime mat: []const []const T) !void {
            if (columns() != mat[0].len) return error.WrongMatrixScheme;

            for (mat) |row| {
                const mutable = try arena.allocator().dupe(T, row);
                try matrix.append(mutable);
            }
        }

        /// Reshapes the matrix
        pub fn Rescheme(comptime num_columns: usize, comptime num_rows: usize) !void {
            if (size() < 1) return error.UnitializedMatrix;
            if (size() != num_columns * num_rows) return error.UnmatchedScheme;

            Destroy();
            
            const marray = try AsArray();
            var i: usize = 0;

            for (num_rows) |_| { 
                try AddRow(marray[i..i+num_columns]);
                i += num_columns;
            }
        }

        /// Gets a column from index
        pub fn GetColumn(comptime index: usize) ![]T {
            if (index >= columns())
                return error.ColumnOutOfRange;
            
            var column = try arena.allocator().alloc(T, rows());
            for (matrix.items, 0..) |slice, i| column[i] = slice[index];
            return column;
        }

        /// Gets a row from index
        pub fn GetRow(comptime index: usize) ![]T {
            return if (index >= rows()) error.RowOutOfRange else matrix.items[index];
        }

        /// Free matrix
        pub fn Destroy() void {
            for (matrix.items) |row| arena.allocator().free(row);
            matrix.clearAndFree();
        }

        /// Deinit matrix
        pub fn Deinit() void {
            matrix.deinit();
            arena.deinit();
        }
    };
}