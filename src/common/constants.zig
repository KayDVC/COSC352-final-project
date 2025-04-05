pub const NEWLINE: u8 = '\n';
pub const TAB: u8 = '\t';
pub const SPACE: u8 = ' ';

pub const WHITESPACE = struct {
    const Self = @This();
    const chars = [_]u8{ NEWLINE, TAB, SPACE };

    pub fn contains(char: u8) bool {
        for (Self.chars) |c| if (c == char) return true;
        return false;
    }
};
