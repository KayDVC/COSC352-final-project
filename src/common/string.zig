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
    pub fn lstrip(self: *String) !void {
        if (self._buffer == null) {
            return String.EmptyString;
        } else if (self._buffer.len == 0) {
            return;
        }
    }

    pub fn rstrip(self: *String) !void {
        if (self._buffer == null) {
            return String.EmptyString;
        } else if (self._buffer.len == 0) {
            return;
        }
    }

    pub fn strip(self: *String) !void {
        try self.lstrip();
        try self.rstrip();
    }

    pub fn find(self: String) !usize {
        _ = self;
    }

    // "Remove" from start (inclusive) to end (exclusive)
    fn remove(self: *String, start: usize, end: usize) !void {
        if ((start < 0) or (start > end) or (end > self.len)) {
            return StringError.InvalidIndex;
        } else if (self._buffer == null) {
            return StringError.EmptyString;
        }

        // Move all characters from end, end+1, self.len back n ("removed" chars) spaces.
        const difference = end - start;
        var curr_index = end;
        while (curr_index < self.len) : (curr_index += 1) {
            self._buffer[curr_index - difference] = self._buffer[curr_index];
        }
        self.len -= difference;
    }
};

// Tests
const testing = std.testing;

test "test basic init" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(gpa.deinit(), std.heap.Check.ok) catch @panic("String leak");

    const allocator = gpa.allocator();

    var string = String.init(allocator);
    defer string.deinit();

    try testing.expectEqual(string.allocator, allocator);
    try testing.expectEqual(string.len, 0);
    try testing.expectEqual(string._buffer, null);
    try testing.expectEqual(string._capacity, 0);
}

test "test init with capacity" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(gpa.deinit(), std.heap.Check.ok) catch @panic("String leak");

    const allocator = gpa.allocator();
    const initialCapacity: usize = 3;

    var string = try String.initReserve(allocator, initialCapacity);
    defer string.deinit();

    try testing.expectEqual(string.len, 0);
    try testing.expectEqual(string.allocator, allocator);
    try testing.expectEqual(string._capacity, initialCapacity);
    try testing.expectEqual(string._buffer.?.len, initialCapacity);
}

test "test init with value" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(gpa.deinit(), std.heap.Check.ok) catch @panic("String leak");

    const allocator = gpa.allocator();
    const buffer: []const u8 = "test";

    var string = try String.initWithValue(
        allocator,
        buffer,
    );
    defer string.deinit();

    try testing.expectEqual(string.len, buffer.len);
    try testing.expectEqual(string.allocator, allocator);
    try testing.expectEqual(string._capacity, buffer.len);
    try testing.expectEqualStrings(string._buffer.?, buffer);
}

test "test deinit obliterates memory & vars" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(gpa.deinit(), std.heap.Check.ok) catch @panic("String leak");

    const allocator = gpa.allocator();

    var string = String.init(allocator);
    string.deinit();
}

test "test split at newline" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expectEqual(gpa.deinit(), std.heap.Check.ok) catch @panic("String leak");

    const allocator = gpa.allocator();
    const buffer: []const u8 = "Hello\nWorld";

    var string = try String.initWithValue(
        allocator,
        buffer,
    );
    defer string.deinit();

    const arr = try string.split(allocator);
    defer allocator.free(arr);

    try testing.expectEqual(arr.len, 2);
    try testing.expectEqualStrings(arr[0], "Hello");
    try testing.expectEqualStrings(arr[1], "World");
}
