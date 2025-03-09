const Graph = @import("graph.zig").Graph;
const std = @import("std");
const ArrayList = @import("std").ArrayList;

pub fn smallerDegreeThan(degree: [*]usize, a: usize, b: usize) bool {
    return degree[a] < degree[b];
}

pub const GreedyMaximalCliqueAux = struct {
    graph: Graph,
    clique: ArrayList(usize),
    nodes: []usize,
    degree: []usize,

    const Self = @This();

    pub fn initFull(graph: Graph) !Self {
        const clique = try ArrayList(usize).initCapacity(graph.allocator, graph.size());
        const nodes = try graph.allocator.alloc(usize, graph.size());
        const degree = try graph.allocator.alloc(usize, graph.size());
        return Self{
            .graph = graph,
            .clique = clique,
            .nodes = nodes,
            .degree = degree,
        };
    }
    pub fn deinit(self: *Self) void {
        self.clique.deinit();
        self.graph.allocator.free(self.nodes);
        self.graph.allocator.free(self.degree);
    }

    pub fn greedyMaximalClique(self: *Self) void {
        self.clique.clearRetainingCapacity();
        for (0..self.graph.size()) |node| {
            self.nodes[node] = node;
            self.degree[node] = self.graph.degree(node);
        }
        std.sort.heap(usize, self.nodes, self.degree.ptr, smallerDegreeThan);
        var sentinel = self.graph.size();
        while (sentinel > 0) : (sentinel -= 1) {
            const curr_viable = sentinel - 1;
            const curr_node = self.nodes[curr_viable];
            var connected = true;
            for (self.clique.items) |c_node| {
                connected = connected and self.graph.adjacencies[curr_node].isSet(c_node);
            }
            if (connected) {
                self.clique.appendAssumeCapacity(curr_node);
            }
        }
    }
};
