const std = @import("std");

pub const Barrier = struct {
    count: std.atomic.Value(u32),
    initial: u32,
    generation: std.atomic.Value(u32),
    lock: std.atomic.Value(bool),

    pub fn init(count: u32) Barrier {
        return .{
            .count = std.atomic.Value(u32).init(count),
            .initial = count,
            .generation = std.atomic.Value(u32).init(0),
            .lock = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *Barrier) void {
        _ = self;
    }

    fn acquireLock(self: *Barrier) void {
        while (self.lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {
            std.atomic.spinLoopHint();
        }
    }

    fn releaseLock(self: *Barrier) void {
        self.lock.store(false, .release);
    }

    pub fn wait(self: *Barrier) void {
        self.acquireLock();
        const gen = self.generation.load(.monotonic);
        const old_count = self.count.fetchSub(1, .acq_rel);

        if (old_count == 1) {
            self.count.store(self.initial, .monotonic);
            _ = self.generation.fetchAdd(1, .release);
            self.releaseLock();
        } else {
            self.releaseLock();

            var spins: usize = 0;
            while (gen == self.generation.load(.acquire)) {
                spins += 1;
                if (spins < 1000) {
                    std.atomic.spinLoopHint();
                } else {
                    spins = 0;
                }
            }
        }
    }

    pub fn reset(self: *Barrier) void {
        self.acquireLock();
        defer self.releaseLock();

        self.count.store(self.initial, .monotonic);
        _ = self.generation.fetchAdd(1, .release);
    }
};

const testing = std.testing;
const Thread = std.Thread;

test "Barrier single thread" {
    var barrier = Barrier.init(1);
    defer barrier.deinit();

    barrier.wait();
}

test "Barrier multiple threads" {
    const num_threads = 4;
    var barrier = Barrier.init(num_threads);
    defer barrier.deinit();

    var counter: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);

    const Worker = struct {
        fn run(b: *Barrier, c: *std.atomic.Value(u32)) void {
            _ = c.fetchAdd(1, .monotonic);
            b.wait();
            _ = c.fetchAdd(1, .monotonic);
        }
    };

    var threads: [num_threads]Thread = undefined;
    for (0..num_threads) |i| {
        threads[i] = try Thread.spawn(.{}, Worker.run, .{ &barrier, &counter });
    }

    for (&threads) |*t| {
        t.join();
    }

    try testing.expectEqual(@as(u32, num_threads * 2), counter.load(.monotonic));
}
