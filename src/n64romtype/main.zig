const std = @import("std");

const clap = @import("clap");
const rc = @import("n64romconvert_lib");

const PARAMS = clap.parseParamsComptime(
    \\-h, --help        Display this message and exit.
    \\<romfile>             
);

pub fn help() !noreturn {
    const stderr = std.io.getStdErr().writer();

    try stderr.writeAll("\u{001b}[1mn64romtype:\u{001b}[0m check the type of an N64 ROM\n");
    try stderr.writeAll("usage: ");
    try clap.usage(stderr, clap.Help, &PARAMS);
    try stderr.writeAll("\n");
    try clap.help(stderr, clap.Help, &PARAMS, .{});

    std.process.exit(0);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const parsers = comptime .{
        .romfile = clap.parsers.string,
    };
    var diag = clap.Diagnostic{};

    var res = clap.parse(clap.Help, &PARAMS, parsers, .{
        .diagnostic = &diag,
        .allocator = alloc,
        .assignment_separators = "=",
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };

    defer res.deinit();

    if (res.args.help != 0) {
        try help();
    }

    if (res.positionals[0]) |arg| {
        const typ = rc.determineFormatFromPath(arg) catch |err| switch (err) {
            rc.Error.InvalidRomError => std.debug.panic("ROM is invalid", .{}),
        };

        const stdout = std.io.getStdOut().writer();
        try stdout.print("\u{001b}[36;1mtype:\u{001b}[0m {s} (\u{001b}[1m{c}64\u{001b}[0m)\n", .{ @tagName(typ), typ.getChar() });
    } else {
        try help();
    }
}
