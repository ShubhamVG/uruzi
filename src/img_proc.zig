// Copyright (c) 2026 Shubham LaV. All Rights Reserved.
//
// Email: lav@brainiacs.in
// GitHub: ShubhamVG

const std = @import("std");

const zigimg = @import("zigimg");
const zignal = @import("zignal");

const Allocator = std.mem.Allocator;

pub const LoadError = error{
    Failed,
    NoEdges,
} || Allocator.Error || zigimg.Image.Error || zigimg.Image.ReadError || std.Io.File.OpenError;

pub const ResizeError = error{IncompatibleDimension} || Allocator.Error || zigimg.Image.ConvertError;

pub const Error = LoadError || ResizeError;

pub fn loadImage(allocator: Allocator, io: std.Io, path: []const u8) LoadError!zigimg.Image {
    var read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
    return try zigimg.Image.fromFilePath(allocator, io, path, read_buffer[0..]);
}

/// Grayscales the image, runs it through a sobel, returns the bitmask.
pub fn edgeFilteredBitmask(
    allocator: Allocator,
    image: zigimg.Image,
    tolerance: u8,
) Allocator.Error!std.DynamicBitSet {
    var grayscaled: []u8 = try allocator.alloc(u8, image.width * image.height);
    defer allocator.free(grayscaled);

    var i: usize = 0;
    var iterator = image.iterator();
    while (iterator.next()) |color| {
        // NOTE: y will never cross 1.0
        const y = (color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722) * color.a;
        const gray_u8: u8 = @intFromFloat(y * 255.0);
        grayscaled[i] = gray_u8;
        i += 1;
    }

    const sobelled = try sobel(allocator, grayscaled, image.width, image.height);
    defer allocator.free(sobelled);

    const size = image.width * image.height;
    var bitmask = try std.DynamicBitSet.initEmpty(allocator, size);
    for (0.., sobelled) |bitidx, v| {
        if (v >= tolerance) {
            bitmask.set(bitidx);
        }
    }

    return bitmask;
}

fn sobel(
    allocator: Allocator,
    noalias grayscaled: []u8,
    width: usize,
    height: usize,
) Allocator.Error![]u8 {
    var buffer = try allocator.alloc(u8, grayscaled.len);

    // Zero out the edges (defaults to 0xAA)
    @memset(buffer[0 .. width + 1], 0); // Top edge and the very left of the next row
    @memset(buffer[(height - 1) * width - 1 ..], 0); // Bottom edge and the very right of the prev row

    // Two at a time; like this:
    //   ==========x
    //   x==========
    for (2..height - 1) |y| {
        const start = (y * width) - 1;
        @memset(buffer[start .. start + 2], 0);
    }

    // for (0..width) |x| {
    //     const top = x;
    //     const bottom = (height - 1) * width + x;
    //     buffer[top] = 0;
    //     buffer[bottom] = 0;
    // }

    // for (1..height) |y| {
    //     const left = y * width;
    //     const right = (y + 1) * width - 1;
    //     buffer[left] = 0;
    //     buffer[right] = 0;
    // }

    // Everything guaranteed to be in bounds. The "hot loop".
    for (1..height - 1) |y| {
        for (1..width - 1) |x| {
            const up = y - 1;
            const down = y + 1;
            const left = x - 1;
            const right = x + 1;

            // NOTE: Do not remove the zero-values. Kernel might be tweaked with in the future.
            const lu: i16 = @intCast(grayscaled[left + up * width]);
            const cu: i16 = @intCast(grayscaled[x + up * width]);
            const ru: i16 = @intCast(grayscaled[right + up * width]);
            const lc: i16 = @intCast(grayscaled[left + y * width]);
            const cc: i16 = @intCast(grayscaled[x + y * width]);
            const rc: i16 = @intCast(grayscaled[right + y * width]);
            const ld: i16 = @intCast(grayscaled[left + down * width]);
            const cd: i16 = @intCast(grayscaled[x + down * width]);
            const rd: i16 = @intCast(grayscaled[right + down * width]);

            const gx =
                (-1 * lu) + (0 * cu) + (1 * ru) +
                (-2 * lc) + (0 * cc) + (2 * rc) +
                (-1 * ld) + (0 * cd) + (1 * rd);
            const gy =
                (-1 * lu) + (-2 * cu) + (-1 * ru) +
                (0 * lc) + (0 * cc) + (0 * rc) +
                (1 * ld) + (2 * cd) + (1 * rd);
            const g = @abs(gx) + @abs(gy);
            const g_u8: u8 = if (g > 255) 255 else @intCast(g);

            buffer[x + y * width] = g_u8;
        }
    }

    return buffer;
}

/// Return a scaled down version of the input image by mapping the avg of a rectangular kernel from
/// the bigger input image to the scaled down output/return image.
pub fn resize_small(allocator: Allocator, image: *zigimg.Image, w: usize, h: usize) ResizeError!zigimg.Image {
    if (w >= image.width or h >= image.height) {
        return ResizeError.IncompatibleDimension;
    }

    image.convert(allocator, .rgba32) catch |err| switch (err) {
        zigimg.Image.ConvertError.NoConversionNeeded => {},
        else => {
            return err;
        },
    };

    var new_img = try zigimg.Image.create(allocator, w, h, .rgba32);

    const img_w_f32: f32 = @floatFromInt(image.width);
    const img_h_f32: f32 = @floatFromInt(image.height);
    const w_f32: f32 = @floatFromInt(w);
    const h_f32: f32 = @floatFromInt(h);
    const dx: f32 = img_w_f32 / w_f32;
    const dy: f32 = img_h_f32 / h_f32;

    for (0..w) |x| {
        for (0..h) |y| {
            const x_f32: f32 = @floatFromInt(x);
            const y_f32: f32 = @floatFromInt(y);
            const img_start_x: usize = @round(x_f32 * dx);
            const img_end_x: usize = @round(x_f32 * dx + dx);
            const img_start_y: usize = @round(y_f32 * dy);
            const img_end_y: usize = @round(y_f32 * dy + dy);
            const area: f32 = @floatFromInt((img_end_x - img_start_x) * (img_end_y - img_start_y));

            var r: f32 = 0.0;
            var g: f32 = 0.0;
            var b: f32 = 0.0;
            var a: f32 = 0.0;
            for (img_start_x..img_end_x) |x2| {
                for (img_start_y..img_end_y) |y2| {
                    const index = y2 * image.width + x2;
                    const pixel = image.pixels.rgba32[index];
                    r += @floatFromInt(pixel.r);
                    g += @floatFromInt(pixel.g);
                    b += @floatFromInt(pixel.b);
                    a += @floatFromInt(pixel.a);
                }
            }

            r /= area;
            g /= area;
            b /= area;
            a /= area;

            const index = y * w + x;
            new_img.pixels.rgba32[index] = .{
                .r = @trunc(r),
                .g = @trunc(g),
                .b = @trunc(b),
                .a = @trunc(a),
            };
        }
    }

    return new_img;
}
