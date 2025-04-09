//! A simple implementation of "dynamic" strings using C-style buffer management sans the bells and whistles.
const std = @import("std");
const constants = @import("../modules.zig").common.constants;

const Allocator = std.mem.Allocator;

pub const String = struct {
    len: usize = 0,
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

    /// Initializes the struct instance.
    pub fn init(allocator: Allocator) String {
        return String{
            .len = 0,
            .allocator = allocator,
        };
    }

    /// Initializes the struct instance, allocating some initial memory.
    ///
    /// Args:
    ///     allocator: the allocator that will dynamically allocate all memory.
    ///     capacity: the number of bytes to allocate after initializing the struct.
    pub fn initReserve(allocator: Allocator, capacity: usize) !String {
        var string = String.init(allocator);
        try string.alloc(capacity);
        return string;
    }

    /// Initializes the struct with some data. Data is copied and owned by the string.
    ///
    /// Args:
    ///     allocator: the allocator that will dynamically allocate all memory.
    ///     value: the value to store in the buffer.
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

    /// Returns all bytes in internal buffer.
    pub fn toSlice(self: *const String) []const u8 {
        return self.getSlice(0, self.len) catch &[_]u8{};
    }

    /// Returns bytes in internal buffer between start (inclusive) and end(exclusive) index.
    ///
    /// Args:
    ///     start: the start of the range to retrieve. 0-index.
    ///     end: the end of the range to retrieve.
    pub fn getSlice(self: String, start: usize, end: usize) StringError![]u8 {
        if (self._buffer == null) return StringError.EmptyString;
        if ((start >= self.len) or (end > self.len)) return StringError.InvalidIndex;

        return self._buffer.?[start..end];
    }

    /// Returns character at specified index.
    pub fn at(self: *const String, index: usize) StringError!u8 {
        if (index >= self.len) return StringError.InvalidIndex;
        return self._buffer.?[index];
    }

    /// Divides string by newline delimiter.
    ///
    /// Args:
    ///     allocator: the allocator that allocates all dynamic memory.
    pub fn split(self: *const String, allocator: Allocator) ![]String {
        return try self.splitAtChar(allocator, constants.NEWLINE);
    }

    /// Divides string by specified delimiter.
    ///
    /// Args:
    ///     allocator: the allocator that allocates all dynamic memory.
    ///     separator: the delimiter to split the string. Removed from new strings.
    pub fn splitAtChar(self: *const String, allocator: Allocator, separator: u8) ![]String {
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

    /// Removes whitespace chars (if any) from the start of the string.
    pub fn lstrip(self: *String) void {
        if (self.findFirstNonWhiteSpace(Position.START)) |end| {
            _ = self.remove(0, end) catch void;
        } else |err| {
            self.handleEmptyStringStrip(err);
        }
    }

    /// Removes whitespace chars (if any) from the end of the string.
    pub fn rstrip(self: *String) void {
        // Since find first uses zero-based indexing, and we want to include the char at the
        // index it finds, we need to increment its value by one.
        if (self.findFirstNonWhiteSpace(Position.END)) |start| {
            _ = self.remove((start + 1), self.len) catch void;
        } else |err| {
            self.handleEmptyStringStrip(err);
        }
    }

    /// Removes whitespace chars (if any) from both ends of the string.
    pub fn strip(self: *String) void {
        self.lstrip();
        self.rstrip();
    }

    /// Returns whether the specified char is in the string.
    pub fn contains(self: *const String, char: u8) bool {
        _ = self.find(char) catch return false;
        return true;
    }

    /// Returns the index of the specified char, if found, from the beginning of the string.
    pub fn find(self: *const String, char: u8) StringError!usize {
        return self.findFrom(0, char);
    }

    /// Returns the index of specified char only if it can be found after the specified
    /// index and is not after the other char
    ///
    /// Args:
    ///     start: the index to start the search.
    ///     to_find: the character to find.
    ///     other: a character that to find should be before.
    ///
    /// If other is found after start, it's effectively ignored.
    pub fn findBeforeOther(self: *const String, start: usize, to_find: u8, other: u8) StringError!usize {
        var other_index: usize = 0;

        // Get index of other character.
        if (self.findFrom(start, other)) |index| {
            other_index = index;
        } else |err| {
            switch (err) {
                StringError.CharNotFound => other_index = self.len, // other char not found. Allow char to be anywhere in the remaining string.
                else => return err,
            }
        }
        const char_index: usize = try self.findFrom(start, to_find);
        if (char_index > other_index) return StringError.InvalidIndex;

        return char_index;
    }

    /// Returns the index of a specified character if it exists in the string after the specified index;
    ///
    /// Args:
    ///     start: the index to start the search.
    ///     char: the character to find.
    pub fn findFrom(self: *const String, start: usize, char: u8) StringError!usize {
        if (self.len == 0) return StringError.EmptyString else if (start >= self.len) return StringError.InvalidIndex;
        for (start..self.len) |i| if (self._buffer.?[i] == char) return i;

        return StringError.CharNotFound;
    }

    /// Removes characters from start (inclusive) to end (exclusive)
    /// and shifts remaining characters to fill space.
    pub fn remove(self: *String, start: usize, end: usize) StringError!void {
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

    /// Adds character the end of the string.
    pub fn append(self: *String, char: u8) !void {
        if (self._buffer == null) {
            try self.alloc(_GROWTH_RATE);
        } else if (self.len == self._capacity) {
            try self.realloc();
        }
        self._buffer.?[self.len] = char;
        self.len += 1;
    }

    /// Adds slice to the end of the string.
    pub fn appendSlice(self: *String, chars: []const u8) !void {
        for (chars) |char| try self.append(char);
    }

    /// Returns whether the two strings have the same value.
    pub fn equals(self: *const String, other: *const ?String) bool {
        if (other.* == null and self.len == 0) {
            return true;
        } else if (other.* == null or self.len != other.*.?.len) {
            return false;
        }
        return std.mem.eql(u8, self.toSlice(), other.*.?.toSlice());
    }

    fn alloc(self: *String, size: usize) !void {
        self._buffer = try self.allocator.alloc(u8, size);
        self._capacity = size;
    }
    fn realloc(self: *String) !void {
        const new_capacity = self._capacity * _GROWTH_RATE;
        self._buffer = try self.allocator.realloc(self._buffer.?, new_capacity);
        self._capacity = new_capacity;
    }

    fn findFirstNonWhiteSpace(self: *const String, position: String.Position) StringError!usize {
        if (self._buffer == null or self.len == 0) return StringError.EmptyString;

        if (position == Position.START) {
            for (0..self.len) |j| if (!constants.isWhitespace(self._buffer.?[j])) return j;
        } else {
            var i: usize = self.len;
            for (0..self.len) |_| {
                i -= 1;
                if (!constants.isWhitespace(self._buffer.?[i])) return (i);
            }
        }
        return StringError.CharNotFound;
    }

    /// Couldn't be bothered to deal with Zig's overly verbose syntax.
    fn handleEmptyStringStrip(self: *String, err: StringError) void {
        switch (err) {
            StringError.CharNotFound => { // Empty String, just "remove" all.
                _ = self.remove(0, self.len) catch void;
            },
            else => {
                // intentionally empty.
            },
        }
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

    // Test empty string doesn't throw error.
    var string = try String.initWithValue(allocator, "   ");
    defer string.deinit();

    string.lstrip();
    try testing.expectEqual(0, string.len);
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

    // Test empty string doesn't throw error.
    var string = try String.initWithValue(allocator, "   ");
    defer string.deinit();

    string.rstrip();
    try testing.expectEqual(0, string.len);
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

    // Test empty string doesn't throw error.
    var string = try String.initWithValue(allocator, "   ");
    defer string.deinit();

    string.strip();
    try testing.expectEqual(0, string.len);
}

test "test find" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();

    var alphabet: String = try String.initWithValue(allocator, "abcdefghijklmnopqrstuvqxyzABCDEFGHIJKLMNOPQRSTUVWXYZ");
    defer alphabet.deinit();

    const test_cases = [_][2]u8{
        [2]u8{ 'f', 5 },
        [2]u8{ 'z', 25 },
        [2]u8{ 'a', 0 },
        [2]u8{ 'o', 14 },
        [2]u8{ 'Z', 51 },
        [2]u8{ 'A', 26 },
    };

    for (test_cases) |case| {
        const to_find: u8 = case[0];
        const exp_index: u8 = case[1];
        try testing.expectEqual(exp_index, try alphabet.find(to_find));
    }

    try alphabet.remove(28, 29); // remove 'C'
    try testing.expectError(String.StringError.CharNotFound, alphabet.find('C'));
}

test "test find from index" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();

    var alphabet: String = try String.initWithValue(allocator, "abcdefghijklmnopqrstuvqxyzabcdefghijklmnopqrstuvqxyz");
    defer alphabet.deinit();

    const test_cases = [_][3]u8{
        [3]u8{ 'f', 20, 31 },
        [3]u8{ 'z', 26, 51 },
        [3]u8{ 'a', 0, 0 },
        [3]u8{ 'o', 2, 14 },
    };

    for (test_cases) |case| {
        const to_find: u8 = case[0];
        const start: u8 = case[1];
        const exp_index: u8 = case[2];
        try testing.expectEqual(exp_index, try alphabet.findFrom(start, to_find));
    }

    try alphabet.remove(31, 32); // remove second 'f'
    try testing.expectError(String.StringError.CharNotFound, alphabet.findFrom(26, 'f'));
    try testing.expectError(String.StringError.InvalidIndex, alphabet.findFrom(51, 'x'));

    var empty_string: String = String.init(allocator);
    defer empty_string.deinit();

    try testing.expectError(String.StringError.EmptyString, empty_string.findFrom(0, 'b'));
}

test "test find before other" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();

    var alphabet: String = try String.initWithValue(allocator, "abcdefghijklmnopqrstuvqxyzABCDEFGHIJKLMNOPQRSTUVWXYZ");
    defer alphabet.deinit();

    const success_cases = [_][4]u8{
        [4]u8{ 'f', 'Z', 0, 5 },
        [4]u8{ 'z', 'Z', 0, 25 },
        [4]u8{ 'a', 'Z', 0, 0 },
        [4]u8{ 'o', 'Z', 0, 14 },
        [4]u8{ 'e', 'e', 0, 4 },
        [4]u8{ 'F', '*', 0, 31 },
    };

    const failure_cases_other_before_char = [_][3]u8{
        [3]u8{ 'A', 'a', 0 },
        [3]u8{ 'e', 'b', 0 },
    };
    const failure_cases_char_not_found = [_][3]u8{
        [3]u8{ 'f', 'Z', 20 },
        [3]u8{ '*', 'Z', 0 },
    };

    for (success_cases) |case| {
        const to_find: u8 = case[0];
        const other: u8 = case[1];
        const start: u8 = case[2];
        const exp_index: u8 = case[3];

        try testing.expectEqual(exp_index, try alphabet.findBeforeOther(start, to_find, other));
    }

    for (failure_cases_other_before_char) |case| {
        const to_find: u8 = case[0];
        const other: u8 = case[1];
        const start: u8 = case[2];
        try testing.expectError(String.StringError.InvalidIndex, alphabet.findBeforeOther(start, to_find, other));
    }

    for (failure_cases_char_not_found) |case| {
        const to_find: u8 = case[0];
        const other: u8 = case[1];
        const start: u8 = case[2];
        try testing.expectError(String.StringError.CharNotFound, alphabet.findBeforeOther(start, to_find, other));
    }
}

