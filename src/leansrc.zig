const std = @import("std");
const compdev = @import("compmath.zig");
const stdlean = @import("common.zig");

/// LeanErrors is a collection of errors that can be returned by Lean's functions.
pub const LeanErrors = error {
    /// `WrongMatrixScheme`: the matrix layout is incorrect, for example a odd matrix.
    WrongMatrixScheme,
    /// `ColumnOutOfRange` is returned when the column index is out of range.
    ColumnOutOfRange,
    /// `RowOutOfRange` is returned when the row index is out of range.
    RowOutOfRange,
    /// `UnitializedMatrix` is returned when the matrix is not initialized.
    UnitializedMatrix,
    /// `UnmatchedScheme` is returned when the matrix scheme is not matched.
    UnmatchedScheme,
    /// `StatNotAvailable` is returned when the requested statistic method is not supported.
    StatNotAvailable
};

/// Axis is a common input value on Lean's functions.
/// It can be used to specify the axis of a matrix.
pub const Axis = enum(u1) {
    /// `Columns`: the axis is the columns (y).
    Columns,
    /// `Rows`: the axis is the rows (x).
    Rows
};

/// Used for Stat() and StatCoordinates() functions.
/// It can be used to specify the statistic method.
pub const Stats = enum(u2) {
    /// `Max`: the maximum value.
    Max,
    /// `Min`: the minimum value.
    Min,
    /// `Avg`: the average value.
    Avg,
    /// `Med`: the median value.
    Med
};

/// For computing you can specify the operation.
pub const Operations = enum(u2) {
    /// `Add`: addition.
    Add,
    /// `Sub`: subtraction.
    Sub,
    /// `Mul`: multiplication.
    Mul,
    /// `Div`: division.
    Div
};

/// Used for the selection of the computing device.
/// Devices has a division for CPU, GPU and the modality:
/// - `Safe`: the safe mode is slower, it make anti-overflow checks.
/// - `Fast`: the fastest computing method with wrapping operations (no-overflow).
pub const Devices = enum(u1) {
    /// `SafeCPU`: the safe mode for CPU.
    SafeCPU,
    /// `FastCPU`: the fast mode for CPU.
    FastCPU,
    //SafeGPU,
    //FastGPU
};

