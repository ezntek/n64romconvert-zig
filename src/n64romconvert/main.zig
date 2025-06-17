const std = @import("std");

const clap = @import("clap");
const rc = @import("n64romconvert_lib");

const PARAMS = clap.parseParamsComptime(
    \\-h, --help          Display this message and exit.
    \\-f, --format <fmt>  Target ROM format
    \\<src>               Path to source ROM
    \\<dest>              Destination ROM (file type can be automatically detected)
);

pub fn help() !noreturn {
    const stderr = std.io.getStdErr().writer();

    try stderr.writeAll("\u{001b}[1mn64convert:\u{001b}[0m convert between N64 ROM formats\n");
    try stderr.writeAll("usage: ");
    try clap.usage(stderr, clap.Help, &PARAMS);
    try stderr.writeAll("\n");
    try clap.help(stderr, clap.Help, &PARAMS, .{});

    std.process.exit(0);
}

fn panic(comptime fmt: []const u8, args: anytype) noreturn {
    const stderr = std.io.getStdErr().writer();
    stderr.writeAll("\u{001b}[31;1mpanic: \u{001b}[0m") catch {};
    stderr.print(fmt, args) catch {};
    stderr.writeAll("\n") catch {};
    @panic("the program crashed with a fatal error.");
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    const stderr = std.io.getStdErr().writer();
    stderr.writeAll("\u{001b}[31;1merror: \u{001b}[0m") catch {};
    stderr.print(fmt, args) catch {};
    stderr.writeAll("\n") catch {};
    std.process.exit(1);
}

fn getPathExtension(path: []const u8) []const u8 {
    var i = path.len - 1;
    const dot_pos = while (i >= 0) : (i -= 1) {
        if (path[i] == '.')
            break i;
    };
    return path[dot_pos + 1 ..];
}

inline fn formatsEqualUnordered(x: rc.RomType, y: rc.RomType, a: rc.RomType, b: rc.RomType) bool {
    return (x == a and y == b) or (x == b and y == a);
}

fn convert(in_fmt: rc.RomType, out_fmt: rc.RomType, in: *const std.fs.File, out: *const std.fs.File) void {
    if (formatsEqualUnordered(in_fmt, out_fmt, .big_endian, .byte_swapped)) {
        rc.byteSwap(in, out);
    } else if (formatsEqualUnordered(in_fmt, out_fmt, .big_endian, .little_endian)) {
        rc.endianSwap(in, out);
    } else if (formatsEqualUnordered(in_fmt, out_fmt, .little_endian, .byte_swapped)) {
        rc.byteEndianSwap(in, out);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // parse args
    const parsers = comptime .{
        .src = clap.parsers.string,
        .dest = clap.parsers.string,
        .fmt = clap.parsers.string,
    };
    var diag = clap.Diagnostic{};

    var res = clap.parse(clap.Help, &PARAMS, parsers, .{
        .diagnostic = &diag,
        .allocator = alloc,
        .assignment_separators = "=",
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        std.process.exit(1);
    };

    defer res.deinit();

    if (res.args.help != 0) {
        try help();
    }

    // process args
    const in_path: []const u8 = if (res.positionals[0]) |arg|
        arg
    else
        try help();

    const out_path: []const u8 = if (res.positionals[1]) |arg|
        arg
    else
        try help();

    // open files
    //const in_path = std.fs.realpathAlloc(alloc, in_path_raw) catch |err| panic("could not resolve absolute path `{s}`: {any}", .{ in_path_raw, err });
    //const out_path = std.fs.realpathAlloc(alloc, out_path_raw) catch |err| panic("could not resolve absolute path `{s}`: {any}", .{ out_path_raw, err });

    //defer alloc.free(in_path);
    //defer alloc.free(out_path);

    const in_file = rc.openRom(in_path) catch fatal("could not open ROM at `{s}`!", .{in_path});
    const out_file = rc.createRom(out_path) catch fatal("could not create new ROM at `{s}`!", .{out_path});

    defer in_file.close();
    defer out_file.close();

    // conversion logic
    const target_format_s = if (res.args.format) |fmt|
        fmt
    else
        getPathExtension(out_path);

    // dont take a false positive of `file.v` or `file.z` etc
    if (!std.mem.eql(u8, target_format_s[target_format_s.len - 2 ..], "64")) {
        fatal("supplied target format `{s}`, but it is invalid", .{target_format_s});
    }

    const target_format = if (rc.RomType.fromChar(target_format_s[0])) |typ|
        typ
    else
        fatal("supplied target format `{s}`, but it is invalid", .{target_format_s});

    const src_format = rc.determineFormatFromFile(&in_file) catch |err| switch (err) {
        rc.Error.InvalidRomError => fatal("invalid input format {s}!", .{getPathExtension(in_path)}),
    };

    if (src_format == target_format) {
        fatal("will not convert between the same formats!", .{});
    }

    convert(src_format, target_format, &in_file, &out_file);
}
