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

    pub fn init(allocator: Allocator) String {
        return String{
            .len = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *String) void {
        // Free allocated memory as necessary.
        if (self._buffer) |buffer| {
            self.allocator.free(buffer);
        }
    }

    pub fn initWithValue(allocator: Allocator, value: []u8) String {
        return String{ .len = value.len, .allocator = allocator, ._capacity = value.len, ._buffer = value };
    }

    pub fn initReserve(allocator: Allocator, capacity: usize) !String {
        const string = &String.init(allocator);
        string._buffer = try string.allocator.alloc(u8, capacity);
        string._capacity = capacity;

        return string.*;
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
        var strings: []String = &[_]String{};

        if (self._buffer) |buffer| {
            var array = std.ArrayList(String).init(allocator);
            defer array.deinit();

            var last_start: usize = 0;
            for (buffer, 0..) |char, i| {
                if (char == separator) {
                    try array.append(String.initWithValue(allocator, buffer[last_start..i]));
                    last_start = i + 1;
                } else if (((i + 1) == buffer.len) and (last_start != buffer.len)) {
                    try array.append(String.initWithValue(allocator, buffer[last_start..buffer.len]));
                }
            }

            strings = try array.toOwnedSlice();
        }

        return strings;
    }

    // TODO
    pub fn strip(self: *String) !void {
        _ = self;
    }
    pub fn find(self: String) !usize {
        _ = self;
    }
};
