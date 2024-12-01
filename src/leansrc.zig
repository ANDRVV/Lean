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

        /// Print matrix as fast as possible
        pub fn quickprint() !void {
            const stdout = std.io.getStdOut().writer();
            for (matrix.items) |row| {
                try stdout.print("{any}\n", .{row});
            }
        }

        /// Print matrix with customizable format
        pub fn printf(comptime format: []const u8) !void {
            const stdout = std.io.getStdOut().writer();
            for (matrix.items) |row| {
                for (row) |item| {
                    try stdout.print(format, .{item});
                }
                try stdout.print("\n", .{});
            }
        }

        /// Set 2D Array
        pub fn Set(mat: []const []const T) !void {
            for (mat[1..]) |slice| if (slice.len != mat[0].len) return error.WrongMatrixScheme;

            Destroy();

            try matrix.ensureTotalCapacity(mat.len);

            for (mat) |slice| {
                const newRow = try arena.allocator().dupe(T, slice);
                matrix.append(newRow) catch return error.SetAllocationFailure;
            }
        }

        /// Set 2D Array from fill -> recommended use rescheme after
        pub fn SetFill(value: T, repeat: usize) !void {
            const marray = try arena.allocator().alloc(T, repeat);
            @memset(marray, value);

            try Set(&[_][]const T{ marray });
        }

        /// Gets a value from index
        pub fn Get(column: usize, row: usize) !T {
            if (row >= rows() or column >= columns()) return error.GetItemNotFound;
            return matrix.items[row][column];
        }

        /// Join as a single list
        pub fn AsArray() ![]T {
            if (size() < 1) return error.UnitializedMatrix;

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

        /// Change a specified row
        pub fn ChangeRow(newRow: []const T, rowIndex: usize) !void {
            if (rows() <= rowIndex or columns() != newRow.len) return error.RowOutOfRange;

            const mutable = try arena.allocator().dupe(T, newRow);
            try matrix.replaceRange(rowIndex, 1, &[_][] T{ mutable });
        }

        /// Change a specified column
        pub inline fn ChangeColumn(newColumn: []const T, columnIndex: usize) !void {
            if (rows() != newColumn.len or columns() <= columnIndex) return error.ColumnOutOfRange;

            for (0..matrix.items.len) |rowIndex| {
                matrix.items[rowIndex][columnIndex] = newColumn[rowIndex];
            }
        }

        /// Remove a specified row
        pub inline fn RemoveRow(rowIndex: usize) !void {
            if (rows() <= rowIndex) return error.RowOutOfRange;

            _ = matrix.orderedRemove(rowIndex);
        }

        /// Remove a specified column
        pub fn RemoveColumn(columnIndex: usize) !void {
            if (columns() <= columnIndex) return error.ColumnOutOfRange;
            
            var row = std.ArrayList(T).init(arena.allocator());
            errdefer row.deinit();

            for (0..matrix.items.len) |rowIndex| {
                row.clearAndFree();
                try row.appendSlice(matrix.items[rowIndex]);
                _ = row.orderedRemove(columnIndex);

                matrix.items[rowIndex] = try arena.allocator().dupe(T, row.items);
            }
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

        /// Change value in (x, y)
        pub inline fn ChangeValue(value: usize, column: usize, row: usize) !void {
            if (size() < 1) return error.UnitializedMatrix;
            if (row >= rows() or column >= columns()) return error.UnmatchedScheme;

            matrix.items[row][column] = value;
        }

        /// Convert linear index as coordinates (x, y)
        pub inline fn IndexAsCoordinates(index: usize) ![2]usize {
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
        pub fn Insert(mat: []const []const T) !void {
            if (columns() != mat[0].len) return error.WrongMatrixScheme;

            for (mat) |row| {
                const mutable = try arena.allocator().dupe(T, row);
                try matrix.append(mutable);
            }
        }

        /// Reshapes the matrix
        pub fn Rescheme(num_columns: usize, num_rows: usize) !void {
            if (size() < 1) return error.UnitializedMatrix;
            if (size() != num_columns * num_rows) return error.UnmatchedScheme;

            const marray = try AsArray();
            var i: usize = 0;

            Destroy();
            
            for (num_rows) |_| { 
                try AddRow(marray[i..i+num_columns]);
                i += num_columns;
            }
        }

        /// Gets a column from index
        pub fn GetColumn(index: usize) ![]T {
            if (index >= columns())
                return error.ColumnOutOfRange;
            
            var column = try arena.allocator().alloc(T, rows());
            for (matrix.items, 0..) |slice, i| column[i] = slice[index];
            return column;
        }

        /// Gets a row from index
        pub fn GetRow(index: usize) ![]T {
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