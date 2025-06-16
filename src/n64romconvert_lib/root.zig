const std = @import("std");
const panic = std.debug.panic;

pub const Error = error{
    InvalidRomError,
};

pub const RomType = enum {
    byte_swapped, // ByteSwapped
    little_endian, // LittleEndian
    big_endian, // BigEndian

    const Self = RomType;

    /// Returns either `n`, `v`, or `z` depending on the format (n64, v64, z64)
    pub fn getChar(self: *const Self) u8 {
        return switch (self.*) {
            .byte_swapped => 'v',
            .little_endian => 'n',
            .big_endian => 'z',
        };
    }

    /// Writes the string name of the ROM type to buf. Asserts `buf.len >= 12`,
    /// as that is the longest possible string.
    pub fn getString(self: *const Self, buf: []u8) []const u8 {
        std.debug.assert(buf.len >= 12);
        const src = switch (self.*) {
            .byte_swapped => "ByteSwapped",
            .little_endian => "LittleEndian",
            .big_endian => "BigEndian",
        };
        std.mem.copyForwards(u8, buf, src);
        return buf[0..src.len];
    }

    /// Returns the string name of the ROM type as an owned, allocated slice.
    pub fn getStringAlloc(self: *const Self, alloc: std.mem.Allocator) ![]const u8 {
        const src = switch (self.*) {
            .byte_swapped => "ByteSwapped",
            .little_endian => "LittleEndian",
            .big_endian => "BigEndian",
        };
        return try alloc.dupe(u8, src);
    }
};

/// helper function to open a ROM file. The caller is expected to close this file when done.
pub fn openRom(path: []const u8) !std.fs.File {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const resolved_path = std.fs.realpath(path, &buf) catch panic("could not resolve absolute path {s}", .{path});
    const fp = try std.fs.openFileAbsolute(resolved_path, .{ .mode = .read_write });
    return fp;
}

/// determine the actual ROM format from a file path
pub fn determineFormatFromFile(path: []const u8) Error!RomType {
    const fp = openRom(path) catch |err| panic("could not open ROM at `{s}`: {any}", .{ path, err });
    defer fp.close();
    return determineFormatFromReader(&fp.reader().any());
}

/// determine the actual ROM format from an `AnyReader`
pub fn determineFormatFromReader(reader: *const std.io.AnyReader) Error!RomType {
    const bytes = reader.readBytesNoEof(4) catch |err| panic("could not read data from reader: {any}", .{err});
    if (std.mem.eql(u8, bytes[0..4], &.{ 0x37, 0x80, 0x40, 0x12 })) {
        return .byte_swapped;
    } else if (std.mem.eql(u8, bytes[0..4], &.{ 0x40, 0x12, 0x37, 0x80 })) {
        return .little_endian;
    } else if (std.mem.eql(u8, bytes[0..4], &.{ 0x80, 0x37, 0x12, 0x40 })) {
        return .big_endian;
    } else {
        return Error.InvalidRomError;
    }
}

/// perform an endianness-swap (z64-v64 and vice-versa)
pub fn endianSwap(in: *const std.io.AnyReader, out: *const std.io.AnyWriter) void {
    @setEvalBranchQuota(2048);
    const CHUNKSIZE = 256; // each chunk is 4 bytes
    var new_chunk: [4 * CHUNKSIZE]u8 = undefined;

    loop: {
        const old_chunk = in.readBytesNoEof(CHUNKSIZE * 4) catch break :loop;

        inline for (0..CHUNKSIZE) |chunk| {
            inline for (0..4) |i| {
                new_chunk[4 * chunk + i] = old_chunk[4 * chunk + (3 - i)];
            }
        }

        out.writeAll(&new_chunk) catch panic("failed to write to writer during format conversion", .{});
    }
}

