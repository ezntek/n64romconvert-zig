const std = @import("std");

const rc = @import("n64romconvert_lib");

fn endianSwap() void {
    const origpath = "baserom.us.z64";
    const fp = std.fs.cwd().openFile(origpath, .{ .mode = .read_only }) catch @panic("could not open file");
    defer fp.close();
    const reader = fp.reader().any();
    const out = std.fs.cwd().createFile("baserom.us.n64", .{}) catch @panic("could not open file");
    var bw = std.io.bufferedWriter(out.writer());
    const writer = bw.writer().any();

    rc.endianSwap(&reader, &writer);
}

fn byteSwap() void {
    const origpath = "baserom.us.z64";
    const fp = std.fs.cwd().openFile(origpath, .{ .mode = .read_only }) catch @panic("could not open file");
    defer fp.close();
    const reader = fp.reader().any();
    const out = std.fs.cwd().createFile("baserom.us.n64", .{}) catch @panic("could not open file");
    var bw = std.io.bufferedWriter(out.writer());
    const writer = bw.writer().any();

    rc.byteSwap(&reader, &writer);
}

fn benchmark() void {
    for (0..100) |_| {
        endianSwap();
    }
}

pub fn main() !void {
    benchmark();
    //byteSwap();
}
