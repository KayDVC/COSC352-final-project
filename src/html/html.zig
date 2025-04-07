const html_parser = @import("parser.zig");
pub const tokens = @import("tokens.zig");

pub const Parser = html_parser.Parser;
pub const Node = html_parser.Node;

comptime {
    _ = html_parser;
    _ = tokens;
}