test "test append - single, no initial values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();
    var string: String = String.init(allocator);
    defer string.deinit();

    const chars = [_]u8{ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h' };

    for (chars, 1..) |char, exp_len| {
        try string.append(char);
        try testing.expectEqual(exp_len, string.len);
        try testing.expectEqual(char, string.at(string.len - 1));
    }
}

test "test append - single, initial values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();
    var string: String = try String.initWithValue(allocator, "ZYXWVUT");
    defer string.deinit();

    const chars = [_]u8{ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h' };

    for (chars, (string.len + 1)..) |char, exp_len| {
        try string.append(char);
        try testing.expectEqual(exp_len, string.len);
        try testing.expectEqual(char, string.at(string.len - 1));
    }
}

test "test append - multi, no initial values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();
    var string = String.init(allocator);
    defer string.deinit();

    const test_cases = [_][]const u8{ "foo", "bar", "baz", "deadbeef", "baddcafe" };

    var exp_len: usize = 0;
    for (test_cases) |case| {
        exp_len += case.len;
        try string.appendSlice(case);
        try testing.expectEqual(exp_len, string.len);
        try testing.expectEqualStrings(case, try string.getSlice((string.len - case.len), string.len));
    }
}

test "test append - multi, initial values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();
    var string: String = try String.initWithValue(allocator, "ZYXWVUT");
    defer string.deinit();

    const test_cases = [_][]const u8{ "foo", "bar", "baz", "deadbeef", "baddcafe" };

    var exp_len: usize = string.len;
    for (test_cases) |case| {
        exp_len += case.len;
        try string.appendSlice(case);
        try testing.expectEqual(exp_len, string.len);
        try testing.expectEqualStrings(case, try string.getSlice((string.len - case.len), string.len));
    }
}

