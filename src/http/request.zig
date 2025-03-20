const std = @import("std");
const local = @import("../modules.zig");
const sizes = local.common.sizes;
const String = local.common.String;

pub const MAX_CONTENT_BYTES: u32 = 2 * sizes.BYTES_PER_MB;

pub const Request = struct {
    uri: []const u8,

    pub fn init(uri: []const u8) !Request {
        return Request{ .uri = uri };
    }

    pub fn deinit(self: *Request) void {
        self.* = undefined;
    }

    pub fn get(self: Request, allocator: std.mem.Allocator) !String {
        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();

        var response_body = std.ArrayList(u8).init(allocator);
        defer response_body.deinit();

        const result = try client.fetch(.{ .method = std.http.Method.GET, .location = .{ .url = self.uri }, .response_storage = .{ .dynamic = &response_body }, .max_append_size = @as(usize, MAX_CONTENT_BYTES) });
        _ = result;

        return String.initWithValue(allocator, try response_body.toOwnedSlice());
    }
};
