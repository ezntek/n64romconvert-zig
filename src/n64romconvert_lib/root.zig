const std = @import("std");
const panic = std.debug.panic;

const Error = error{
    InvalidRomError,
};

pub const RomType = enum { byte_swapped, little_endian, big_endian };

fn openRom(path: []const u8) std.fs.File {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const resolved_path = std.fs.realpath(path, &buf) catch panic("could not resolve absolute path {s}", .{path});
    const fp = std.fs.openFileAbsolute(resolved_path, .{ .mode = .read_only }) catch |err| panic("could not open file: {any}", .{err});
    return fp;
}

pub fn determineFormatFromFile(path: []const u8) Error!RomType {
    const fp = openRom(path);
    defer fp.close();
    return determineFormatFromReader(&fp.reader().any());
}

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

pub fn endianSwap(in: *const std.io.AnyReader, out: *const std.io.AnyWriter) void {
    const CHUNKSIZE = 256; // each chunk is 4 bytes
    while (true) {
        const old_chunk = in.readBytesNoEof(CHUNKSIZE * 4) catch break;
        var new_chunk: [4 * CHUNKSIZE]u8 = undefined;

        @setEvalBranchQuota(2048);
        inline for (0..CHUNKSIZE) |chunk| {
            inline for (0..4) |i| {
                new_chunk[4 * chunk + i] = old_chunk[4 * chunk + (3 - i)];
            }
        }

        out.writeAll(&new_chunk) catch @panic("arstarst");
    }
}

pub fn byteSwap(in: *const std.io.AnyReader, out: *const std.io.AnyWriter) void {
    const CHUNKSIZE = 256; // each chunk is 2 bytes
    while (true) {
        const old_chunk = in.readBytesNoEof(CHUNKSIZE * 2) catch break;
        var new_chunk: [2 * CHUNKSIZE]u8 = undefined;

        inline for (0..CHUNKSIZE) |chunk| {
            new_chunk[2 * chunk] = old_chunk[2 * chunk + 1];
            new_chunk[2 * chunk + 1] = old_chunk[2 * chunk];
        }

        out.writeAll(&new_chunk) catch @panic("arstarst");
    }
}

test "swap big endian to little endian" {
    const origpath = "baserom.us.z64";
    const fp = try std.fs.cwd().openFile(origpath, .{ .mode = .read_only });
    defer fp.close();
    const reader = fp.reader().any();
    const out = try std.fs.cwd().createFile("baserom.us.n64", .{});
    const writer = out.writer().any();

    std.debug.print("format of {s}: {any}\n", .{ origpath, try determineFormatFromReader(&reader) });

    fp.seekTo(0) catch @panic("arst");

    endianSwap(&reader, &writer);
}

test "swap big endian to byteswapped" {
    const origpath = "baserom.us.z64";
    const fp = try std.fs.cwd().openFile(origpath, .{ .mode = .read_only });
    defer fp.close();
    const reader = fp.reader().any();
    const out = try std.fs.cwd().createFile("baserom.us.n64", .{});
    const writer = out.writer().any();

    std.debug.print("format of {s}: {any}\n", .{ origpath, try determineFormatFromReader(&reader) });

    fp.seekTo(0) catch @panic("arst");

    byteSwap(&reader, &writer);
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
