const std = @import("std");
const Allocator = std.mem.Allocator;
const UnionFind = @import("union_find.zig").UnionFind;
const Thresholds = @import("thresholds.zig").Thresholds;

pub const Edge = struct {
    left_id: u32,
    right_id: u32,
    weight: f64,
};

pub const Cluster = struct {
    id: u32,
    members: std.ArrayList(u32),
    cohesion: f64,
    allocator: Allocator,

    pub fn init(allocator: Allocator, id: u32) Cluster {
        return Cluster{
            .id = id,
            .members = std.ArrayList(u32).init(allocator),
            .cohesion = 1.0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Cluster) void {
        self.members.deinit();
    }

    pub fn addMember(self: *Cluster, id: u32) void {
        self.members.append(id) catch {};
    }
};

pub const ClusteringEngine = struct {
    uf: UnionFind,
    thresholds: Thresholds,
    clusters: std.HashMap(u32, Cluster, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage),
    edge_weights: std.HashMap(u64, f64, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    num_records: usize,

    pub fn init(allocator: Allocator, num_records: usize, thresholds: Thresholds) !ClusteringEngine {
        return ClusteringEngine{
            .uf = try UnionFind.init(allocator, num_records),
            .thresholds = thresholds,
            .clusters = std.HashMap(u32, Cluster, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator),
            .edge_weights = std.HashMap(u64, f64, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .num_records = num_records,
        };
    }

    pub fn deinit(self: *ClusteringEngine, allocator: Allocator) void {
        var iter = self.clusters.iterator();
        while (iter.next()) |entry| {
            var cluster = entry.value_ptr;
            cluster.deinit();
        }
        self.clusters.deinit();
        self.edge_weights.deinit();
        self.uf.deinit(allocator);
    }

    fn makeEdgeKey(a: u32, b: u32) u64 {
        const min_id = @min(a, b);
        const max_id = @max(a, b);
        return (@as(u64, min_id) << 32) | @as(u64, max_id);
    }

    pub fn processEdges(self: *ClusteringEngine, edges: []const Edge, allocator: Allocator) !void {
        for (edges) |edge| {
            const key = makeEdgeKey(edge.left_id, edge.right_id);
            try self.edge_weights.put(key, edge.weight);
        }

        const sorted_edges = try allocator.dupe(Edge, edges);
        defer allocator.free(sorted_edges);

        const sortCtx = struct {
            fn lessThan(_: void, a: Edge, b: Edge) bool {
                return a.weight > b.weight;
            }
        };
        std.sort.insertion(Edge, sorted_edges, {}, sortCtx.lessThan);

        for (sorted_edges) |edge| {
            if (!self.thresholds.isMatch(edge.weight)) {
                continue;
            }

            const root_left = self.uf.find(edge.left_id);
            const root_right = self.uf.find(edge.right_id);

            if (root_left == root_right) {
                continue;
            }

            if (self.checkCohesion(root_left, root_right, edge.weight)) {
                self.uf.merge(edge.left_id, edge.right_id);
            }
        }

        try self.buildClusters(allocator);
    }

    pub fn checkCohesion(self: *ClusteringEngine, cluster_a: u32, cluster_b: u32, edge_weight: f64) bool {
        _ = edge_weight;

        var members_a = std.ArrayList(u32).init(std.heap.page_allocator);
        defer members_a.deinit();
        var members_b = std.ArrayList(u32).init(std.heap.page_allocator);
        defer members_b.deinit();

        for (0..self.num_records) |i| {
            const id: u32 = @intCast(i);
            const root = self.uf.find(id);
            if (root == cluster_a) {
                members_a.append(id) catch {};
            } else if (root == cluster_b) {
                members_b.append(id) catch {};
            }
        }

        const size_a = members_a.items.len;
        const size_b = members_b.items.len;

        if (size_a == 0 or size_b == 0) {
            return true;
        }

        var combined = std.ArrayList(u32).initCapacity(std.heap.page_allocator, size_a + size_b) catch return false;
        defer combined.deinit();
        combined.appendSlice(members_a.items) catch {};
        combined.appendSlice(members_b.items) catch {};

        const cohesion = self.computeCohesion(combined.items, &self.edge_weights);

        return cohesion >= self.thresholds.cohesion;
    }

    pub fn getClusterAssignments(self: *ClusteringEngine, allocator: Allocator) !std.HashMap(u32, u32) {
        var assignments = std.HashMap(u32, u32, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator);

        for (0..self.num_records) |i| {
            const id: u32 = @intCast(i);
            const root = self.uf.find(id);
            try assignments.put(id, root);
        }

        return assignments;
    }

    pub fn computeCohesion(_: *const ClusteringEngine, members: []const u32, edge_weights: *const std.HashMap(u64, f64, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage)) f64 {
        if (members.len < 2) {
            return 1.0;
        }

        var sum: f64 = 0.0;
        var count: usize = 0;

        for (members, 0..) |a, i| {
            for (members[i + 1 ..]) |b| {
                const key = makeEdgeKey(a, b);
                if (edge_weights.get(key)) |weight| {
                    sum += weight;
                }
                count += 1;
            }
        }

        if (count == 0) {
            return 0.0;
        }

        return sum / @as(f64, @floatFromInt(count));
    }

    fn buildClusters(self: *ClusteringEngine, allocator: Allocator) !void {
        var root_members = std.HashMap(u32, std.ArrayList(u32), std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(allocator);
        defer {
            var iter = root_members.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            root_members.deinit();
        }

        for (0..self.num_records) |i| {
            const id: u32 = @intCast(i);
            const root = self.uf.find(id);

            if (!root_members.contains(root)) {
                try root_members.put(root, std.ArrayList(u32).init(allocator));
            }

            const list = root_members.getPtr(root).?;
            try list.append(id);
        }

        var iter = root_members.iterator();
        while (iter.next()) |entry| {
            const root = entry.key_ptr.*;
            const members = entry.value_ptr.items;

            var cluster = Cluster.init(allocator, root);
            for (members) |id| {
                try cluster.addMember(id);
            }

            const cohesion = self.computeCohesion(members, &self.edge_weights);
            cluster.cohesion = cohesion;

            try self.clusters.put(root, cluster);
        }
    }

    pub fn getCluster(self: *ClusteringEngine, record_id: u32) ?*Cluster {
        const root = self.uf.find(record_id);
        return self.clusters.getPtr(root);
    }

    pub fn getClusterCount(self: *ClusteringEngine) usize {
        return self.clusters.count();
    }
};

const testing = std.testing;

test "ClusteringEngine basic clustering" {
    const allocator = testing.allocator;
    const thresholds = Thresholds.init(0.8, 0.6, 0.5);

    var engine = try ClusteringEngine.init(allocator, 5, thresholds);
    defer engine.deinit(allocator);

    const edges = [_]Edge{
        .{ .left_id = 0, .right_id = 1, .weight = 0.9 },
        .{ .left_id = 1, .right_id = 2, .weight = 0.85 },
        .{ .left_id = 3, .right_id = 4, .weight = 0.88 },
    };

    try engine.processEdges(&edges, allocator);

    var assignments = try engine.getClusterAssignments(allocator);
    defer assignments.deinit();

    try testing.expect(engine.uf.connected(0, 1));
    try testing.expect(engine.uf.connected(1, 2));
    try testing.expect(engine.uf.connected(3, 4));
    try testing.expect(!engine.uf.connected(0, 3));
}

test "ClusteringEngine cohesion filter" {
    const allocator = testing.allocator;
    const thresholds = Thresholds.init(0.8, 0.6, 0.7);

    var engine = try ClusteringEngine.init(allocator, 4, thresholds);
    defer engine.deinit(allocator);

    const edges = [_]Edge{
        .{ .left_id = 0, .right_id = 1, .weight = 0.9 },
        .{ .left_id = 1, .right_id = 2, .weight = 0.85 },
        .{ .left_id = 0, .right_id = 2, .weight = 0.5 },
    };

    try engine.processEdges(&edges, allocator);

    try testing.expect(engine.uf.connected(0, 1));
    try testing.expect(engine.uf.connected(1, 2));
}

test "Edge key generation" {
    const key1 = ClusteringEngine.makeEdgeKey(1, 5);
    const key2 = ClusteringEngine.makeEdgeKey(5, 1);
    try testing.expectEqual(key1, key2);

    const key3 = ClusteringEngine.makeEdgeKey(0, 0);
    try testing.expectEqual(@as(u64, 0), key3);
}

test "Cohesion computation" {
    const allocator = testing.allocator;
    const thresholds = Thresholds.init(0.8, 0.6, 0.5);

    var engine = try ClusteringEngine.init(allocator, 3, thresholds);
    defer engine.deinit(allocator);

    const edges = [_]Edge{
        .{ .left_id = 0, .right_id = 1, .weight = 0.9 },
        .{ .left_id = 1, .right_id = 2, .weight = 0.8 },
        .{ .left_id = 0, .right_id = 2, .weight = 0.7 },
    };

    for (&edges) |edge| {
        const key = ClusteringEngine.makeEdgeKey(edge.left_id, edge.right_id);
        try engine.edge_weights.put(key, edge.weight);
    }

    const members = [_]u32{ 0, 1, 2 };
    const cohesion = engine.computeCohesion(&members, &engine.edge_weights);

    try testing.expectApproxEqRel(@as(f64, 0.8), cohesion, @as(f64, 0.01));
}
