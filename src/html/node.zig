const std = @import("std");
const local = @import("../modules.zig");

const constants = local.common.constants;
const tokens = local.html.tokens;
const String = local.common.String;
const Allocator = std.mem.Allocator;

pub const Node = struct {
    allocator: Allocator,
    tag: ?String = null,
    content: ?String = null,
    parent: ?*Node = null,
    children: ?std.ArrayList(*Node) = null,

    pub const NodeError = error{
        EXTRACTION_ERROR,
        UNCLOSED_TAG,
    };

    const ExtractStatus = enum {
        CONTINUE,
        FINISHED,
    };

    const NodeExtractionResult = struct {
        last_index: usize,
        extract_status: ExtractStatus,
    };

    pub fn init(allocator: Allocator) Node {
        return Node{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Node) void {
        if (self.tag) |*tag| {
            tag.deinit();
        }
        self.tag = null;

        if (self.content) |*content| {
            content.deinit();
        }
        self.content = null;

        if (self.children) |*children| {
            for (children.items) |child| {
                child.deinit();
                self.allocator.destroy(child);
            }
            children.deinit();
        }
        self.children = null;
        self.parent = null;
    }

    pub fn extract(self: *Node, html: String, start: usize) !usize {
        if (start >= html.len) return start; // handle edge-case: all content parsed.

        const result = try self.extractTag(html, start);
        if (result.extract_status == ExtractStatus.FINISHED) return result.last_index + 1;
        var curr: usize = result.last_index;

        // Initialize variables so we don't have so in loop.
        var children = std.ArrayList(*Node).init(self.allocator);
        var content = String.init(self.allocator);

        while (true) {
            const next_tag_index: usize = html.findFrom(curr, tokens.TAG_START) catch return NodeError.UNCLOSED_TAG;

            // Extract any content not nested in another tag.
            try content.appendSlice(html.getSlice((curr + 1), next_tag_index));
            content.strip();
            curr = next_tag_index;

            // Handle return case: no more nested tags.
            if (try html.at(curr + 1) == tokens.TAG_CLOSE_INDICATOR) {
                curr = html.findFrom(curr, tokens.TAG_END) catch return NodeError.EXTRACTION_ERROR; // '<' without '>'
                break;
            }
            // Recursively extract nested tags.
            else {
                var child = try self.allocator.create(Node);
                child.* = Node.init(self.allocator);
                child.parent = self;
                curr = try child.extract(html, curr);
                try children.append(child);
            }
        }

        // Free/set unused variables as necessary.
        if (content.len == 0) content.deinit() else self.content = content;
        if (children.items.len == 0) children.deinit() else self.children = children;

        return curr;
    }

    fn extractTag(self: *Node, html: String, start: usize) !Node.NodeExtractionResult {
        if (tokens.TAG_START != try html.at(start)) return NodeError.EXTRACTION_ERROR;

        // Get entire opening tag string (cleaning along the way).
        const tag_end = html.findFrom(start, tokens.TAG_END) catch return NodeError.EXTRACTION_ERROR;
        var tag = try String.initWithValue(self.allocator, html.getSlice(start, tag_end));
        try tag.remove(0, 1);
        tag.lstrip();

        const is_self_closing = tag.contains(tokens.TAG_CLOSE_INDICATOR);

        // Get actual tag value (i.e. 'p', 'html', etc.). Tag params are not captured in this implementation.
        for (tag.toSlice(), 0..) |char, i| {
            if ((char == tokens.TAG_END) or (constants.WHITESPACE.contains(char))) {
                try tag.remove(i, tag.len);
                break;
            }
        }
        self.tag = tag;
        return NodeExtractionResult{ .last_index = tag_end, .extract_status = if (is_self_closing) ExtractStatus.FINISHED else ExtractStatus.CONTINUE };
    }
};

const testing = std.testing;
const TestUtils = struct {
    fn appendOpeningTag(string: *String, tag: []const u8) !void {
        try string.append(tokens.TAG_START);
        try string.appendSlice(tag);
        try string.append(tokens.TAG_END);
    }

    fn appendClosingTag(string: *String, tag: []const u8) !void {
        try string.append(tokens.TAG_START);
        try string.append(tokens.TAG_CLOSE_INDICATOR);
        try string.appendSlice(tag);
        try string.append(tokens.TAG_END);
    }
};

test "test single tag" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();
    const tag: []const u8 = "p";
    const content: []const u8 = "Extract Me";
    var html = String.init(allocator);
    defer html.deinit();

    try TestUtils.appendOpeningTag(&html, tag);
    try html.appendSlice(content);
    try TestUtils.appendClosingTag(&html, tag);

    try testing.expectEqualStrings("<p>Extract Me</p>", html.toSlice());

    var node = Node.init(allocator);
    defer node.deinit();

    try testing.expectEqual((html.len - 1), node.extract(html, 0));
    try testing.expectEqualStrings(tag, node.tag.?.toSlice());
    try testing.expectEqualStrings(content, node.content.?.toSlice());
    try testing.expectEqual(null, node.parent);
    try testing.expectEqual(null, node.children);
}

test "test nested tags" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();
    const parent_tag: []const u8 = "html";
    var html = String.init(allocator);
    defer html.deinit();

    const nested_tags = [_][2][]const u8{
        [2][]const u8{ "p", "Extract Me" },
        [2][]const u8{ "span", "Hello World" },
        [2][]const u8{ "div", "Nice to meet you" },
    };

    try TestUtils.appendOpeningTag(&html, parent_tag);

    for (nested_tags) |nested_tag| {
        const tag = nested_tag[0];
        const content = nested_tag[1];

        // construct tag.
        try html.append(constants.NEWLINE);
        try TestUtils.appendOpeningTag(&html, tag);
        try html.appendSlice(content);
        try TestUtils.appendClosingTag(&html, tag);
        try html.append(constants.NEWLINE);
    }
    try TestUtils.appendClosingTag(&html, parent_tag);

    try testing.expectEqualStrings("<html>\n<p>Extract Me</p>\n\n<span>Hello World</span>\n\n<div>Nice to meet you</div>\n</html>", html.toSlice());
    var node = Node.init(allocator);
    defer node.deinit();

    try testing.expectEqual((html.len - 1), node.extract(html, 0));
    try testing.expectEqualStrings(parent_tag, node.tag.?.toSlice());

    try testing.expectEqual(null, node.content);
    try testing.expectEqual(null, node.parent);
    try testing.expect(node.children != null);
    try testing.expectEqual(nested_tags.len, node.children.?.items.len);

    for (node.children.?.items, nested_tags) |child_node, exp_values| {
        const exp_tag = exp_values[0];
        const exp_content = exp_values[1];

        try testing.expectEqualStrings(exp_tag, child_node.tag.?.toSlice());
        try testing.expectEqualStrings(exp_content, child_node.content.?.toSlice());
        try testing.expectEqual(&node, child_node.parent.?);
        try testing.expectEqual(null, child_node.children);
    }
}