test "test equals - non-equal" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();

    const test_cases = [_][2][]const u8{
        [2][]const u8{ "foo", "fo" },
        [2][]const u8{ "ba", "bar" },
        [2][]const u8{ "teSt", "test" },
    };

    for (test_cases) |case| {
        var string1: String = try String.initWithValue(allocator, case[0]);
        defer string1.deinit();

        var string2: String = try String.initWithValue(allocator, case[1]);
        defer string2.deinit();

        try testing.expectEqual(false, string1.equals(@ptrCast(&string2)));
    }

    var empty_string = String.init(allocator);
    defer empty_string.deinit();

    var non_empty_string = try String.initWithValue(allocator, "Hello World");
    defer non_empty_string.deinit();

    try testing.expectEqual(false, empty_string.equals(@ptrCast(&non_empty_string)));
}

test "test equals - equals" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(std.heap.Check.ok, gpa.deinit()) catch @panic("String leak");

    const allocator = gpa.allocator();

    const test_cases = [_][2][]const u8{
        [2][]const u8{ "foo", "foo" },
        [2][]const u8{ "bar", "bar" },
        [2][]const u8{ "test", "test" },
    };

    for (test_cases) |case| {
        var string1: String = try String.initWithValue(allocator, case[0]);
        defer string1.deinit();

        var string2: String = try String.initWithValue(allocator, case[1]);
        defer string2.deinit();

        try testing.expectEqual(true, string1.equals(@ptrCast(&string2)));
    }

    var empty_string1 = String.init(allocator);
    defer empty_string1.deinit();

    var empty_string2 = String.init(allocator);
    defer empty_string2.deinit();

    try testing.expectEqual(true, empty_string1.equals(@ptrCast(&empty_string2)));
}
