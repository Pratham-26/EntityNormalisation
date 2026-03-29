const std = @import("std");
const Allocator = std.mem.Allocator;

pub const BlockArena = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init(backing: Allocator) BlockArena {
        return .{
            .arena = std.heap.ArenaAllocator.init(backing),
        };
    }

    pub fn deinit(self: *BlockArena) void {
        self.arena.deinit();
    }

    pub fn allocator(self: *BlockArena) Allocator {
        return self.arena.allocator();
    }

    pub fn reset(self: *BlockArena) void {
        _ = self.arena.reset(.retain_capacity);
    }
};
