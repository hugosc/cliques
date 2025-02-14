const std = @import("std");
const Allocator = std.mem.Allocator;
const AdjacencyList = std.DoublyLinkedList(usize);
const LNode = AdjacencyList.Node;
const test_allocator = std.testing.allocator;
const expect = std.testing.expect;
const expectError = std.testing.expectError;

fn adjListFind(v: usize, adj: *const AdjacencyList) ?*LNode {
    var head = adj.first;
    while (head) |item| : (head = item.next) {
        if (item.data == v) return item;
    }
    return null;
}

const GraphError = error{ VertexNotExists, EdgeAlreadyExists };
// What will I do with these graphs? Do I need them to grow in vertices?
// Their size will be know by reading a specific file
pub const Graph = struct {
    allocator: Allocator,
    adjacencies: ?[]AdjacencyList,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .adjacencies = null,
        };
    }

    pub fn size(self: *const Self) usize {
        if (self.adjacencies) |adj| {
            return adj.len;
        } else return 0;
    }

    pub fn addVertices(self: *Self, n_vertices: usize) !void {
        const to_alloc = n_vertices + (if (self.adjacencies) |adjs| adjs.len else 0);
        var new = try self.allocator.alloc(AdjacencyList, to_alloc);

        if (self.adjacencies) |adjs| {
            @memcpy(new[0..adjs.len], adjs);
            self.allocator.free(adjs);
        }
        for ((new.len - n_vertices)..new.len) |i| {
            new[i] = AdjacencyList{
                .len = 0,
                .first = null,
                .last = null,
            };
        }
        self.adjacencies = new;
    }
    pub fn safeAddEdge(self: *Self, v1: usize, v2: usize) !void {
        if (v1 >= self.size() or v2 >= self.size()) {
            return GraphError.VertexNotExists;
        }
        // the previous check guarantees adjacencies is not null and
        // has positions v1 and v2
        const adj = self.adjacencies.?;
        if (adjListFind(v2, &adj[v1]) != null) {
            return GraphError.EdgeAlreadyExists;
        }
        try self.unsafeAddEdge(v1, v2);
    }
    fn unsafeAddEdge(self: *Self, v1: usize, v2: usize) !void {
        const adj = self.adjacencies.?;
        const alloc_e1 = try self.allocator.create(LNode);
        errdefer self.allocator.destroy(alloc_e1);
        const alloc_e2 = try self.allocator.create(LNode);

        alloc_e1.data = v2;
        alloc_e2.data = v1;
        adj[v1].prepend(alloc_e1);
        adj[v2].prepend(alloc_e2);
    }

    pub fn multiLinePrint(self: *Self, writer: anytype) !void {
        if (self.adjacencies) |adjs| {
            for (adjs, 0..) |adj, i| {
                var curr = adj.first;
                try writer.print("{} ->", .{i});
                while (curr) |item| : (curr = item.next) {
                    try writer.print(" {}", .{item.data});
                }
                try writer.print("\n", .{});
            }
        } else {
            try writer.print("empty graph.\n", .{});
        }
    }

    pub fn deinit(self: *Self) void {
        if (self.adjacencies) |adjs| {
            for (adjs) |adj| {
                var edge = adj.first;
                while (edge) |item| {
                    const next = item.next;
                    self.allocator.destroy(item);
                    edge = next;
                }
            }

            self.allocator.free(adjs);
            self.adjacencies = null;
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
    try graph.addVertices(20);
    try expect(graph.size() == 50);
    try graph.safeAddEdge(3, 49);
    try expectError(GraphError.EdgeAlreadyExists, graph.safeAddEdge(3, 49));
    graph.deinit();
}
