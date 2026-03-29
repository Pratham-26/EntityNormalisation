const std = @import("std");
const Allocator = std.mem.Allocator;
const queue = @import("queue.zig");

pub const ThreadPool = struct {
    const Self = @This();

    pub const Job = struct {
        func: *const fn (ctx: *anyopaque) void,
        ctx: *anyopaque,
    };

    const Worker = struct {
        pool: *ThreadPool,
        queue: *WorkQueue,
        thread: ?std.Thread,
        id: usize,
    };

    const WorkQueue = queue.WorkQueue(Job);

    allocator: Allocator,
    workers: []Worker,
    queues: []WorkQueue,
    num_workers: u32,
    running: std.atomic.Value(bool),
    pending_jobs: std.atomic.Value(usize),

    pub fn init(allocator: Allocator, num_threads: u32) !*ThreadPool {
        const actual_threads = if (num_threads == 0) @as(u32, @intCast(std.Thread.getCpuCount() catch 1)) else num_threads;

        const workers = try allocator.alloc(Worker, actual_threads);
        const queues = try allocator.alloc(WorkQueue, actual_threads);
        @memset(workers, undefined);

        for (workers, 0..) |*w, i| {
            w.* = .{
                .pool = undefined,
                .queue = undefined,
                .thread = null,
                .id = i,
            };
        }

        for (queues) |*q| {
            q.* = WorkQueue.init(allocator);
        }

        const self = try allocator.create(ThreadPool);
        self.* = .{
            .allocator = allocator,
            .workers = workers,
            .queues = queues,
            .num_workers = actual_threads,
            .running = std.atomic.Value(bool).init(true),
            .pending_jobs = std.atomic.Value(usize).init(0),
        };

        for (workers) |*w| {
            w.pool = self;
            w.queue = &queues[w.id];
        }

        for (workers) |*w| {
            w.thread = try std.Thread.spawn(.{}, workerLoop, .{w});
        }

        return self;
    }

    pub fn deinit(self: *ThreadPool) void {
        self.running.store(false, .release);

        for (self.workers) |*w| {
            if (w.thread) |t| {
                t.join();
            }
        }

        for (self.queues) |*q| {
            q.deinit();
        }

        self.allocator.free(self.workers);
        self.allocator.free(self.queues);
        self.allocator.destroy(self);
    }

    fn workerLoop(worker: *Worker) void {
        outer: while (worker.pool.running.load(.acquire)) {
            if (worker.pool.getNextJob(worker.id)) |job| {
                job.func(job.ctx);
                _ = worker.pool.pending_jobs.fetchSub(1, .release);
            } else {
                var spins: usize = 0;
                while (spins < 100000) : (spins += 1) {
                    if (!worker.pool.running.load(.acquire)) {
                        break :outer;
                    }
                    if (worker.pool.getNextJob(worker.id)) |job| {
                        job.func(job.ctx);
                        _ = worker.pool.pending_jobs.fetchSub(1, .release);
                        continue :outer;
                    }
                    std.atomic.spinLoopHint();
                }
            }
        }
    }

    fn getNextJob(self: *ThreadPool, worker_id: usize) ?Job {
        if (self.queues[worker_id].pop()) |job| {
            return job;
        }

        var i: usize = 1;
        while (i < self.num_workers) {
            const steal_id = (worker_id + i) % self.num_workers;
            if (self.queues[steal_id].steal()) |job| {
                return job;
            }
            i += 1;
        }

        return null;
    }

    pub fn submit(self: *const ThreadPool, job: Job) !void {
        const target = @as(usize, @intFromPtr(job.ctx)) % self.num_workers;
        _ = self.pending_jobs.fetchAdd(1, .monotonic);
        try self.queues[target].push(job);
    }

    pub fn submitBatch(self: *const ThreadPool, jobs: []Job) !void {
        _ = self.pending_jobs.fetchAdd(jobs.len, .monotonic);
        for (jobs, 0..) |job, i| {
            const target = i % self.num_workers;
            try self.queues[target].push(job);
        }
    }

    pub fn waitIdle(self: *const ThreadPool) void {
        while (self.pending_jobs.load(.acquire) > 0) {
            std.atomic.spinLoopHint();
        }
    }

    pub fn numThreads(self: *const ThreadPool) u32 {
        return self.num_workers;
    }
};

const testing = std.testing;

test "ThreadPool basic" {
    var pool = try ThreadPool.init(testing.allocator, 2);
    defer pool.deinit();

    try testing.expectEqual(@as(u32, 2), pool.numThreads());
}

test "ThreadPool execute jobs" {
    var pool = try ThreadPool.init(testing.allocator, 4);
    defer pool.deinit();

    const Counter = struct {
        value: std.atomic.Value(u32),

        fn increment(ctx: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            _ = self.value.fetchAdd(1, .monotonic);
        }
    };

    var counter = Counter{ .value = std.atomic.Value(u32).init(0) };

    for (0..100) |_| {
        try pool.submit(.{
            .func = Counter.increment,
            .ctx = &counter,
        });
    }

    pool.waitIdle();

    try testing.expectEqual(@as(u32, 100), counter.value.load(.monotonic));
}
