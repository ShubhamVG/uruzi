// Copyright (c) 2026 Shubham LaV. All Rights Reserved.
//
// Email: lav@brainiacs.in
// GitHub: ShubhamVG

const std = @import("std");

const clap = @import("clap");

// TODO: Rewrite everything here: replace Param(Help) with inhouse type and inhouse comptime parser.

pub const params = clap.parseParamsComptime(
    \\-h, --help             Display this help and exit.
    \\    --width  <u32>     Canvas width.
    \\    --height <u32>     Canvas height.
    \\    --particles <u32>  Particle count.
    \\    --outline          Shows the image outline.
    \\<img_path>

    // TODO: Add show fps and set fps
    // \\    --show-fps         Show the FPS.
    // \\    --set-fps <u32>    Set the FPS.
);
pub const parsers = .{ .img_path = clap.parsers.string, .u32 = clap.parsers.int(u32, 10) };

pub fn printHelp(io: std.Io, file: std.Io.File) !void {
    var buffer: [512]u8 = undefined;
    var file_writer = file.writer(io, &buffer);
    const buffered_writer = &file_writer.interface;

    try buffered_writer.print("Usage: uruzi ", .{});
    try clap.usage(buffered_writer, clap.Help, &params);

    try buffered_writer.print("\n\nArguments:\n", .{});
    try clap.help(buffered_writer, clap.Help, &params, .{
        .description_on_new_line = false,
        .description_indent = 4,
        .indent = 0,
    });
    try buffered_writer.print("\n", .{});

    try buffered_writer.flush();
}
