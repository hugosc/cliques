const std = @import("std");
const expect = std.testing.expect;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const test_allocator = std.testing.allocator;
const BitSet = std.DynamicBitSetUnmanaged;
const ArrayList = std.ArrayList;
const cstdlib = @cImport(@cInclude("stdlib.h"));
const stats = @import("stats.zig");

pub const Graph = struct {
    allocator: Allocator,
    adjacencies: []BitSet,

    const Self = @This();

    pub fn initFull(allocator: Allocator, n_vertices: usize) !Self {
        const adjacencies = try allocator.alloc(BitSet, n_vertices);
        for (adjacencies) |*adj| {
            adj.* = try BitSet.initFull(allocator, n_vertices);
            adj.unsetAll();
        }
        return Self{
            .allocator = allocator,
            .adjacencies = adjacencies,
        };
    }

    pub inline fn size(self: Self) usize {
        return self.adjacencies.len;
    }
    ///O(n) call, beware
    pub inline fn degree(self: Self, u: usize) usize {
        return self.adjacencies[u].count();
    }

    pub inline fn numEdges(self: Self) usize {
        var acc: usize = 0;
        for (self.adjacencies) |adj| {
            acc += adj.count();
        }
        return acc / 2;
    }

    pub fn hasEdges(self: Self) bool {
        for (self.adjacencies) |adj| {
            if (adj.count() > 0) {
                return true;
            }
        }
        return false;
    }

    pub fn setEdge(self: *Self, u: usize, v: usize) void {
        self.adjacencies[u].set(v);
        self.adjacencies[v].set(u);
    }

    pub fn unsetEdge(self: *Self, u: usize, v: usize) void {
        self.adjacencies[u].unset(v);
        self.adjacencies[v].unset(u);
    }

    pub fn unsetAll(self: *Self) void {
        for (self.adjacencies) |*adj| {
            adj.unsetAll();
        }
    }

    pub fn clone(self: *const Self) !Self {
        const adjacencies = try self.allocator.alloc(BitSet, self.size());
        for (0..self.size()) |i| {
            adjacencies[i] = try self.adjacencies[i].clone(self.allocator);
        }
        return Self{
            .allocator = self.allocator,
            .adjacencies = adjacencies,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.adjacencies) |*adj| {
            adj.deinit(self.allocator);
        }
        self.allocator.free(self.adjacencies);
    }

    pub fn format(
        self: Self,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        out_stream: anytype,
    ) !void {
        try std.fmt.format(out_stream, "graph{{ n = {d}, m = {d} }}", .{ self.size(), self.numEdges() });
    }
    pub fn printNeighbours(self: Self, writer: anytype) !void {
        try writer.print("{}\n", .{self});
        for (0..self.size()) |u| {
            try writer.print("\tnode {d}, d({d}) = {d}, N({d}) = {{", .{ u, u, self.degree(u), u });
            var it = self.adjacencies[u].iterator(.{});
            if (it.next()) |v| {
                try writer.print("{d}", .{v});
            }
            while (it.next()) |v| {
                try writer.print(", {d}", .{v});
            }
            try writer.print("}}\n", .{});
        }
    }
};

pub fn erdosRenyiGraph(g: *Graph, density: f32) void {
    for (0..g.size() - 1) |u| {
        if (density < 0.5) {
            g.adjacencies[u].unsetAll();
            for (u..g.size()) |v| {
                const int_thresh: @TypeOf(cstdlib.RAND_MAX) = @intFromFloat(density * cstdlib.RAND_MAX);
                if (cstdlib.rand() < int_thresh) {
                    g.adjacencies[u].set(v);
                    g.adjacencies[v].set(u);
                }
            }
        } else {
            g.adjacencies[u].setAll();
            for (u..g.size()) |v| {
                const int_thresh: @TypeOf(cstdlib.RAND_MAX) = @intFromFloat(density * cstdlib.RAND_MAX);
                if (cstdlib.rand() > int_thresh) {
                    g.adjacencies[u].unset(v);
                    g.adjacencies[v].unset(u);
                }
            }
        }
    }
}

pub fn erdosRenyiGraphFast(g: *Graph, density: f32, rng: anytype) void {
    for (1..g.size()) |u| {
        stats.randomBits(density, g.adjacencies[u].masks, u, rng);
    }
    for (0..g.size() - 1) |u| {
        for (u..g.size()) |v| {
            g.adjacencies[u].setValue(v, g.adjacencies[v].isSet(u));
        }
    }
}
// pub fn erdosRenyiGraph(g: *Graph, density: f32, prng: std.rand.Random) void {
//     for (0..g.size() - 1) |u| {
//         for (u..g.size()) |v| {
//             const int_thresh: u16 = @intFromFloat(density * std.math.maxInt(u16));
//             const edgeVal = prng.int(u16) < int_thresh;
//             g.adjacencies[u].setValue(v, edgeVal);
//             g.adjacencies[v].setValue(u, edgeVal);
//         }
//     }
// }

test "bitset graph" {
    var graph = try Graph.initFull(test_allocator, 10);
    try expect(graph.size() == 10);
    defer graph.deinit();
    var graph2 = try graph.clone();
    defer graph2.deinit();
    try expect(graph.size() == graph2.size());
}

test "graph maximal clique" {
    var graph = try Graph.initFull(test_allocator, 5);
    defer graph.deinit();
    graph.setEdge(0, 3);
    const clique = try graph.greedyMaximalClique();
    defer clique.deinit();
    try expect(clique.items.len == 2);
    graph.setEdge(0, 1);
    const clique2 = try graph.greedyMaximalClique();
    defer clique2.deinit();
    try expect(clique2.items.len == 2);
    graph.setEdge(1, 3);
    const clique3 = try graph.greedyMaximalClique();
    defer clique3.deinit();
    try expect(clique3.items.len == 3);
}
