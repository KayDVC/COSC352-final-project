const std = @import("std");
const local = @import("../modules.zig");
const sizes = local.common.sizes;
const String = local.common.String;

pub const MAX_CONTENT_BYTES: u32 = 2 * sizes.BYTES_PER_MB;

pub const Request = struct {
    /// Reaches out to URI and returns content.
    pub fn get(allocator: std.mem.Allocator, uri: []const u8) !String {
        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();

        var response_body = std.ArrayList(u8).init(allocator);
        defer response_body.deinit();

        const result = try client.fetch(.{ .method = std.http.Method.GET, .location = .{ .url = uri }, .response_storage = .{ .dynamic = &response_body }, .max_append_size = @as(usize, MAX_CONTENT_BYTES) });
        _ = result;

        const response_buffer: []const u8 = try response_body.toOwnedSlice();
        defer allocator.free(response_buffer);

        return String.initWithValue(allocator, response_buffer);
    }
};
