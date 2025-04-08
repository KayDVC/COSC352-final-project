const std = @import("std");
const local = @import("modules.zig");

const http = local.http;
const html = local.html;
const String = local.common.String;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub fn main() !void {
    var timer = try std.time.Timer.start();

    var page_content = try retrievePage();
    defer page_content.deinit();

    var elapsed: f64 = @floatFromInt(timer.lap());
    std.debug.print("Request took : {d:.5}ms\n", .{
        elapsed / std.time.ns_per_ms,
    });

    var parser = html.Parser.init(allocator);
    defer parser.deinit();

    try parser.parse(page_content);
    elapsed = @floatFromInt(timer.lap());
    std.debug.print("Parser took : {d:.5}ms\n", .{
        elapsed / std.time.ns_per_ms,
    });

    var table_tag = try String.initWithValue(allocator, "table");
    defer table_tag.deinit();

    const table_nodes = try parser.root.?.findTags(&table_tag);
    defer allocator.free(table_nodes);

    var i: u8 = 48; // '0' in ASCII
    for (table_nodes) |node| {
        var file_string = try String.initWithValue(allocator, "table");
        defer file_string.deinit();

        try file_string.append('_');
        try file_string.append(i);
        try file_string.appendSlice(".csv");
        try writeAsCsv(&file_string, node);

        i += 1;
    }
    elapsed = @floatFromInt(timer.lap());
    std.debug.print("Extracting CSV took : {d:.5}ms\n", .{
        elapsed / std.time.ns_per_ms,
    });
    std.debug.print("Check 'output' folder for generated csv files", .{});
}

fn getTempDir() !std.fs.Dir {
    const dir_name = "output";
    const cwd = std.fs.cwd();

    return cwd.openDir(dir_name, .{}) catch {
        try cwd.makeDir(dir_name);
        return try cwd.openDir(dir_name, .{});
    };
}

fn retrievePage() !String {
    var request = try http.Request.init("https://en.wikipedia.org/wiki/List_of_largest_companies_in_the_United_States_by_revenue");
    defer request.deinit();

    return request.get(allocator);
}

fn writeToFile(filename: *String, content: *String) !void {
    var temp_dir = try getTempDir();
    defer temp_dir.close();

    var file = try temp_dir.createFile(filename.toSlice(), .{});
    defer file.close();

    try file.writeAll(content.toSlice());
}

fn writeAsCsv(filename: *String, table_node: *const html.Node) !void {
    var csv_data = String.init(allocator);
    defer csv_data.deinit();

    var row_tag = try String.initWithValue(allocator, "tr");
    defer row_tag.deinit();

    var heading_tag = try String.initWithValue(allocator, "th");
    defer heading_tag.deinit();

    var data_tag = try String.initWithValue(allocator, "td");
    defer data_tag.deinit();

    const rows = try table_node.findTags(&row_tag);
    defer allocator.free(rows);

    for (rows, 0..) |row, i| {
        const vals = try row.findTags(if (i == 0) &heading_tag else &data_tag);
        defer allocator.free(vals);

        for (vals) |val| {
            try csv_data.append('"');
            try val.getAllContent(&csv_data);
            try csv_data.appendSlice("\",");
        }

        try csv_data.remove((csv_data.len - 1), csv_data.len);
        try csv_data.append('\n');
    }

    try writeToFile(filename, &csv_data);
}
