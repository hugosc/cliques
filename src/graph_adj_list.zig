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
    adjacencies: []AdjacencyList,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .adjacencies = &[_]AdjacencyList{},
        };
    }

    pub inline fn size(self: *const Self) usize {
        return self.adjacencies.len;
    }

    pub fn addVertices(self: *Self, n_vertices: usize) !void {
        const to_alloc = n_vertices + self.size();
        var new = try self.allocator.alloc(AdjacencyList, to_alloc);
        @memcpy(new[0..self.adjacencies.len], self.adjacencies);
        self.allocator.free(self.adjacencies);

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
        const adj = self.adjacencies;
        if (adjListFind(v2, &adj[v1]) != null) {
            return GraphError.EdgeAlreadyExists;
        }
        try self.unsafeAddEdge(v1, v2);
    }
    fn unsafeAddEdge(self: *Self, v1: usize, v2: usize) !void {
        const alloc_e1 = try self.allocator.create(LNode);
        errdefer self.allocator.destroy(alloc_e1);
        const alloc_e2 = try self.allocator.create(LNode);

        alloc_e1.data = v2;
        alloc_e2.data = v1;
        self.adjacencies[v1].prepend(alloc_e1);
        self.adjacencies[v2].prepend(alloc_e2);
    }

    pub fn multiLinePrint(self: *Self, writer: anytype) !void {
        if (self.size() == 0) {
            try writer.print("empty graph.", .{});
            return;
        }

        for (self.adjacencies, 0..) |adj, i| {
            var curr = adj.first;
            try writer.print("{} ->", .{i});
            while (curr) |item| : (curr = item.next) {
                try writer.print(" {}", .{item.data});
            }
            try writer.print("\n", .{});
        }
    }

    pub fn deinit(self: *Self) void {
        for (self.adjacencies) |adj| {
            var edge = adj.first;
            while (edge) |item| {
                const next = item.next;
                self.allocator.destroy(item);
                edge = next;
            }
        }
        self.allocator.free(self.adjacencies);
    }
};

test "graph init" {
    var graph = Graph.init(test_allocator);
    defer graph.deinit();
    try expect(graph.size() == 0);
}

test "graph alloc" {
    var graph = Graph.init(test_allocator);
    defer graph.deinit();
    try graph.addVertices(30);
    try expect(graph.size() == 30);
    try graph.addVertices(20);
    try expect(graph.size() == 50);
    try graph.safeAddEdge(3, 49);
    try expectError(GraphError.EdgeAlreadyExists, graph.safeAddEdge(3, 49));
}

const dFSReturnStruct = struct {
    parent: []?usize,
    pre: []usize,
    post: []usize,
    sentinel: usize,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .parent = &[_]?usize{},
            .pre = &[_]usize{},
            .post = &[_]usize{},
            .sentinel = undefined,
            .allocator = allocator,
        };
    }

    pub fn create(n_vertices: usize, allocator: Allocator) !Self {
        var self = Self.init(allocator);

        self.parent = try allocator.alloc(?usize, n_vertices);
        @memset(self.parent, null);
        self.pre = try allocator.alloc(usize, n_vertices);
        self.post = try allocator.alloc(usize, n_vertices);
        self.sentinel = n_vertices;

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.parent);
        self.allocator.free(self.pre);
        self.allocator.free(self.post);
    }
};

/// Based on Knuth's pseudocode in volume 4's fascicle 12a, TAOCP.
/// Returns preorder, postorder and spanning tree. The return object
/// needs to be deallocated by calling its 'deinit()' method.
pub fn dFSIterative(graph: *const Graph, allocator: Allocator) !dFSReturnStruct {
    const dfs_ret = try dFSReturnStruct.create(graph.size(), allocator);
    const aux_arc = try allocator.alloc(?*LNode, graph.size());
    defer allocator.free(aux_arc);

    var p: usize = 0;
    var q: usize = 0;

    var sweep = graph.size() - 1;

    while (sweep > 0) : (sweep -= 1) {
        if (dfs_ret.parent[sweep]) |_| continue;
        //sweep is the root of a new strongly connected component.
        var v = sweep;
        var o_edge = graph.adjacencies[v].first;
        dfs_ret.parent[v] = dfs_ret.sentinel;
        dfs_ret.pre[v] = p;
        p += 1;
        while (true) {
            if (o_edge) |edge| {
                const u = edge.data;
                o_edge = edge.next;
                if (dfs_ret.parent[u] == null) {
                    // if u is an unexplored vertex, move to u
                    // while saving the next edge to explore from v
                    dfs_ret.parent[u] = v;
                    aux_arc[v] = o_edge;
                    v = u;
                    dfs_ret.pre[v] = p;
                    p += 1;
                    o_edge = graph.adjacencies[v].first;
                }
            } else {
                // finished exploring neighbors of v
                // we can move back to v's parent
                dfs_ret.post[v] = q;
                q += 1;
                v = dfs_ret.parent[v].?;
                if (v != dfs_ret.sentinel) {
                    o_edge = aux_arc[v];
                } else break;
            }
        }
    }
    return dfs_ret;
}

test "DFS tree" {
    // 4 <-> 3 <-> 1
    // 3 <-> 2 <-> 0
    var graph = Graph.init(test_allocator);
    defer graph.deinit();
    try graph.addVertices(5);
    try graph.unsafeAddEdge(4, 3);
    try graph.unsafeAddEdge(3, 1);
    try graph.unsafeAddEdge(3, 2);
    try graph.unsafeAddEdge(2, 0);

    var ret = try dFSIterative(&graph, test_allocator);
    defer ret.deinit();
    try expect(ret.parent[4] == ret.sentinel);
    try expect(ret.parent[3] == 4);
    try expect(ret.parent[2] == 3);
    try expect(ret.parent[1] == 3);
    try expect(ret.parent[0] == 2);
}

test "DFS two components" {
    // 4 <-> 3 <-> 2
    // 1 <-> 0
    var graph = Graph.init(test_allocator);
    defer graph.deinit();
    try graph.addVertices(5);
    try graph.unsafeAddEdge(4, 3);
    try graph.unsafeAddEdge(3, 2);
    try graph.unsafeAddEdge(1, 0);

    var ret = try dFSIterative(&graph, test_allocator);
    defer ret.deinit();
    try expect(ret.parent[4] == ret.sentinel);
    try expect(ret.parent[3] == 4);
    try expect(ret.parent[2] == 3);
    try expect(ret.parent[1] == ret.sentinel);
    try expect(ret.parent[0] == 1);
}
