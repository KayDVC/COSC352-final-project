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

    try stdout.print("Returned Content: {s}\n", .{page_content.toSlice()});
}

fn retrievePage() !String {
    var request = try http.Request.init("https://en.wikipedia.org/wiki/List_of_largest_companies_in_the_United_States_by_revenue");
    defer request.deinit();

    return request.get(allocator);
}
