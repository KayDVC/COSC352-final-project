pub const NEWLINE: u8 = '\n';
pub const TAB: u8 = '\t';
pub const SPACE: u8 = ' ';

pub fn isWhitespace(char: u8) bool {
    for ([_]u8{ NEWLINE, TAB, SPACE }) |c| if (c == char) return true;
    return false;
}
