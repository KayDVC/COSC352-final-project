const std = @import("std");
const local = @import("../modules.zig");

const html = local.html;
const String = local.common.String;

const Allocator = std.mem.Allocator;
const Node = html.Node;

const Parser = struct {
    allocator: Allocator,
    root: ?*Node,

    pub fn init(allocator: Allocator) Parser {
        return Parser{ .allocator = allocator, .root = null };
    }

    pub fn deinit(self: *Parser) void {
        if (self.root) |root| {
            root.deinit();
        }
        self.root = null;
    }

    pub fn parse(self: *Parser, content: *String) void {
        _ = self;
        _ = content;
    }
};
