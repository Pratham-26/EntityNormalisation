pub const ThreadPool = @import("pool.zig").ThreadPool;
pub const Barrier = @import("barrier.zig").Barrier;
pub fn WorkQueue(comptime T: type) type {
    return @import("queue.zig").WorkQueue(T);
}

const testing = @import("std").testing;

test {
    _ = @import("pool.zig");
    _ = @import("barrier.zig");
    _ = @import("queue.zig");
}
