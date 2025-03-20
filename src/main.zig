const std = @import("std");
const local = @import("modules.zig");

const http = local.http;
const String = local.common.String;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var page_content = try retrievePage();
    defer page_content.deinit();

    const strings = try page_content.split(allocator);
    defer allocator.free(strings);

    for (strings, 0..) |string, i| {
        if (i > 50) {
            break;
        }
        try stdout.print("Line Found: {s}\n", .{string.toSlice()});
    }
}

fn retrievePage() !String {
    var request = try http.Request.init("https://en.wikipedia.org/wiki/List_of_largest_companies_in_the_United_States_by_revenue");
    defer request.deinit();

    return request.get(allocator);
}
