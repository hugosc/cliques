const Graph = @import("graph.zig").Graph;
const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var graph = Graph.init(allocator);
    try graph.addVertices(5);
    try graph.safeAddEdge(1, 2);
    try graph.multiLinePrint(stdout);

    try bw.flush(); // don't forget to flush!
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