/// Use Lean on custom numeric type
pub fn BasedValue(comptime T: type) type {
    return struct {
        const Self = @This();

        matrix: std.ArrayList([]T),
        allocator: std.mem.Allocator,
        device: Devices,

        /// Initialize Lean with allocator, device (optional) and capacity (number of rows).
        /// Capacity WON'T optimized. Otherwise, with optimization, use initCapacity().
        pub fn initCapacityPrecise(allocator: std.mem.Allocator, device: ?Devices, cap: usize) !Self {
            return Self {
                .allocator = allocator,
                .matrix = try std.ArrayList([]T).initCapacity(
                    allocator,
                    @max(cap, 1)
                ),
                .device = device orelse Devices.SafeCPU,
            };
        }

        /// Initialize Lean with allocator, device (optional) and capacity (number of rows).
        /// Capacity will changed with GetOptimalCapacity(). Otherwise use initCapacityPrecise().
        pub fn initCapacity(allocator: std.mem.Allocator, device: ?Devices, cap: usize) !Self {
            return try initCapacityPrecise(
                allocator,
                device,
                stdlean.GetOptimalCapacity(cap)
            );
        }

        /// Initialize Lean with allocator and device (optional) with dynamic capacity.
        pub fn init(allocator: std.mem.Allocator, device: ?Devices) Self {
            return Self {
                .allocator = allocator,
                .matrix = std.ArrayList([]T).init(allocator),
                .device = device orelse Devices.SafeCPU,
            };
        }

        /// Return the number of rows of the matrix.
        pub inline fn rows(self: *Self) usize { return self.matrix.items.len; }
        /// Return the number of columns of the matrix.
        pub inline fn columns(self: *Self) usize { return if (self.rows() > 0) self.matrix.items[0].len else 0; }
        /// Return the number of columns and rows of the matrix.
        pub inline fn scheme(self: *Self) [2]usize { return .{self.columns(), self.rows()}; }
        /// Return the total number of elements in the matrix.
        pub inline fn size(self: *Self) usize { return self.columns() * self.rows(); }
        /// Return the matrix content as 2D array.
        pub inline fn content(self: *Self) [][]T { return self.matrix.items; }

        /// Print matrix as fast as possible
        pub fn quickprint(self: *Self) !void {
            const stdout = std.io.getStdErr().writer();
            for (self.matrix) |row| {
                try stdout.print("{any}\n", .{row});
            }
        }

        /// Print matrix with customizable format
        pub fn printf(self: *Self, comptime format: []const u8) !void {
            const stdout = std.io.getStdOut().writer();
            for (self.matrix) |row| {
                for (row) |item| {
                    try stdout.print(format, .{item});
                }
                try stdout.print("\n", .{});
            }
        }

        /// Make a calculation with another matrix: the result can available on this matrix
        pub inline fn Calc(self: *Self, op: Operations, mat: []const []const T) !void {
            self.matrix.items = try self.ReturnCalc(op, mat);
        }

        /// Make a calculation with another matrix: the result is return of this function
        pub inline fn ReturnCalc(self: *Self, op: Operations, mat: []const []const T) ![][]T {
            return switch (self.device) {
                Devices.SafeCPU => compdev.CPUProc(
                    T,
                    op,
                    true,
                    self.allocator,
                    self.content(),
                    mat
                ),
                Devices.FastCPU => compdev.CPUProc(
                    T,
                    op,
                    false,
                    self.allocator,
                    self.content(),
                    mat
                )
            };
        }

        /// Set 2D Array
        pub fn Set(self: *Self, mat: []const []const T) !void {
            for (mat[1..]) |slice| if (slice.len != mat[0].len) return error.WrongMatrixScheme;
            
            self.Destroy();
            try self.matrix.ensureTotalCapacity(mat.len);

            for (mat) |slice| {
                const newRow = try self.allocator.dupe(T, slice);
                try self.matrix.append(newRow);
            }
        }

        /// Set 2D Array from fill -> recommended use rescheme after
        pub fn SetFill(self: *Self, value: T, repeat: usize) !void {
            const marray = try self.allocator.alloc(T, repeat);
            @memset(marray, value);

            try self.Set(&[_][]const T{ marray });
        }

        /// Set 2D Array from fill with random numbers -> recommended use rescheme after
        pub fn SetFillRandom(self: *Self, from: T, to: T, repeat: usize) !void {
            const marray = try self.allocator.alloc(T, repeat);
            
            var prng = std.rand.DefaultPrng.init(std.crypto.random.int(T));
            const random = prng.random();

            for (0..repeat) |i| {
                marray[i] = random.intRangeAtMost(T, from, to);
            }

            try self.Set(&[_][]const T{ marray });
        }

        //pub fn SetFillRule(repeat: usize) !void {
        //    
        //}

        /// Gets a value from index
        pub fn Get(self: *Self, column: usize, row: usize) !T {
            if (row >= self.rows()) return error.RowOutOfRange;
            if (column >= self.columns()) return error.ColumnOutOfRange;
            return self.matrix.items[row][column];
        }

        /// Change a specified row/column
        pub fn ChangeAxis(self: *Self, axis: Axis, newAxis: []const T, axisIndex: usize) !void {
            switch (axis) {
                Axis.Columns => {
                    if (self.rows() != newAxis.len or self.columns() <= axisIndex) return error.ColumnOutOfRange;

                    for (0..self.matrix.items.len) |rowIndex| {
                        self.matrix.items[rowIndex][axisIndex] = newAxis[rowIndex];
                    }
                },
                Axis.Rows => {
                    if (self.columns() != newAxis.len or self.rows() <= axisIndex) return error.RowOutOfRange;

                    const mutable = try self.allocator.dupe(T, newAxis);
                    try self.matrix.replaceRange(axisIndex, 1, &[_][] T{ mutable });
                },
            }
        }

        /// Gets a column/row from index
        pub fn GetAxis(self: *Self, axis: Axis, index: usize) ![]T {
            switch (axis) {
                Axis.Columns => {
                    if (index >= self.columns()) return error.ColumnOutOfRange;
                    
                    var column = try self.allocator.alloc(T, self.rows());
                    for (self.matrix.items, 0..) |slice, i| column[i] = slice[index];

                    return column;
                },
                Axis.Rows => return if (index >= self.rows()) error.RowOutOfRange else self.matrix.items[index],
            }
        }

        /// Remove a specified row/column
        pub fn RemoveAxis(self: *Self, axis: Axis, axisIndex: usize) !void {
            switch (axis) {
                Axis.Rows => {
                    if (self.rows() <= axisIndex) return error.RowOutOfRange;

                    _ = self.matrix.orderedRemove(axisIndex);
                },
                Axis.Columns => {
                    if (self.columns() <= axisIndex) return error.ColumnOutOfRange;

                    var row = std.ArrayList(T).init(self.allocator);
                    errdefer row.deinit();

                    for (0..self.matrix.items.len) |rowIndex| {
                        row.clearAndFree();
                        try row.appendSlice(self.matrix.items[rowIndex]);
                        _ = row.orderedRemove(axisIndex);

                        self.matrix.items[rowIndex] = try self.allocator.dupe(T, row.items);
                    }
                }
            }
        }

        /// Adds a row in a specified index, adter forward to the front
        pub fn AddAxis(self: *Self, axis: Axis, axisContent: []const T, axisIndex: usize) !void {
            switch (axis) {
                Axis.Columns => {
                    if (self.rows() != axisContent.len and self.rows() != 0) return error.UnmatchedScheme;

                    const rowLength = @max(self.columns(), 1);
                    const adjColumnIndex = if (self.rows() == 0) 0 else @min(rowLength, axisIndex);

                    if (adjColumnIndex == 0 and self.rows() == 0) {
                        for (axisContent) |item| {
                            const newRow = try self.allocator.alloc(T, 1);
                            newRow[0] = item;
                            try self.matrix.append(newRow);
                        }
                        return;
                    }

                    for (axisContent, 0..) |item, i| {
                        const updated = try self.allocator.alloc(T, rowLength + 1);
                        updated[adjColumnIndex] = item;

                        if (adjColumnIndex > 0) @memcpy(updated[0..adjColumnIndex], self.matrix.items[i][0..adjColumnIndex]);
                        if (self. self.rows() != 1) @memcpy(updated[adjColumnIndex + 1..], self.matrix.items[i][adjColumnIndex..]);

                        self.matrix.items[i] = updated;
                        
                    }
                },
                Axis.Rows => {
                    if (self.columns() != axisContent.len and self.columns() != 0) return error.RowOutOfRange;

                    const adjRowIndex = @min(self.columns(), axisIndex);
                    const mutable = try self.allocator.dupe(T, axisContent);
                    try self.matrix.insert(adjRowIndex, mutable);
                },
            }
        }

        /// Gets a piece of matrix, from (x, y) to (x, y)
        pub fn GetSection(self: *Self, fromX: usize, fromY: usize, toX: usize, toY: usize) ![][]T {
            const section = try self.allocator.alloc([]T, toY - fromY);
    
            for (0..toY - fromY, section) |i, *row| {
                row.* = try self.allocator.dupe(T, self.matrix[fromY + i][fromX..toX]);
            }
            
            return section;
        }

        /// Change value in (x, y)
        pub inline fn ChangeValue(self: *Self, value: usize, column: usize, row: usize) !void {
            if (self.size() < 1) return error.UnitializedMatrix;
            if (row >= self.rows() or column >= self.columns()) return error.UnmatchedScheme;

            self.matrix.items[row][column] = value;
        }

        /// Convert linear index as coordinates (x, y)
        pub inline fn IndexAsCoordinates(self: *Self, index: usize) ![2]usize {
            return .{index / self.columns(), index % self.columns()};
        }

        /// Gets coordinates (x, y) from stat in a specified column/row 
        /// avg stat not available (Stats.Avg)
        pub fn StatCoordinates(self: *Self, statType: Stats, axis: ?Axis, index: ?usize) ![2]usize {
            const marray = if (axis == null or index == null) try self.AsArray() else try self.GetAxis(axis.?, index.?);

            return IndexAsCoordinates(
                switch (statType) {
                    Stats.Max => std.mem.indexOfMax(T, marray),
                    Stats.Min => std.mem.indexOfMin(T, marray),
                    Stats.Med => struct {
                            fn f(value: f64, marray2: anytype) usize {
                                for (marray2, 0..) |item, i| if (@as(f64, @floatFromInt(item)) == value) return i;
                                @panic("Median not available.");
                            }
                        }.f(try self.Stat(statType, axis, index), marray),
                    else => return error.StatNotAvailable,
                }
            );
        }

        /// Gets value from stat in a specified column/row
        pub fn Stat(self: *Self, statType: Stats, axis: ?Axis, index: ?usize) !f64 {
            const marray = if (axis == null or index == null) try self.AsArray() else try self.GetAxis(axis.?, index.?);

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
        pub inline fn Sum(self: *Self) !usize {
            return self.Map( 
                struct {
                    fn f(a: usize, b: usize) usize { return a + b; }
                }.f
            );
        }

        /// Return the product of all values
        pub inline fn Prod(self: *Self) !usize {
            return self.Map( 
                struct {
                    fn f(a: usize, b: usize) usize { return a * b; }
                }.f
            );
        }

        /// Return the result of all operations among all values
        pub fn Map(self: *Self, opfunc: fn (usize, usize) usize) !usize {
            const marray = try self.AsArray();
            
            var res: usize = 0;
            for (marray) |value| {
                res = opfunc(res, value);
            }
            return res;
        }

        /// Concatenate with another matrix
        pub fn Insert(self: *Self, mat: []const []const T) !void {
            if (self.columns() != mat[0].len) return error.WrongMatrixScheme;

            for (mat) |row| {
                const mutable = try self.allocator.dupe(T, row);
                try self.matrix.append(mutable);
            }
        }

        /// Private function: reverse an axis of matrix
        fn reverseAxis(self: *Self, axis: Axis, idx: usize) !void {
            switch (axis) {
                Axis.Columns => {
                    const column = try self.GetAxis(Axis.Columns, idx);
                    std.mem.reverse(T, column);
                    try self.ChangeAxis(Axis.Columns, column, idx);
                },
                Axis.Rows => {
                    std.mem.reverse(T, self.matrix.items[idx]);
                }
            }
        }

        /// Reverse all or specified axis index
        pub fn Reverse(self: *Self, axis: Axis, index: ?usize) !void {
            if (index) |i| {
                switch (axis) {
                    Axis.Columns => if (i >= self.columns()) return error.ColumnOutOfRange,
                    Axis.Rows => if (i >= self.rows()) return error.RowOutOfRange,
                }
                try self.reverseAxis(axis, i);
            } else {
                const limit = switch (axis) {
                    Axis.Columns => self.columns(),
                    Axis.Rows => self.rows(),
                };

                for (0..limit) |i| {
                    try self.reverseAxis(axis, i);
                }
            }
        }
        
        /// Transpose matrix
        pub fn Transpose(self: *Self) !void {
            const matrixCopy = try stdlean.DeepClone(self.allocator, T, self.matrix);

            self.Destroy();

            for (matrixCopy.items, 0..) |row, i| {
                try self.AddAxis(Axis.Columns, row, i);
            }
        }

        /// Reshapes the matrix
        pub fn Rescheme(self: *Self, num_columns: usize, num_rows: usize) !void {
            if (self.size() < 1) return error.UnitializedMatrix;
            if (self.size() != num_columns * num_rows) return error.UnmatchedScheme;

            const marray = try self.AsArray();
            var i: usize = 0;

            self.Destroy();
            
            for (0..num_rows) |row| {
                const slice = marray[i..i+num_columns];
                try self.AddAxis(Axis.Rows, slice, row);
                i += num_columns;
            }
        }

        /// Join as a single list
        pub fn AsArray(self: *Self) ![]T {
            if (self.size() < 1) return error.UnitializedMatrix;

            var marray = try self.allocator.alloc(T, self.size());
            var i: usize = 0;

            for (self.matrix.items) |slice| {
                for (slice) |value| {
                    marray[i] = value;
                    i += 1;
                }
            }

            return marray;
        }

        /// Free matrix
        pub inline fn Destroy(self: *Self) void {
            for (self.matrix.items) |row| self.allocator.free(row);
            self.matrix.clearAndFree();
        }

        /// Deinit matrix
        pub inline fn deinit(self: Self) void {
            self.matrix.deinit();
        }
    };
}