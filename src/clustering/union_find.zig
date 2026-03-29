const std = @import("std");
const Allocator = std.mem.Allocator;

pub const UnionFind = struct {
    parent: []u32,
    rank: []u8,
    size: usize,

    pub fn init(allocator: Allocator, n: usize) !UnionFind {
        const parent = try allocator.alloc(u32, n);
        const rank = try allocator.alloc(u8, n);

        for (0..n) |i| {
            parent[i] = @intCast(i);
            rank[i] = 0;
        }

        return UnionFind{
            .parent = parent,
            .rank = rank,
            .size = n,
        };
    }

    pub fn deinit(self: *UnionFind, allocator: Allocator) void {
        allocator.free(self.parent);
        allocator.free(self.rank);
    }

    pub fn find(self: *UnionFind, x: u32) u32 {
        if (self.parent[x] != x) {
            self.parent[x] = self.find(self.parent[x]);
        }
        return self.parent[x];
    }

    pub fn merge(self: *UnionFind, x: u32, y: u32) void {
        const root_x = self.find(x);
        const root_y = self.find(y);

        if (root_x == root_y) {
            return;
        }

        if (self.rank[root_x] < self.rank[root_y]) {
            self.parent[root_x] = root_y;
        } else if (self.rank[root_x] > self.rank[root_y]) {
            self.parent[root_y] = root_x;
        } else {
            self.parent[root_y] = root_x;
            self.rank[root_x] += 1;
        }
    }

    pub fn connected(self: *UnionFind, x: u32, y: u32) bool {
        return self.find(x) == self.find(y);
    }

    pub fn getSetSize(self: *UnionFind, x: u32) usize {
        const root = self.find(x);
        var count: usize = 0;
        for (0..self.size) |i| {
            if (self.find(@intCast(i)) == root) {
                count += 1;
            }
        }
        return count;
    }

    pub fn countSets(self: *UnionFind) !usize {
        var roots = std.HashMap(u32, void, std.hash_map.AutoContext(u32), std.hash_map.default_max_load_percentage).init(std.heap.page_allocator);
        defer roots.deinit();

        var count: usize = 0;
        for (0..self.size) |i| {
            const root = self.find(@intCast(i));
            if (!roots.contains(root)) {
                try roots.put(root, {});
                count += 1;
            }
        }
        return count;
    }
};

const testing = std.testing;

test "UnionFind basic operations" {
    const allocator = testing.allocator;
    var uf = try UnionFind.init(allocator, 10);
    defer uf.deinit(allocator);

    try testing.expect(!uf.connected(0, 1));
    try testing.expect(uf.find(0) == 0);
    try testing.expect(uf.find(1) == 1);

    uf.merge(0, 1);
    try testing.expect(uf.connected(0, 1));
    try testing.expect(uf.getSetSize(0) == 2);

    uf.merge(2, 3);
    uf.merge(0, 2);
    try testing.expect(uf.connected(1, 3));
    try testing.expect(uf.getSetSize(0) == 4);

    try testing.expect(try uf.countSets() == 7);
}

test "UnionFind path compression" {
    const allocator = testing.allocator;
    var uf = try UnionFind.init(allocator, 5);
    defer uf.deinit(allocator);

    uf.merge(0, 1);
    uf.merge(1, 2);
    uf.merge(2, 3);
    uf.merge(3, 4);

    _ = uf.find(4);

    try testing.expect(uf.parent[4] == uf.find(0));
}

test "UnionFind union by rank" {
    const allocator = testing.allocator;
    var uf = try UnionFind.init(allocator, 8);
    defer uf.deinit(allocator);

    uf.merge(0, 1);
    uf.merge(2, 3);
    uf.merge(0, 2);

    uf.merge(4, 5);
    uf.merge(6, 7);
    uf.merge(4, 6);

    uf.merge(0, 4);

    const root = uf.find(7);
    try testing.expect(uf.find(0) == root);
    try testing.expect(uf.find(1) == root);
    try testing.expect(uf.find(2) == root);
    try testing.expect(uf.find(3) == root);
    try testing.expect(uf.find(4) == root);
    try testing.expect(uf.find(5) == root);
    try testing.expect(uf.find(6) == root);
}
