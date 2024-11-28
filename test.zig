const std = @import("std");
const Lean = @import("src/lean.zig");

pub fn main() !void {
    const lean = Lean.BasedValue(i32);
    
    const matrix = [_][]const i32{
        &[_]i32{1, 2, 3, 9}, 
        &[_]i32{2, 7, 2, 2}
    };

    try lean.Set(&matrix);
    try lean.Insert(&matrix);
    
    std.debug.print("{any}", .{lean.content()});
    

    lean.Destroy();
}