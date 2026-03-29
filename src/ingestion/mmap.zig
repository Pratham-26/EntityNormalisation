const std = @import("std");
const posix = std.posix;
const windows = std.os.windows;

pub const MappedFile = struct {
    data: []align(std.mem.page_size) const u8,
    handle: ?std.os.fd_t,
    size: usize,

    pub fn open(path: []const u8) !MappedFile {
        const file = try std.fs.cwd().openFile(path, .{});
        errdefer file.close();

        const stat = try file.stat();
        const file_size = stat.size;

        if (file_size == 0) {
            return MappedFile{
                .data = &[_]u8{},
                .handle = file.handle,
                .size = 0,
            };
        }

        const ptr = posix.mmap(
            null,
            file_size,
            posix.PROT.READ,
            .{ .TYPE = .PRIVATE },
            file.handle,
            0,
        ) catch return error.MappingFailed;

        const aligned_ptr: [*]align(std.mem.page_size) const u8 = @ptrCast(@alignCast(ptr));

        return MappedFile{
            .data = aligned_ptr[0..file_size],
            .handle = file.handle,
            .size = file_size,
        };
    }

    pub fn close(self: *MappedFile) void {
        if (self.size > 0 and self.data.len > 0) {
            posix.munmap(@constCast(self.data));
        }
        if (self.handle) |h| {
            posix.close(h);
        }
        self.data = &[_]u8{};
        self.handle = null;
        self.size = 0;
    }

    pub fn bytes(self: *const MappedFile) []const u8 {
        return self.data;
    }
};

test "MappedFile open and close" {
    const tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const path = "test_mmap.txt";
    const content = "Hello, World!";

    const file = try tmp_dir.dir.createFile(path, .{});
    defer file.close();
    try file.writeAll(content);

    var mapped = try MappedFile.open(path);
    defer mapped.close();

    try std.testing.expectEqualSlices(u8, content, mapped.bytes());
}
