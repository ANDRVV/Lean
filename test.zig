const std = @import("std");
const Lean = @import("src/lean.zig");

pub fn main() !void {
    var ar = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = ar.allocator();

    const dev = Lean.Devices{.SingleThreaded  = .FastCPU};

    const g: type = f64;

    var lean = Lean.BasedValue(g, dev).init(al);
    var lean2 = Lean.BasedValue(g, dev).init(al);

    var linalg = Lean.Linalg(g, dev, al);

    const mat1 = &[_][]const g{
        &[_]g{2, 2, 5},
        &[_]g{4, 5, 6},
        &[_]g{5, 2, 2},
    };
    
    try lean.Set(mat1);

    try lean.quickprint();
    std.debug.print("\n", .{});

    const a = try linalg.Transpose(lean.content());
    
    try lean.Set(a);

    try lean.quickprint();

    lean.Destroy();
    lean2.Destroy();
}