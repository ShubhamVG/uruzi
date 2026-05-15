// Copyright (c) 2026 Shubham LaV. All Rights Reserved.
//
// Email: lav@brainiacs.in
// GitHub: ShubhamVG

const std = @import("std");

const bitmaster = @import("bitmaster.zig");
const img_proc = @import("img_proc.zig");
const physics = @import("physics.zig");

const Allocator = std.mem.Allocator;

pub const AnimationStatus = enum {
    playing,
    paused,
    none,
};

pub const AppState = struct {
    image_loaded: bool = false,
    show_outline: bool = false,

    img_w: u32,
    img_h: u32,

    edge_tolerance: u8 = 220,
    delta_sq: f32 = 10.0,

    canvas_w: u32,
    canvas_h: u32,

    particle_count: u32,

    img_bitmask: ?std.DynamicBitSet = null,
    neighbors_map: ?bitmaster.NeighborMap = null,

    particles: ?physics.ParticleSystem = null,

    fps: u8 = 30,
    anim_status: AnimationStatus = .none,
    footer_msg: ?[:0]const u8 = null, // TODO: move this out

    const Self = @This();

    pub fn init(canvas_w: u32, canvas_h: u32, particle_count: u32) Self {
        return .{
            .canvas_w = canvas_w,
            .canvas_h = canvas_h,
            .particle_count = particle_count,
            .img_w = undefined,
            .img_h = undefined,
        };
    }

    pub fn loadAndProcessImage(
        self: *Self,
        allocator: Allocator,
        io: std.Io,
        path: []const u8,
    ) img_proc.Error!void {
        var image = img_proc.loadImage(allocator, io, path) catch |err| switch (err) {
            img_proc.LoadError.Unsupported,
            img_proc.LoadError.FileNotFound,
            img_proc.LoadError.AccessDenied,
            img_proc.LoadError.OutOfMemory,
            => {
                return err;
            },
            else => return img_proc.LoadError.Failed,
        }; // will be deinited after potential resizing

        if (image.width != image.height) {
            var len: usize = undefined;
            var x: usize = undefined;
            var y: usize = undefined;

            if (image.width < image.height) {
                len = image.width;
                x = 0;
                y = (image.height - len) / 2;
            } else {
                len = image.height;
                x = (image.width - len) / 2;
                y = 0;
            }

            const cropped_img = try image.crop(allocator, .{
                .x = x,
                .y = y,
                .width = len,
                .height = len,
            });
            image.deinit(allocator);
            image = cropped_img;
        }

        // NOTE: IMAGE WILL BE SQUARE FROM HERE ONWARDS

        if (image.width > 400) {
            const new_w: usize = 400;
            const new_h: usize = new_w;
            // const new_w: usize = 400;
            // const h_to_w: f32 = @as(f32, @floatFromInt(image.height)) / @as(f32, @floatFromInt(image.width));
            // const new_h: usize = @intFromFloat(@as(f32, new_w) * h_to_w);

            const new_img = try img_proc.resize_small(allocator, &image, new_w, new_h);
            image.deinit(allocator);
            image = new_img;
        }
        defer image.deinit(allocator);

        self.img_w = @intCast(image.width);
        self.img_h = @intCast(image.height);

        const bitmask = img_proc.edgeFilteredBitmask(allocator, image, self.edge_tolerance) catch {
            return img_proc.LoadError.OutOfMemory;
        };

        if (bitmask.count() == 0) {
            return img_proc.LoadError.NoEdges;
        }

        self.img_bitmask = bitmask;
        const neighbor_map = try bitmaster.NeighborMap.initAndFill(allocator, bitmask, self.*);
        self.neighbors_map = neighbor_map;
        self.image_loaded = true;
    }

    pub fn loadParticles(self: *Self, allocator: Allocator, rng: std.Random) Allocator.Error!void {
        const particle_system = physics.ParticleSystem.init(allocator, rng, self) catch |err| {
            self.image_loaded = false;
            return err;
        };
        self.particles = particle_system;
    }

    /// Attempts to unload the particles' system.
    ///
    /// Safe to call even if no particle system is loaded.
    pub fn unloadParticles(self: *Self, allocator: Allocator) void {
        if (self.particles) |*p| {
            p.deinit(allocator);
            self.particles = null;
        }
    }

    /// Attempts to unload an image.
    ///
    /// Safe to call even if no image is loaded.
    pub fn unloadImage(self: *Self) void {
        self.image_loaded = false;

        if (self.img_bitmask) |*b| {
            b.deinit();
            self.img_bitmask = null;
        }
        if (self.neighbors_map) |*n| {
            n.deinit();
            self.neighbors_map = null;
        }
    }
};
