const std = @import("std");
const local = @import("modules.zig");

const http = local.http;
const html = local.html;
const String = local.common.String;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    var page_content = try retrievePage();
    defer page_content.deinit();

    try writeToFile(page_content);
    var parser = html.Parser.init(allocator);
    defer parser.deinit();

    try parser.parse(page_content);
    try stdout.print("Root tag: {s}\n", .{parser.root.?.tag.?.toSlice()});
}

fn retrievePage() !String {
    var request = try http.Request.init("https://en.wikipedia.org/wiki/List_of_largest_companies_in_the_United_States_by_revenue");
    defer request.deinit();

    return request.get(allocator);
}

fn writeToFile(content: String) !void {
    var file = try std.fs.cwd().createFile("output.html", .{});
    defer file.close();
    try file.writeAll(content.toSlice());
}
