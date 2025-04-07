const std = @import("std");
const local = @import("../modules.zig");

const constants = local.common.constants;
const tokens = local.html.tokens;
const String = local.common.String;
const Allocator = std.mem.Allocator;

// Taken from https://html.spec.whatwg.org/multipage/syntax.html#void-elements
const KNOWN_SELF_CLOSING_TAGS = [_][]const u8{
    "area",
    "base",
    "br",
    "col",
    "embed",
    "hr",
    "img",
    "input",
    "link",
    "meta",
    "source",
    "track",
    "wbr",
};

pub const Parser = struct {
    allocator: Allocator,
    root: ?*Node,

    pub const ParserError = error{
        INVALID_HTML,
        EMPTY_DOCUMENT,
    };

    pub fn init(allocator: Allocator) Parser {
        return Parser{
            .allocator = allocator,
            .root = null,
        };
    }

    pub fn deinit(self: *Parser) void {
        if (self.root) |root| {
            root.deinit();
            self.allocator.destroy(root);
        }
        self.root = null;
    }

    pub fn parse(self: *Parser, html: String) !void {
        var node = try self.allocator.create(Node);
        node.* = Node.init(self.allocator);

        errdefer {
            node.deinit();
            self.allocator.destroy(node);
        }

        _ = node.extract(html, 0) catch return ParserError.INVALID_HTML;

        self.root = node;
    }
};

