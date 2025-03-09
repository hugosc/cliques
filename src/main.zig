const gr = @import("graph.zig");
const algo = @import("graph_algo.zig");
const stats = @import("stats.zig");
const std = @import("std");

pub fn simulate(n_vertices: u32, density: f16, allocator: std.mem.Allocator, times: []i64, writer: anytype) !void {
    var graph = try gr.Graph.initFull(allocator, n_vertices);
    var clique_aux = try algo.GreedyMaximalCliqueAux.initFull(graph);

    defer graph.deinit();
    defer clique_aux.deinit();

    var rng = std.Random.DefaultPrng.init(42);

    for (times) |*time| {
        gr.erdosRenyiGraphFast(&graph, density, &rng);
        const start = std.time.milliTimestamp();
        clique_aux.greedyMaximalClique();
        const end = std.time.milliTimestamp();
        time.* = end - start;
        try writer.print("{}, clique {any}\n", .{ graph, clique_aux.clique.items.len });
    }
}

pub fn main() !void {
    const start = std.time.milliTimestamp();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const n_vertices = 50000;
    const density = 0.5;
    const n_simulations = 50;

    const times = try allocator.alloc(i64, n_simulations);
    defer allocator.free(times);

    try simulate(n_vertices, density, allocator, times, stdout);
    const mean_time = stats.mean(f32, times);
    const end = std.time.milliTimestamp();
    try stdout.print("mean exec: {any} ms, total: {any} ms.\n total + allocs: {any} ms.\n", .{ mean_time, mean_time * n_simulations, end - start });
    try bw.flush(); // don't forget to flush!
}
//
// pub fn main() !void {
//     const stdout_file = std.io.getStdOut().writer();
//     var bw = std.io.bufferedWriter(stdout_file);
//     const stdout = bw.writer();
//
//     const prob: f32 = 0.4;
//     var buf: [500000]u64 = undefined;
//     var rng = std.Random.DefaultPrng.init(42);
//
//     const start_slow = std.time.milliTimestamp();
//     _ = stats.randomBitSetSlow(prob, &buf, &rng);
//     const end_slow = std.time.milliTimestamp();
//
//     var setBits: f32 = 0;
//     for (buf) |u| {
//         setBits += @floatFromInt(@popCount(u));
//     }
//     const meanBits = setBits / (buf.len * 64);
//
//     try stdout.print("exec: {any} ms, mean bits: {any}\n", .{ end_slow - start_slow, meanBits });
//
//     const start_fast = std.time.milliTimestamp();
//     _ = stats.randomBitSetFast(prob, &buf, &rng);
//     const end_fast = std.time.milliTimestamp();
//
//     var setBits2: f32 = 0;
//     for (buf) |u| {
//         setBits2 += @floatFromInt(@popCount(u));
//     }
//     const meanBits2 = setBits2 / (buf.len * 64);
//
//     try stdout.print("exec: {any} ms, mean bits: {any}\n", .{ end_fast - start_fast, meanBits2 });
//
//     try bw.flush(); // don't forget to flush!
//
// }
