const std = @import("std");

const clap = @import("clap");
const rc = @import("n64romconvert_lib");

const VERSION = "0.2.0";

const PARAMS = clap.parseParamsComptime(
    \\-h, --help          Display this message and exit.
    \\-V, --version       Print the version
    \\-q, --quiet         Suppress output messages
    \\-f, --format <fmt>  Specify explicit target ROM format
    \\-t, --type   <fmt>  Specify explicit target ROM format (duplicate of --format)
    \\<src>               Path to source ROM
    \\<dest>              Destination ROM (file type can be automatically detected)
);

fn printVersion(writer: *const std.io.AnyWriter) void {
    writer.print("version {s} (library version {s})\n", .{ VERSION, rc.VERSION }) catch {};
}

fn help() !noreturn {
    const stderr = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr);
    const writer = bw.writer();

    try writer.writeAll("\u{001b}[1mn64romconvert:\u{001b}[0m convert between N64 ROM formats\n");
    try writer.writeAll(" " ** ("n64romconvert: ").len);
    printVersion(&writer.any());
    try writer.writeAll("usage: ");
    try clap.usage(writer, clap.Help, &PARAMS);
    try writer.writeAll("\n");
    try clap.help(writer, clap.Help, &PARAMS, .{});
    try bw.flush();

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

fn printConvertInfo(in: rc.RomType, out: rc.RomType, out_name: []const u8) void {
    const stdout = std.io.getStdOut().writer();
    stdout.print("\u{001b}[36;1mrom type:\u{001b}[0m\t{s} (\u{001b}[1m{c}64\u{001b}[0m)\n", .{ @tagName(in), in.getChar() }) catch {};
    stdout.print("\u{001b}[36;1mout type:\u{001b}[0m\t{s} (\u{001b}[1m{c}64\u{001b}[0m)\n", .{ @tagName(out), out.getChar() }) catch {};
    stdout.print("\u{001b}[32;1mnew file name:\u{001b}[0m\t{s}\n", .{out_name}) catch {};
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

    if (res.args.version != 0) {
        printVersion(&std.io.getStdOut().writer().any());
        std.process.exit(0);
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

    const in_file = rc.openRom(in_path) catch fatal("could not open ROM at `{s}`!", .{in_path});
    const out_file = rc.createRom(out_path) catch fatal("could not create new ROM at `{s}`!", .{out_path});

    defer in_file.close();
    defer out_file.close();

    // conversion logic
    const target_format_s = if (res.args.format) |fmt|
        fmt
    else if (res.args.type) |typ|
        typ
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

    if (res.args.quiet == 0) {
        const out_name = std.fs.path.basename(out_path);
        printConvertInfo(src_format, target_format, out_name);
    }

    rc.convert(src_format, target_format, &in_file, &out_file);
}
