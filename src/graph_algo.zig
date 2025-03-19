const Graph = @import("graph.zig").Graph;
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const NodeSet = std.DynamicBitSetUnmanaged;
const assert = std.debug.assert;
const expect = std.testing.expect;
const test_allocator = std.testing.allocator;

pub fn smallerDegreeThan(degree: [*]usize, a: usize, b: usize) bool {
    return degree[a] < degree[b];
}

/// Stack with run-time known max depth, it's unmanaged
pub fn AlgoStack(comptime T: type, comptime preAllocFn: fn (Allocator, usize) Allocator.Error!T, comptime freeFn: fn (Allocator, *T) void) type {
    return struct {
        levels: []T,
        depth: usize,

        const Self = @This();

        pub fn init() Self {
            return Self{ .levels = &[_]T{}, .depth = 0 };
        }

        pub fn initCapacity(allocator: Allocator, max_depth: usize, state_size: usize) !Self {
            const levels = try allocator.alloc(T, max_depth);
            for (levels) |*level| {
                level.* = try preAllocFn(allocator, state_size);
            }
            return Self{ .levels = levels, .depth = 0 };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            for (self.levels) |*level| {
                freeFn(allocator, level);
            }
            allocator.free(self.levels);
        }

        pub fn top(self: Self) *T {
            return &self.levels[self.depth - 1];
        }
        //pointer to preallocated state
        pub fn push(self: *Self) *T {
            self.depth += 1;
            return &self.levels[self.depth - 1];
        }
        pub fn pop(self: *Self) void {
            if (self.depth > 0) self.depth -= 1;
        }
    };
}

pub const GreedyMaximalCliqueRunner = struct {
    graph: Graph,
    clique: ArrayList(usize),
    nodes: []usize,
    degree: []usize,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .graph = Graph.init(allocator),
            .clique = ArrayList(usize).init(allocator),
            .nodes = &[_]usize{},
            .degree = &[_]usize{},
        };
    }

    pub fn initFromGraph(graph: Graph) !Self {
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

    pub fn run(self: *Self) void {
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

test "graph maximal clique" {
    var graph = try Graph.initFull(test_allocator, 5);
    defer graph.deinit();
    graph.setEdge(0, 3);
    var runner = try GreedyMaximalCliqueRunner.initFromGraph(graph);
    defer runner.deinit();
    runner.run();
    try expect(runner.clique.items.len == 2);
    graph.setEdge(0, 1);
    runner.run();
    try expect(runner.clique.items.len == 2);
    graph.setEdge(1, 3);
    runner.run();
    try expect(runner.clique.items.len == 3);
}
// ENUMERATE-CLIQUES (C; P; S)
// B enumerates all cliques in an arbitrary graph G
// C: set of vertices belonging to the current clique
// P: set of vertices which can be added to C
// S: set of vertices which are not allowed to be added to C
// N [u]: set of neighbours of vertex u in G
//
// 01 Let P be the set {u1; : : : ; u k };
// 02 if P = ∅ and S = ∅
// 03 then REPORT CLIQUE;
// 04 else for i←1 to k
// 05   do P←P\{u i };
// 06      P′←P;
// 07      S′←S;
// 08      N ←{v ∈ V | {u i ; v} ∈ E};
// 09      ENUMERATE CLIQUES (C∪{u i }; P′∩N; S′∩N );
// 10      S←S∪{u i };
// 11   od;
// 12 ;
pub const MaximalCliqueEnumerator = struct {
    graph: Graph,
    stack: Stack,
    num_masks: usize,

    const Self = @This();
    const State = struct {
        /// current clique
        clique: NodeSet,
        /// nodes that could be added
        candidates: NodeSet,
        node_it: NodeSet.Iterator(.{}),
        forbidden: NodeSet,
    };
    const MaskInt = usize;

    fn preallocState(allocator: Allocator, size: usize) !State {
        return State{
            .clique = try NodeSet.initFull(allocator, size),
            .candidates = try NodeSet.initFull(allocator, size),
            .node_it = undefined,
            .forbidden = try NodeSet.initFull(allocator, size),
        };
    }

    fn freeState(allocator: Allocator, state: *State) void {
        state.clique.deinit(allocator);
        state.candidates.deinit(allocator);
        state.forbidden.deinit(allocator);
    }

    fn debugPrintNodeSet(set: NodeSet) void {
        std.debug.print("{{", .{});
        var it = set.iterator(.{});
        if (it.next()) |v| {
            std.debug.print("{d}", .{v});
        }
        while (it.next()) |v| {
            std.debug.print(", {d}", .{v});
        }
        std.debug.print("}}\n", .{});
    }
    fn numMasks(bit_length: usize) usize {
        return (bit_length + (@bitSizeOf(MaskInt) - 1)) / @bitSizeOf(MaskInt);
    }
    /// I guess I have to do this because of https://github.com/ziglang/zig/issues/19933
    fn setAll(set: *NodeSet) void {
        const padding_bits: std.math.Log2Int(MaskInt) = @truncate(@bitSizeOf(MaskInt) - set.bit_length % @bitSizeOf(MaskInt));
        const padding_mask = std.math.boolMask(MaskInt, true) >> padding_bits;
        set.setAll();
        set.masks[numMasks(set.bit_length) - 1] &= padding_mask;
    }

    const Stack = AlgoStack(State, preallocState, freeState);

    pub fn init(allocator: Allocator) Self {
        return Self{ .graph = Graph.init(allocator), .current_depth = 0, .stack = &[_]State{} };
    }

    pub fn initFromGraph(graph: Graph) !Self {
        const num_masks = (graph.size() + (@bitSizeOf(usize) - 1)) / @bitSizeOf(usize);
        var stack = try Stack.initCapacity(graph.allocator, graph.size(), graph.size());
        const top = stack.push();
        top.clique.unsetAll();
        top.forbidden.unsetAll();
        setAll(&top.candidates);
        top.node_it = top.candidates.iterator(.{});

        return Self{ .graph = graph, .stack = stack, .num_masks = num_masks };
    }

    pub fn next(self: *Self) ?NodeSet {
        if (self.stack.depth == 0) return null;

        while (self.stack.top().node_it.next()) |u| {
            const curr_clique = self.stack.top().clique;

            const candidates = self.stack.top().candidates;

            const top = self.stack.push();
            @memcpy(top.clique.masks[0..self.num_masks], curr_clique.masks[0..self.num_masks]);
            top.clique.set(u);

            @memcpy(top.candidates.masks[0..self.num_masks], candidates.masks[0..self.num_masks]);

            top.candidates.setIntersection(self.graph.adjacencies[u]);
            top.node_it = top.candidates.iterator(.{});
        }

        const clique = self.stack.top().clique;
        self.stack.pop();

        return clique;
    }

    pub fn deinit(self: *Self) void {
        self.stack.deinit(self.graph.allocator);
    }
};

test "maximal clique" {
    var graph = try Graph.initFull(test_allocator, 10);
    defer graph.deinit();

    graph.setEdge(0, 3);
    graph.setEdge(0, 2);
    graph.setEdge(2, 3);
    graph.setEdge(5, 8);

    var enumerator = try MaximalCliqueEnumerator.initFromGraph(graph);
    defer enumerator.deinit();

    while (enumerator.next()) |clique| {
        std.debug.print("clique len {}\n", .{clique.count()});
    }
    //try expect(clique.count() == 3);
}
