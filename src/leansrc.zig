const std = @import("std");
const leanMath = @import("leanmath.zig");
const stdlean = @import("common.zig");

/// ArenaAllocator: fastest allocation for small allocations
const ArenaAllocator = std.heap.ArenaAllocator; 

pub const LeanErrors = error {
    GetItemNotFound,
    WrongMatrixScheme,
    ColumnOutOfRange,
    RowOutOfRange,
    UnitializedMatrix,
    UnmatchedScheme,
    StatNotAvailable,
};

pub const Axis = enum(u1) {
    Columns,
    Rows
};

pub const Stats = enum(u2) {
    Max,
    Min,
    Avg,
    Med
};

pub const Operations = enum(u3) {
    Add,
    Sub,
    Mul,
    Div
};

pub const Devices = enum(u3) {
    CPU,
    GPU,
    CUDA
};

/// Use Lean on custom numeric type
pub fn BasedValue(comptime T: type) type {
    return struct {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        var matrix = std.ArrayList([]T).init(arena.allocator());

        var device: type = leanMath.CPUComputing(arena, T);

        pub inline fn rows() usize { return matrix.items.len; }
        pub inline fn columns() usize { return if (rows() > 0) matrix.items[0].len else 0; }
        pub inline fn scheme() [2]usize { return .{columns(), rows()}; }
        pub inline fn size() usize { return columns() * rows(); }
        pub inline fn content() [][]T { return matrix.items; }

        /// Change device that does the calculations
        pub inline fn ChangeDevice(computingDevice: Devices) void { 
            device = switch (computingDevice) { 
                Devices.CPU => leanMath.CPUComputing(arena, T),
                Devices.GPU => leanMath.GPUComputing(arena, T),
                Devices.CUDA => leanMath.CUDAComputing(arena, T),
            };
        }

        /// Make a calculation with another matrix: the result can available on this matrix
        pub inline fn Calc(op: Operations, mat: []const []const T) !void {
            matrix.items = try ReturnCalc(op, mat);
        }

        pub inline fn ReturnCalc(op: Operations, mat: []const []const T) ![][]T {
            return try switch (op) {
                Operations.Add => device.Add(content(), mat),
                Operations.Sub => device.Sub(content(), mat),
                Operations.Mul => device.Mul(content(), mat),
                Operations.Div => device.Div(content(), mat),
            };
        }

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
                try matrix.append(newRow);
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

        /// Change a specified row/column
        pub fn ChangeAxis(axis: Axis, newAxis: []const T, axisIndex: usize) !void {
            switch (axis) {
                Axis.Columns => {
                    if (rows() != newAxis.len or columns() <= axisIndex) return error.ColumnOutOfRange;

                    for (0..matrix.items.len) |rowIndex| {
                        matrix.items[rowIndex][axisIndex] = newAxis[rowIndex];
                    }
                },
                Axis.Rows => {
                    if (columns() != newAxis.len or rows() <= axisIndex) return error.RowOutOfRange;

                    const mutable = try arena.allocator().dupe(T, newAxis);
                    try matrix.replaceRange(axisIndex, 1, &[_][] T{ mutable });
                },
            }
        }

        /// Gets a column/row from index
        pub fn GetAxis(axis: Axis, index: usize) ![]T {
            switch (axis) {
                Axis.Columns => {
                    if (index >= columns()) return error.ColumnOutOfRange;
                    
                    var column = try arena.allocator().alloc(T, rows());
                    for (matrix.items, 0..) |slice, i| column[i] = slice[index];

                    return column;
                },
                Axis.Rows => return if (index >= rows()) error.RowOutOfRange else matrix.items[index],
            }
        }

        /// Remove a specified row/column
        pub inline fn RemoveAxis(axis: Axis, axisIndex: usize) !void {
            switch (axis) {
                Axis.Rows => {
                    if (rows() <= axisIndex) return error.RowOutOfRange;

                    _ = matrix.orderedRemove(axisIndex);
                },
                Axis.Columns => {
                    if (columns() <= axisIndex) return error.ColumnOutOfRange;
            
                    var row = std.ArrayList(T).init(arena.allocator());
                    errdefer row.deinit();

                    for (0..matrix.items.len) |rowIndex| {
                        row.clearAndFree();
                        try row.appendSlice(matrix.items[rowIndex]);
                        _ = row.orderedRemove(axisIndex);

                        matrix.items[rowIndex] = try arena.allocator().dupe(T, row.items);
                    }
                }
            }
        }

        /// Adds a row in a specified index, adter forward to the front
        pub fn AddAxis(axis: Axis, axisContent: []const T, axisIndex: usize) !void {
            switch (axis) {
                Axis.Columns => {
                    if (rows() != axisContent.len and rows() != 0) return error.UnmatchedScheme;

                    const rowLength = @max(columns(), 1);
                    const adjColumnIndex = if (rows() == 0) 0 else @min(rowLength, axisIndex);

                    if (adjColumnIndex == 0 and rows() == 0) {
                        for (axisContent) |item| {
                            const newRow = try arena.allocator().alloc(T, 1);
                            newRow[0] = item;
                            try matrix.append(newRow);
                        }
                        return;
                    }

                    for (axisContent, 0..) |item, i| {
                        const updated = try arena.allocator().alloc(T, rowLength + 1);
                        updated[adjColumnIndex] = item;

                        if (adjColumnIndex > 0) @memcpy(updated[0..adjColumnIndex], matrix.items[i][0..adjColumnIndex]);
                        if (rows() != 1) @memcpy(updated[adjColumnIndex + 1..], matrix.items[i][adjColumnIndex..]);

                        matrix.items[i] = updated;
                        
                    }
                },
                Axis.Rows => {
                    if (columns() != axisContent.len and columns() != 0) return error.RowOutOfRange;

                    const adjRowIndex = @min(columns(), axisIndex);
                    const mutable = try arena.allocator().dupe(T, axisContent);
                    try matrix.insert(adjRowIndex, mutable);
                },
            }
        }

        /// Gets a piece of matrix, from (x, y) to (x, y)
        pub fn GetSection(fromX: usize, fromY: usize, toX: usize, toY: usize) ![][]T {
            const section = try arena.allocator().alloc([]T, toY - fromY);
    
            for (0..toY - fromY, section) |i, *row| {
                row.* = try arena.allocator().dupe(T, matrix[fromY + i][fromX..toX]);
            }
            
            return section;
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

        /// Gets coordinates (x, y) from stat in a specified column/row 
        /// avg stat not available (Stats.Avg)
        pub fn StatCoordinates(statType: Stats, axis: ?Axis, index: ?usize) ![2]usize {
            const marray = if (axis == null or index == null) try AsArray() else try GetAxis(axis.?, index.?);

            return IndexAsCoordinates(
                switch (statType) {
                    Stats.Max => std.mem.indexOfMax(T, marray),
                    Stats.Min => std.mem.indexOfMin(T, marray),
                    Stats.Med => struct {
                            fn f(value: f64, marray2: anytype) usize {
                                for (marray2, 0..) |item, i| if (@as(f64, @floatFromInt(item)) == value) return i;
                                unreachable; // if Stat() success, for loop success!
                            }
                        }.f(try Stat(statType, axis, index), marray),
                    else => return error.StatNotAvailable,
                }
            );
        }

        /// Gets value from stat in a specified column/row
        pub fn Stat(statType: Stats, axis: ?Axis, index: ?usize) !f64 {
            const marray = if (axis == null or index == null) try AsArray() else try GetAxis(axis.?, index.?);

            return switch (statType) {
                Stats.Max => @floatFromInt(std.mem.max(T, marray)),
                Stats.Min => @floatFromInt(std.mem.min(T, marray)),
                Stats.Avg => {
                    var sum: f64 = 0;
                    for (marray) |value| sum += @floatFromInt(value);
                    return sum / @as(f64, @floatFromInt(marray.len));
                },
                Stats.Med => {
                    std.mem.sort(T, marray, {}, comptime std.sort.asc(T));
                    const mmid = @as(f64, @floatFromInt(marray[marray.len / 2]));

                    return if (marray.len % 2 == 1) mmid else (@as(f64, @floatFromInt(marray[marray.len / 2 - 1])) + mmid) / 2.0;
                }
            };
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

        /// Private function: reverse an axis of matrix
        fn reverseAxis(axis: Axis, idx: usize) !void {
            switch (axis) {
                Axis.Columns => {
                    const column = try GetAxis(Axis.Columns, idx);
                    std.mem.reverse(T, column);
                    try ChangeAxis(Axis.Columns, column, idx);
                },
                Axis.Rows => {
                    std.mem.reverse(T, matrix.items[idx]);
                }
            }
        }

        /// Reverse all or specified axis index
        pub fn Reverse(axis: Axis, index: ?usize) !void {
            if (index) |i| {
                switch (axis) {
                    Axis.Columns => if (i >= columns()) return error.ColumnOutOfRange,
                    Axis.Rows => if (i >= rows()) return error.RowOutOfRange,
                }
                try reverseAxis(axis, i);
            } else {
                const limit = switch (axis) {
                    Axis.Columns => columns(),
                    Axis.Rows => rows(),
                };

                for (0..limit) |i| {
                    try reverseAxis(axis, i);
                }
            }
        }
        
        /// Transpose matrix
        pub fn Transpose() !void {
            const matrixCopy = try stdlean.DeepClone(arena.allocator(), T, matrix);

            Destroy();

            for (matrixCopy.items, 0..) |row, i| {
                try AddAxis(Axis.Columns, row, i);
            }
        }

        /// Reshapes the matrix
        pub fn Rescheme(num_columns: usize, num_rows: usize) !void {
            if (size() < 1) return error.UnitializedMatrix;
            if (size() != num_columns * num_rows) return error.UnmatchedScheme;

            const marray = try AsArray();
            var i: usize = 0;

            Destroy();
            
            for (0..num_rows) |row| {
                const slice = marray[i..i+num_columns];
                try AddAxis(Axis.Rows, slice, row);
                i += num_columns;
            }
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