const std = @import("std");
const panic = std.debug.panic;

pub const VERSION = "0.1.0";

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

    /// Returns the ROM type based on the beginning char of the file extension
    pub fn fromChar(ch: u8) ?Self {
        return switch (ch) {
            'v' => .byte_swapped,
            'n' => .little_endian,
            'z' => .big_endian,
            else => null,
        };
    }
};

/// helper function to open an existing ROM file. The caller is expected to close this file when done.
pub fn openRom(path: []const u8) !std.fs.File {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const resolved_path = try std.fs.realpath(path, &buf);
    const fp = try std.fs.openFileAbsolute(resolved_path, .{ .mode = .read_only });
    return fp;
}

/// helper function to either create a ROM file for writing, or overwrite and open it if it still exists.
/// The caller is expected to close this file when done.
pub fn createRom(path: []const u8) !std.fs.File {
    return if (!std.fs.path.isAbsolute(path))
        try std.fs.cwd().createFile(path, .{})
    else
        try std.fs.createFileAbsolute(path, .{});
}

/// determine the actual ROM format from a file path.
pub fn determineFormatFromPath(path: []const u8) Error!RomType {
    const fp = openRom(path) catch |err| panic("could not open ROM at `{s}`: {any}", .{ path, err });
    defer fp.close();
    return determineFormatFromFile(&fp);
}

/// determine the actual ROM format from an `AnyReader`
pub fn determineFormatFromFile(file: *const std.fs.File) Error!RomType {
    file.seekTo(0) catch |err| panic("could not seek to beginning of file: {any}", .{err});
    const reader = file.reader();
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
pub fn endianSwap(in: *const std.fs.File, out: *const std.fs.File) void {
    @setEvalBranchQuota(2048);
    const CHUNKSIZE = 256; // each chunk is 4 bytes
    var new_chunk: [4 * CHUNKSIZE]u8 = undefined;

    in.seekTo(0) catch |err| panic("could not seek to beginning of file: {any}", .{err});
    out.seekTo(0) catch |err| panic("could not seek to beginning of file: {any}", .{err});

    while (true) {
        const old_chunk = in.reader().readBytesNoEof(CHUNKSIZE * 4) catch break;
        inline for (0..CHUNKSIZE) |chunk| {
            inline for (0..4) |i| {
                new_chunk[4 * chunk + i] = old_chunk[4 * chunk + (3 - i)];
            }
        }

        out.writer().writeAll(&new_chunk) catch panic("failed to write to writer during format conversion", .{});
    }
}

/// perform an byteswap (z64-v64 and vice-versa)
pub fn byteSwap(in: *const std.fs.File, out: *const std.fs.File) void {
    const CHUNKSIZE = 256; // each chunk is 2 bytes
    var new_chunk: [2 * CHUNKSIZE]u8 = undefined;

    in.seekTo(0) catch |err| panic("could not seek to beginning of file: {any}", .{err});
    out.seekTo(0) catch |err| panic("could not seek to beginning of file: {any}", .{err});

    while (true) {
        const old_chunk = in.reader().readBytesNoEof(CHUNKSIZE * 2) catch break;

        inline for (0..CHUNKSIZE) |chunk| {
            new_chunk[2 * chunk] = old_chunk[2 * chunk + 1];
            new_chunk[2 * chunk + 1] = old_chunk[2 * chunk];
        }

        out.writer().writeAll(&new_chunk) catch panic("failed to write to writer during format conversion", .{});
    }
}

/// perform both a byteswap and endianswap (n64-z64 and vice-versa)
pub fn byteEndianSwap(in: *const std.fs.File, out: *const std.fs.File) void {
    const CHUNKSIZE = 256; // each chunk is 4 bytes
    var new_chunk: [4 * CHUNKSIZE]u8 = undefined;

    in.seekTo(0) catch |err| panic("could not seek to beginning of file: {any}", .{err});
    out.seekTo(0) catch |err| panic("could not seek to beginning of file: {any}", .{err});

    while (true) {
        const old_chunk = in.reader().readBytesNoEof(CHUNKSIZE * 4) catch break;

        inline for (0..CHUNKSIZE) |chunk| {
            new_chunk[4 * chunk] = old_chunk[4 * chunk + 2];
            new_chunk[4 * chunk + 1] = old_chunk[4 * chunk + 3];
            new_chunk[4 * chunk + 2] = old_chunk[4 * chunk + 0];
            new_chunk[4 * chunk + 3] = old_chunk[4 * chunk + 1];
        }

        out.writer().writeAll(&new_chunk) catch panic("failed to write to writer during format conversion", .{});
    }
}

/// perform an endianswap (n64-z64 and vice-versa) from two file paths
pub fn endianSwapPath(in: []const u8, out: []const u8) void {
    const in_file = try openRom(in);
    const out_file = try openRom(out);

    defer in_file.close();
    defer out_file.close();

    return endianSwap(&in_file, &out_file);
}

/// perform an byteswap (z64-v64 and vice-versa) from two file paths
pub fn byteSwapPath(in: []const u8, out: []const u8) void {
    const in_file = try openRom(in);
    const out_file = try openRom(out);

    defer in_file.close();
    defer out_file.close();

    return byteSwap(&in_file, &out_file);
}

/// perform an endian and byteswap (n64-v64 and vice-versa) from two file paths
pub fn byteEndianSwapPath(in: []const u8, out: []const u8) void {
    const in_file = try openRom(in);
    const out_file = try openRom(out);

    defer in_file.close();
    defer out_file.close();

    return byteEndianSwap(&in_file, &out_file);
}

test "swap big endian to little endian" {
    endianSwapPath("baserom.us.z64", "baserom.us.n64");
}

test "swap big endian to byteswapped" {
    byteSwapPath("baserom.us.z64", "baserom.us.v64");
}

test "swap little endian to byteswapped" {
    byteEndianSwapPath("baserom.us.n64", "baserom.us.v64");
}

test "format of z64 rom" {
    const path = "./baserom.us.z64";
    const res = try determineFormatFromPath(path);
    try std.testing.expectEqual(res, RomType.big_endian);
}

test "format of n64 rom" {
    const path = "./baserom.us.n64";
    const res = try determineFormatFromPath(path);
    try std.testing.expectEqual(res, RomType.little_endian);
}

test "format of v64 rom" {
    const path = "./baserom.us.v64";
    const res = try determineFormatFromPath(path);
    try std.testing.expectEqual(res, RomType.byte_swapped);
}