/// perform an byteswap (z64-v64 and vice-versa)
pub fn byteSwap(in: *const std.io.AnyReader, out: *const std.io.AnyWriter) void {
    const CHUNKSIZE = 256; // each chunk is 2 bytes
    var new_chunk: [2 * CHUNKSIZE]u8 = undefined;

    loop: {
        const old_chunk = in.readBytesNoEof(CHUNKSIZE * 2) catch break :loop;

        inline for (0..CHUNKSIZE) |chunk| {
            new_chunk[2 * chunk] = old_chunk[2 * chunk + 1];
            new_chunk[2 * chunk + 1] = old_chunk[2 * chunk];
        }

        out.writeAll(&new_chunk) catch panic("failed to write to writer during format conversion", .{});
    }
}

/// perform both a byteswap and endianswap (n64-z64 and vice-versa)
pub fn byteEndianSwap(in: *const std.io.AnyReader, out: *const std.io.AnyWriter) void {
    const CHUNKSIZE = 256; // each chunk is 4 bytes
    var new_chunk: [4 * CHUNKSIZE]u8 = undefined;

    loop: {
        const old_chunk = in.readBytesNoEof(CHUNKSIZE * 4) catch break :loop;

        inline for (0..CHUNKSIZE) |chunk| {
            new_chunk[4 * chunk] = old_chunk[4 * chunk + 2];
            new_chunk[4 * chunk + 1] = old_chunk[4 * chunk + 3];
            new_chunk[4 * chunk + 2] = old_chunk[4 * chunk + 0];
            new_chunk[4 * chunk + 3] = old_chunk[4 * chunk + 1];
        }

        out.writeAll(&new_chunk) catch panic("failed to write to writer during format conversion", .{});
    }
}

/// perform an endianswap (n64-z64 and vice-versa) from two file paths
pub fn endianSwapFile(in: []const u8, out: []const u8) void {
    const in_file = openRom(in);
    const out_file = openRom(out);

    in_file.seekTo(0) catch panic("could not seek to beginning of file", .{});
    out_file.seekTo(0) catch panic("could not seek to beginning of file", .{});

    defer in_file.close();
    defer out_file.close();

    return endianSwap(&in_file.reader().any(), &out_file.writer().any());
}

/// perform an byteswap (z64-v64 and vice-versa) from two file paths
pub fn byteSwapFile(in: []const u8, out: []const u8) void {
    const in_file = openRom(in);
    const out_file = openRom(out);

    in_file.seekTo(0) catch panic("could not seek to beginning of file", .{});
    out_file.seekTo(0) catch panic("could not seek to beginning of file", .{});

    defer in_file.close();
    defer out_file.close();

    return byteSwap(&in_file.reader().any(), &out_file.writer().any());
}

/// perform an endian and byteswap (n64-v64 and vice-versa) from two file paths
pub fn byteEndianSwapFile(in: []const u8, out: []const u8) void {
    const in_file = openRom(in);
    const out_file = openRom(out);

    in_file.seekTo(0) catch panic("could not seek to beginning of file", .{});
    out_file.seekTo(0) catch panic("could not seek to beginning of file", .{});

    defer in_file.close();
    defer out_file.close();

    return byteEndianSwap(&in_file.reader().any(), &out_file.writer().any());
}

test "swap big endian to little endian" {
    endianSwapFile("baserom.us.z64", "baserom.us.n64");
}

test "swap big endian to byteswapped" {
    byteSwapFile("baserom.us.z64", "baserom.us.v64");
}

test "swap little endian to byteswapped" {
    byteEndianSwapFile("baserom.us.n64", "baserom.us.v64");
}

test "format of z64 rom" {
    const path = "./baserom.us.z64";
    const res = try determineFormatFromFile(path);
    try std.testing.expectEqual(res, RomType.big_endian);
}

test "format of n64 rom" {
    const path = "./baserom.us.n64";
    const res = try determineFormatFromFile(path);
    try std.testing.expectEqual(res, RomType.little_endian);
}

test "format of v64 rom" {
    const path = "./baserom.us.v64";
    const res = try determineFormatFromFile(path);
    try std.testing.expectEqual(res, RomType.byte_swapped);
}

test "ROM string conversion" {
    const rt = RomType.big_endian;
    var buf: [12]u8 = undefined;
    const res = rt.getString(&buf);
    try std.testing.expectEqualStrings(res, "BigEndian");
}
