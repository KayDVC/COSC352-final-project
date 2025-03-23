//! A simple implementation of "dynamic" strings using C-style buffer management sans the bells and whistles.
const std = @import("std");
const constants = @import("../modules.zig").common.constants;

const Allocator = std.mem.Allocator;

pub const String = struct {
    len: usize,
    allocator: Allocator,

    // To hell with Zig and it's lack of visibility modifiers.
    _buffer: ?[]u8 = null,
    _capacity: usize = 0,

    const _GROWTH_RATE: usize = 2;

    pub const StringError = error{
        InvalidIndex,
        EmptyString,
        CharNotFound,
    };

    const Position = enum {
        START,
        END,
    };

    pub fn init(allocator: Allocator) String {
        return String{
            .len = 0,
            .allocator = allocator,
        };
    }

    pub fn initReserve(allocator: Allocator, capacity: usize) !String {
        var string = String.init(allocator);
        string._buffer = try string.allocator.alloc(u8, capacity);
        string._capacity = capacity;

        return string;
    }

    pub fn initWithValue(allocator: Allocator, value: []const u8) !String {
        var string = try String.initReserve(allocator, value.len);
        @memcpy(string._buffer.?, value);
        string.len = value.len;

        return string;
    }

    pub fn deinit(self: *String) void {
        // Free allocated memory as necessary.
        if (self._buffer) |buffer| {
            self.allocator.free(buffer);
        }
        self.* = undefined;
    }

    pub fn toSlice(self: String) []u8 {
        if (self._buffer) |buffer| {
            return buffer[0..self.len];
        }
        return &[_]u8{};
    }

    pub fn split(self: *String, allocator: Allocator) ![]String {
        return try self.splitAtChar(allocator, constants.NEWLINE);
    }

    pub fn splitAtChar(self: *String, allocator: Allocator, separator: u8) ![]String {
        if (self._buffer) |buffer| {
            var array = std.ArrayList(String).init(allocator);
            defer array.deinit();

            var last_start: usize = 0;
            for (buffer, 0..) |char, i| {
                if (char == separator) {
                    try array.append(try String.initWithValue(allocator, buffer[last_start..i]));
                    last_start = i + 1;
                } else if (((i + 1) == buffer.len) and (last_start != buffer.len)) {
                    try array.append(try String.initWithValue(allocator, buffer[last_start..buffer.len]));
                }
            }

            return try array.toOwnedSlice();
        }

        return StringError.EmptyString;
    }

    // TODO
    pub fn lstrip(self: *String) void {
        if (self.findFirstNonWhiteSpace(Position.START)) |end| {
            _ = self.remove(0, end) catch void;
        } else |_| {}
    }

    pub fn rstrip(self: *String) void {
        // Since find first uses zero-based indexing, and we want to include the char at the
        // index it finds, we need to increment its value by one.
        if (self.findFirstNonWhiteSpace(Position.END)) |start| {
            _ = self.remove((start + 1), self.len) catch void;
        } else |_| {}
    }

    pub fn strip(self: *String) void {
        self.lstrip();
        self.rstrip();
    }

    pub fn find(self: String, char: u8) String.StringError!usize {
        if (self._buffer == null or self._buffer.len == 0) return StringError.EmptyString;

        for (self._buffer, 0..) |c, i| {
            if (c == char) {
                return i;
            }
        }

        return StringError.CharNotFound;
    }

    // "Remove" from start (inclusive) to end (exclusive)
    fn remove(self: *String, start: usize, end: usize) String.StringError!void {
        if (self._buffer == null or self.len == 0) {
            return StringError.EmptyString;
        } else if ((start < 0) or (start > end) or (end > self.len)) {
            return StringError.InvalidIndex;
        }

        // Move all characters from end, end+1, self.len back n ("removed" chars) spaces.
        const difference = end - start;
        var curr_index = end;
        while (curr_index < self.len) : (curr_index += 1) {
            self._buffer.?[curr_index - difference] = self._buffer.?[curr_index];
        }
        self.len -= difference;
    }

    fn findFirstNonWhiteSpace(self: String, position: String.Position) String.StringError!usize {
        if (self._buffer == null or self._buffer.?.len == 0) return StringError.EmptyString;

        const whitespace_chars = struct {
            const Self = @This();
            const chars = [_]u8{ constants.NEWLINE, constants.TAB, constants.SPACE };

            fn contains(char: u8) bool {
                for (Self.chars) |c| if (c == char) return true;
                return false;
            }
        };

        if (position == Position.START) {
            for (0..self.len) |j| if (!whitespace_chars.contains(self._buffer.?[j])) return j;
        } else {
            var i = self.len - 1;
            for (0..self.len) |_| {
                if (!whitespace_chars.contains(self._buffer.?[i])) return (i);
                i -= 1;
            }
        }
        return StringError.CharNotFound;
    }
};

