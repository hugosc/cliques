const std = @import("std");
const Allocator = std.mem.Allocator;
const AdjacencyList = std.DoublyLinkedList(usize);
const test_allocator = std.testing.allocator;
const expect = std.testing.expect;
// What will I do with these graphs? Do I need them to grow in vertices?
// Their size will be know by reading a specific file
pub const Graph = struct {
    allocator: Allocator,
    adjacencies: ?[]AdjacencyList,

    pub fn init(allocator: Allocator) Graph {
        return Graph{
            .allocator = allocator,
            .adjacencies = null,
        };
    }

    pub fn size(self: *const Graph) usize {
        if (self.adjacencies) |adj| {
            return adj.len;
        } else return 0;
    }

    pub fn addVertices(self: *Graph, n_vertices: usize) !void {
        const to_alloc = n_vertices + (if (self.adjacencies) |adj| adj.len else 0);
        const alloc = self.allocator.alloc(AdjacencyList, to_alloc);

        if (alloc) |new| {
            if (self.adjacencies) |adj| {
                @memcpy(new, adj);
                self.allocator.free(adj);
            }
            self.adjacencies = new;
        } else |err| {
            return err;
        }
    }
    pub fn deinit(self: *Graph) void {
        if (self.adjacencies) |adj| {
            self.allocator.free(adj);
        }
    }
};

test "graph init" {
    const graph = Graph.init(test_allocator);
    try expect(graph.size() == 0);
}

test "graph alloc" {
    var graph = Graph.init(test_allocator);
    try graph.addVertices(30);
    try expect(graph.size() == 30);
    graph.deinit();
}
