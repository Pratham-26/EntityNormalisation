const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn WorkQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []T,
        head: std.atomic.Value(usize),
        tail: std.atomic.Value(usize),
        capacity: usize,
        allocator: Allocator,
        lock: std.atomic.Value(bool),

        pub fn init(allocator: Allocator) Self {
            const initial_capacity: usize = 256;
            const items = allocator.alloc(T, initial_capacity) catch @panic("Out of memory");

            return .{
                .items = items,
                .head = std.atomic.Value(usize).init(0),
                .tail = std.atomic.Value(usize).init(0),
                .capacity = initial_capacity,
                .allocator = allocator,
                .lock = std.atomic.Value(bool).init(false),
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
        }

        fn acquireLock(self: *Self) void {
            while (self.lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {
                std.atomic.spinLoopHint();
            }
        }

        fn releaseLock(self: *Self) void {
            self.lock.store(false, .release);
        }

        pub fn push(self: *Self, item: T) !void {
            self.acquireLock();
            defer self.releaseLock();

            const tail = self.tail.raw;
            const head = self.head.raw;

            if (tail - head >= self.capacity) {
                try self.growLocked();
            }

            self.items[tail % self.capacity] = item;
            self.tail.store(tail + 1, .release);
        }

        fn growLocked(self: *Self) !void {
            const new_capacity = self.capacity * 2;
            const new_items = try self.allocator.alloc(T, new_capacity);

            const head = self.head.raw;
            const tail = self.tail.raw;

            var i: usize = 0;
            while (head + i < tail) : (i += 1) {
                new_items[i] = self.items[(head + i) % self.capacity];
            }

            self.allocator.free(self.items);
            self.items = new_items;
            self.capacity = new_capacity;
            self.head.store(0, .monotonic);
            self.tail.store(tail - head, .monotonic);
        }

        pub fn pop(self: *Self) ?T {
            self.acquireLock();
            defer self.releaseLock();

            const tail = self.tail.raw;
            const head = self.head.raw;

            if (tail == head) {
                return null;
            }

            const item = self.items[head % self.capacity];
            self.head.store(head + 1, .release);
            return item;
        }

        pub fn steal(self: *Self) ?T {
            self.acquireLock();
            defer self.releaseLock();

            const tail = self.tail.raw;
            const head = self.head.raw;

            if (tail == head) {
                return null;
            }

            const item = self.items[head % self.capacity];
            self.head.store(head + 1, .release);
            return item;
        }

        pub fn isEmpty(self: *Self) bool {
            self.acquireLock();
            defer self.releaseLock();
            return self.tail.raw == self.head.raw;
        }

        pub fn size(self: *Self) usize {
            self.acquireLock();
            defer self.releaseLock();
            return self.tail.raw - self.head.raw;
        }
    };
}

const testing = std.testing;

test "WorkQueue push and pop" {
    const queue = WorkQueue(u32);
    var q = queue.init(testing.allocator);
    defer q.deinit();

    try q.push(1);
    try q.push(2);
    try q.push(3);

    try testing.expectEqual(@as(?u32, 1), q.pop());
    try testing.expectEqual(@as(?u32, 2), q.pop());
    try testing.expectEqual(@as(?u32, 3), q.pop());
    try testing.expectEqual(@as(?u32, null), q.pop());
}

test "WorkQueue steal" {
    const queue = WorkQueue(u32);
    var q = queue.init(testing.allocator);
    defer q.deinit();

    try q.push(10);
    try q.push(20);

    try testing.expectEqual(@as(?u32, 10), q.steal());
    try testing.expectEqual(@as(?u32, 20), q.pop());
}

test "WorkQueue isEmpty" {
    const queue = WorkQueue(u32);
    var q = queue.init(testing.allocator);
    defer q.deinit();

    try testing.expect(q.isEmpty());
    try q.push(1);
    try testing.expect(!q.isEmpty());
    _ = q.pop();
    try testing.expect(q.isEmpty());
}