pub const Node = struct {
    allocator: Allocator,
    tag: ?String = null,
    content: ?String = null,
    parent: ?*Node = null,
    children: ?std.ArrayList(*Node) = null,

    pub const NodeError = error{
        ExtractionError,
        IncompleteTag, // '<p' or '<p>' without full '</p>'
        SpecialIndicatorError,
    };

    const ExtractStatus = enum {
        CONTINUE,
        FINISHED,
    };

    const NodeExtractionResult = struct {
        last_index: usize,
        extract_status: ExtractStatus,
    };

    pub fn getTree(self: Node, level: usize, out: *String) !void {
        const formatted_string = try std.fmt.allocPrint(
            self.allocator,
            "Tag: {s}, Address: {*}, Content: {s}\n",
            .{ self.tag.?.toSlice(), &self, if (self.content) |content| content.toSlice() else "" },
        );
        defer self.allocator.free(formatted_string);

        for (0..level) |_| {
            try out.append('\t');
        }

        try out.appendSlice(formatted_string);

        if (self.children) |children| {
            for (children.items) |child| {
                try child.getTree(level + 1, out);
            }
        }
    }

    pub fn findTags(self: Node, tag: String) []const *Node {
        var matching_nodes = std.ArrayList(*Node).init(self.allocator);
        defer matching_nodes.deinit();

        if (self.children) |children| {
            for (children.items) |child| {
                if (tag.equals(child.tag)) matching_nodes.append(child);
            }
        }
        return matching_nodes.toOwnedSlice() catch &[_]*Node{};
    }

    fn init(allocator: Allocator) Node {
        return Node{
            .allocator = allocator,
        };
    }

    fn deinitChildren(self: *Node) void {
        if (self.children) |*children| {
            for (children.items) |child| {
                child.deinit();
                self.allocator.destroy(child);
            }
            children.deinit();
        }
        self.children = null;
    }

    fn deinitContent(self: *Node) void {
        if (self.content) |*content| {
            content.deinit();
        }
        self.content = null;
    }

    fn deinit(self: *Node) void {
        if (self.tag) |*tag| {
            tag.deinit();
        }
        self.tag = null;

        self.deinitContent();
        self.deinitChildren();
        self.children = null;
        self.parent = null;
    }

    fn extract(self: *Node, html: String, start: usize) !usize {
        if (start >= html.len) return start; // handle edge-case: all content parsed.

        const result = try self.extractTag(html, start);
        if (result.extract_status == ExtractStatus.FINISHED) return result.last_index;
        var curr: usize = result.last_index;

        // Initialize variables so we don't have so in loop.
        self.children = std.ArrayList(*Node).init(self.allocator);
        errdefer self.deinitChildren();

        self.content = String.init(self.allocator);
        errdefer self.deinitContent();

        while (true) {
            const next_tag_index: usize = Node.ensureNonSpecial(html, html.findBeforeOther((curr + 1), tokens.TAG_START, tokens.TAG_END) catch return NodeError.IncompleteTag) catch return NodeError.IncompleteTag;

            // Extract any content not nested in another tag.
            try self.content.?.appendSlice(try html.getSlice((curr + 1), next_tag_index));
            self.content.?.strip();
            curr = next_tag_index;

            // Handle return case: no more nested tags.
            if (try html.at(curr + 1) == tokens.TAG_CLOSE_INDICATOR) {
                curr = html.findBeforeOther((curr + 1), tokens.TAG_END, tokens.TAG_START) catch return NodeError.IncompleteTag;
                break;
            }
            // Recursively extract nested tags.
            else {
                var child = try self.allocator.create(Node);
                try self.children.?.append(child);

                child.* = Node.init(self.allocator);
                child.parent = self;
                curr = try child.extract(html, curr);
            }
        }

        // Free/set unused variables as necessary.
        if (self.content.?.len == 0) self.deinitContent();
        if (self.children.?.items.len == 0) self.deinitChildren();

        return curr;
    }

    fn extractTag(self: *Node, html: String, start: usize) !Node.NodeExtractionResult {
        if (tokens.TAG_START != try html.at(start)) return NodeError.ExtractionError;
        const post_start = (Node.ensureNonSpecial(html, start) catch return NodeError.SpecialIndicatorError) + 1;

        // Get entire opening tag string (cleaning along the way).
        const tag_end = html.findBeforeOther(post_start, tokens.TAG_END, tokens.TAG_START) catch return NodeError.IncompleteTag catch {
            return NodeError.IncompleteTag;
        };

        var tag = try String.initWithValue(self.allocator, try html.getSlice(post_start, tag_end));
        tag.lstrip();

        // Get actual tag value (i.e. 'p', 'html', etc.). Tag params are not captured in this implementation.
        for (tag.toSlice(), 0..) |char, i| {
            if ((char == tokens.TAG_CLOSE_INDICATOR) or (constants.isWhitespace(char))) {
                try tag.remove(i, tag.len);
                break;
            }
        }

        var is_self_closing: bool = false;
        for (KNOWN_SELF_CLOSING_TAGS) |sct| {
            if (!std.mem.eql(u8, sct, tag.toSlice())) continue;

            is_self_closing = true;
            break;
        }

        self.tag = tag;
        return NodeExtractionResult{ .last_index = tag_end, .extract_status = if (is_self_closing) ExtractStatus.FINISHED else ExtractStatus.CONTINUE };
    }

    fn ensureNonSpecial(html: String, start: usize) !usize {
        var curr = start;
        // Skip comments and other "special" tags not parsed in this implementation.
        while (try html.at(curr + 1) == tokens.SPECIAL_INDICATOR) {
            curr += 2; // skip past the special indicator.

            if ((html.len > (curr + tokens.DOCTYPE_INDICATOR.len)) and
                (std.mem.eql(u8, try html.getSlice(curr, (curr + tokens.DOCTYPE_INDICATOR.len)), tokens.DOCTYPE_INDICATOR)))
            {
                curr = try html.findFrom(curr, tokens.TAG_START);
            } else if ((html.len > (curr + tokens.COMMENT_INDICATOR.len)) and
                (std.mem.eql(u8, try html.getSlice(curr, (curr + tokens.COMMENT_INDICATOR.len)), tokens.COMMENT_INDICATOR)))
            {
                while (true) {
                    curr = try html.findFrom(curr + 1, tokens.TAG_END);
                    if (std.mem.eql(u8, try html.getSlice((curr - tokens.COMMENT_INDICATOR.len), curr), tokens.COMMENT_INDICATOR)) break;
                }
                curr = try html.findFrom(curr, tokens.TAG_START);
            } else return NodeError.SpecialIndicatorError;
        }
        return curr;
    }
};

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

    fn appendSelfClosingTag(string: *String, tag: []const u8) !void {
        try string.append(tokens.TAG_START);
        try string.appendSlice(tag);
        try string.append(tokens.TAG_CLOSE_INDICATOR);
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

    try testing.expectEqual((html.len - 1), try node.extract(html, 0));
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

    try testing.expectEqual((html.len - 1), try node.extract(html, 0));
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

test "test invalid tag" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();
    const content: []const u8 = "Extract Me";

    const test_cases = [_][3][]const u8{
        [3][]const u8{ "<p", "</p>", "<pExtract Me</p>" },
        [3][]const u8{ "<p>", "/p>", "<p>Extract Me/p>" },
        [3][]const u8{ "<p>", "</p", "<p>Extract Me</p" },
    };

    for (test_cases) |case| {
        var html = String.init(allocator);
        defer html.deinit();

        const opening: []const u8 = case[0];
        const close: []const u8 = case[1];
        const exp_string: []const u8 = case[2];

        try html.appendSlice(opening);
        try html.appendSlice(content);
        try html.appendSlice(close);

        try testing.expectEqualStrings(exp_string, html.toSlice());

        var node = Node.init(allocator);
        defer node.deinit();

        try testing.expectError(Node.NodeError.IncompleteTag, node.extract(html, 0));
    }
}

