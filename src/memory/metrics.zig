const std = @import("std");
const builtin = @import("builtin");

pub const MemoryMetrics = struct {
    total_allocated: usize = 0,
    peak_allocated: usize = 0,
    current_allocated: usize = 0,
    allocation_count: usize = 0,

    pub fn init() MemoryMetrics {
        return .{};
    }

    pub fn recordAlloc(self: *MemoryMetrics, size: usize) void {
        self.total_allocated += size;
        self.current_allocated += size;
        if (self.current_allocated > self.peak_allocated) {
            self.peak_allocated = self.current_allocated;
        }
        self.allocation_count += 1;
    }

    pub fn recordFree(self: *MemoryMetrics, size: usize) void {
        if (size > self.current_allocated) {
            self.current_allocated = 0;
        } else {
            self.current_allocated -= size;
        }
    }

    pub fn reset(self: *MemoryMetrics) void {
        self.total_allocated = 0;
        self.peak_allocated = 0;
        self.current_allocated = 0;
        self.allocation_count = 0;
    }
};

pub fn getRSS() ?usize {
    return switch (builtin.os.tag) {
        .windows => getRSSWindows(),
        .linux => getRSSLinux(),
        .macos => getRSSMacos(),
        else => null,
    };
}

fn getRSSWindows() ?usize {
    const windows = std.os.windows;
    const kernel32 = windows.kernel32;

    var pmc: windows.PROCESS_MEMORY_COUNTERS = undefined;
    pmc.cb = @sizeOf(windows.PROCESS_MEMORY_COUNTERS);

    if (kernel32.GetProcessMemoryInfo(kernel32.GetCurrentProcess(), &pmc, pmc.cb) == 0) {
        return null;
    }
    return pmc.WorkingSetSize;
}

fn getRSSLinux() ?usize {
    const file = std.fs.openFileAbsolute("/proc/self/statm", .{}) catch return null;
    defer file.close();

    var buf: [256]u8 = undefined;
    const bytes_read = file.read(&buf) catch return null;
    const content = buf[0..bytes_read];

    var iter = std.mem.splitScalar(u8, content, ' ');
    _ = iter.next();
    const rss_str = iter.next() orelse return null;

    const rss_pages = std.fmt.parseInt(usize, std.mem.trim(u8, rss_str, " \n"), 10) catch return null;
    return rss_pages * std.mem.page_size;
}

fn getRSSMacos() ?usize {
    _ = struct {
        pub const TASK_INFO_MAX = 32;
        pub const MACH_TASK_BASIC_INFO = 20;
        pub const mach_task_basic_info_t = *anyopaque;
        pub const task_info_t = *anyopaque;
        pub const kern_return_t = i32;
        pub const natural_t = u32;
        pub const mach_vm_size_t = u64;

        pub const task_flavor_t = natural_t;
        pub const task_info_data_t = [TASK_INFO_MAX]natural_t;

        pub extern "c" fn task_info(
            target_task: usize,
            flavor: task_flavor_t,
            task_info_out: task_info_t,
            task_info_outCnt: *natural_t,
        ) kern_return_t;
    };

    return null;
}