// Tests
const testing = std.testing;

test "test basic init" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();

    var string = String.init(allocator);
    defer string.deinit();

    try testing.expectEqual(allocator, string.allocator);
    try testing.expectEqual(0, string.len);
    try testing.expectEqual(null, string._buffer);
    try testing.expectEqual(0, string._capacity);
}

test "test init with capacity" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();
    const initialCapacity: usize = 3;

    var string = try String.initReserve(allocator, initialCapacity);
    defer string.deinit();

    try testing.expectEqual(0, string.len);
    try testing.expectEqual(allocator, string.allocator);
    try testing.expectEqual(initialCapacity, string._capacity);
    try testing.expectEqual(initialCapacity, string._buffer.?.len);
}

test "test init with value" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();
    const buffer: []const u8 = "test";

    var string = try String.initWithValue(
        allocator,
        buffer,
    );
    defer string.deinit();

    try testing.expectEqual(allocator, string.allocator);
    try testing.expectEqual(buffer.len, string.len);
    try testing.expectEqual(buffer.len, string._capacity);
    try testing.expectEqualStrings(buffer, string._buffer.?);
}

test "test deinit obliterates memory & vars" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();

    var string = String.init(allocator);
    string.deinit();
}

test "test split at newline" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();
    const buffer: []const u8 = "Hello\nWorld";

    var string = try String.initWithValue(
        allocator,
        buffer,
    );
    defer string.deinit();

    var arr = try string.split(allocator);
    defer {
        for (arr) |*s| {
            s.deinit();
        }
        allocator.free(arr);
    }

    try testing.expectEqual(2, arr.len);
    try testing.expectEqualStrings("Hello", arr[0].toSlice());
    try testing.expectEqualStrings("World", arr[1].toSlice());
}

test "test lstrip" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();

    const test_cases = [_][2][]const u8{
        [2][]const u8{ "test", "test" },
        [2][]const u8{ " test", "test" },
        [2][]const u8{ "   test", "test" },
        [2][]const u8{ "\ntest", "test" },
        [2][]const u8{ "\ttest", "test" },
        [2][]const u8{ "\t\ntest", "test" },
    };

    for (test_cases) |case| {
        const exp = case[1];
        const in = case[0];

        var string = try String.initWithValue(allocator, in);
        defer string.deinit();

        string.lstrip();
        try testing.expectEqual(exp.len, string.len);
        try testing.expectEqual(in.len, string._capacity);
        try testing.expectEqualStrings(exp, string.toSlice());
    }
}

test "test rstrip" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();

    const test_cases = [_][2][]const u8{
        [2][]const u8{ "test", "test" },
        [2][]const u8{ "test ", "test" },
        [2][]const u8{ "test   ", "test" },
        [2][]const u8{ "test\n", "test" },
        [2][]const u8{ "test\t", "test" },
        [2][]const u8{ "test\t\n", "test" },
    };

    for (test_cases) |case| {
        const exp = case[1];
        const in = case[0];

        var string = try String.initWithValue(allocator, in);
        defer string.deinit();

        string.rstrip();
        try testing.expectEqual(exp.len, string.len);
        try testing.expectEqual(in.len, string._capacity);
        try testing.expectEqualStrings(exp, string.toSlice());
    }
}

test "test strip" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();

    const test_cases = [_][2][]const u8{
        // left side
        [2][]const u8{ "test", "test" },
        [2][]const u8{ " test", "test" },
        [2][]const u8{ "   test", "test" },
        [2][]const u8{ "\ntest", "test" },
        [2][]const u8{ "\ttest", "test" },
        [2][]const u8{ "\t\ntest", "test" },

        // right side
        [2][]const u8{ "test ", "test" },
        [2][]const u8{ "test ", "test" },
        [2][]const u8{ "test   ", "test" },
        [2][]const u8{ "test\n", "test" },
        [2][]const u8{ "test\t", "test" },
        [2][]const u8{ "test\t\n", "test" },

        // both
        [2][]const u8{ "test", "test" },
        [2][]const u8{ " test ", "test" },
        [2][]const u8{ "   test  \n ", "test" },
        [2][]const u8{ "\ntest\t", "test" },
        [2][]const u8{ "\ttest\n ", "test" },
        [2][]const u8{ "\t \ntest\t\n\t  ", "test" },
    };

    for (test_cases) |case| {
        const exp = case[1];
        const in = case[0];

        var string = try String.initWithValue(allocator, in);
        defer string.deinit();

        string.strip();
        try testing.expectEqual(exp.len, string.len);
        try testing.expectEqual(in.len, string._capacity);
        try testing.expectEqualStrings(exp, string.toSlice());
    }
}