test "test self closing tag" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();
    const parent_tag: []const u8 = "html";
    const self_closing_tag: []const u8 = "meta";
    var html = String.init(allocator);
    defer html.deinit();

    const nested_tags = [_][2][]const u8{
        [2][]const u8{ "p", "Extract Me" },
        [2][]const u8{ "span", "Hello World" },
        [2][]const u8{ "div", "Nice to meet you" },
    };

    try TestUtils.appendOpeningTag(&html, parent_tag);

    try html.append(constants.NEWLINE);
    try TestUtils.appendSelfClosingTag(&html, self_closing_tag);
    try html.append(constants.NEWLINE);

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

    try testing.expectEqualStrings("<html>\n<meta/>\n\n<p>Extract Me</p>\n\n<span>Hello World</span>\n\n<div>Nice to meet you</div>\n</html>", html.toSlice());
    var node = Node.init(allocator);
    defer node.deinit();

    try testing.expectEqual((html.len - 1), try node.extract(html, 0));
    try testing.expectEqualStrings(parent_tag, node.tag.?.toSlice());

    try testing.expectEqual(null, node.content);
    try testing.expectEqual(null, node.parent);
    try testing.expect(node.children != null);
    try testing.expectEqual((nested_tags.len + 1), node.children.?.items.len);

    const self_closing_tag_node = node.children.?.items[0];
    try testing.expectEqual(null, self_closing_tag_node.children);
    try testing.expectEqual(null, self_closing_tag_node.content);
    try testing.expectEqualStrings(self_closing_tag, self_closing_tag_node.tag.?.toSlice());

    for (node.children.?.items[1..node.children.?.items.len], nested_tags) |child_node, exp_values| {
        const exp_tag = exp_values[0];
        const exp_content = exp_values[1];

        try testing.expectEqualStrings(exp_tag, child_node.tag.?.toSlice());
        try testing.expectEqualStrings(exp_content, child_node.content.?.toSlice());
        try testing.expectEqual(&node, child_node.parent.?);
        try testing.expectEqual(null, child_node.children);
    }
}

const testing = std.testing;
test "test parse example doc" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();
    var html: String = try String.initWithValue(allocator,
        \\<!DOCTYPE html>
        \\<html>
        \\    <head>
        \\        <title>Title of the document</title>
        \\    </head>
        \\    <body>
        \\    The content of the document......
        \\    </body>
        \\</html>
    );
    defer html.deinit();

    var parser = Parser.init(allocator);
    defer parser.deinit();

    try parser.parse(html);

    var root = parser.root.?;

    try testing.expect(root.parent == null);
    try testing.expect(root.content == null);
    try testing.expectEqualStrings("html", root.tag.?.toSlice());
    try testing.expect(root.children != null);

    const elements = root.children.?;
    try testing.expectEqual(2, elements.items.len);
}
