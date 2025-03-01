const std = @import("std");
const expect = std.testing.expect;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const test_allocator = std.testing.allocator;
const BitSet = std.DynamicBitSet;
const ArrayList = std.ArrayList;

pub fn smallerDegreeThan(g: Graph, a: usize, b: usize) bool {
    return g.adjacencies[a].count() < g.adjacencies[b].count();
}

pub const Graph = struct {
    allocator: Allocator,
    adjacencies: []BitSet,

    const Self = @This();

    pub fn initFull(allocator: Allocator, n_vertices: usize) !Self {
        const adjacencies = try allocator.alloc(BitSet, n_vertices);
        for (adjacencies) |*adj| {
            adj.* = try BitSet.initFull(allocator, n_vertices);
            adj.unmanaged.unsetAll();
        }
        return Self{
            .allocator = allocator,
            .adjacencies = adjacencies,
        };
    }

    pub inline fn size(self: Self) usize {
        return self.adjacencies.len;
    }

    pub fn hasEdges(self: Self) bool {
        for (self.adjacencies) |adj| {
            if (adj.count() > 0) {
                return true;
            }
        }
        return false;
    }

    pub fn addEdge(self: *Self, u: usize, v: usize) void {
        self.adjacencies[u].set(v);
        self.adjacencies[v].set(u);
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
            adj.deinit();
        }
        self.allocator.free(self.adjacencies);
    }
    // viable nodes - list that contains nodes adjacent to all elements of current clique
    // keep track of
    pub fn greedyMaximalClique(self: Self) !ArrayList(usize) {
        var clique = try ArrayList(usize).initCapacity(self.allocator, self.size());
        if (self.size() == 0) {
            return clique;
        }
        var viable_nodes = try self.allocator.alloc(usize, self.size());
        defer self.allocator.free(viable_nodes);

        for (0..self.size()) |node| {
            viable_nodes[node] = node;
        }
        std.sort.heap(usize, viable_nodes, self, smallerDegreeThan);
        var sentinel = self.size();
        while (sentinel > 0) : (sentinel -= 1) {
            const curr_viable = sentinel - 1;
            const curr_node = viable_nodes[curr_viable];
            var connected = true;
            for (clique.items) |c_node| {
                connected = connected and self.adjacencies[curr_node].isSet(c_node);
            }
            if (connected) {
                clique.appendAssumeCapacity(curr_node);
            }
        }
        return clique;
    }
};

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
    graph.addEdge(0, 3);
    const clique = try graph.greedyMaximalClique();
    defer clique.deinit();
    try expect(clique.items.len == 2);
    graph.addEdge(0, 1);
    const clique2 = try graph.greedyMaximalClique();
    defer clique2.deinit();
    try expect(clique2.items.len == 2);
    graph.addEdge(1, 3);
    const clique3 = try graph.greedyMaximalClique();
    defer clique3.deinit();
    try expect(clique3.items.len == 3);
}
