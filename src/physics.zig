// Copyright (c) 2026 Shubham LaV. All Rights Reserved.
//
// Email: lav@brainiacs.in
// GitHub: ShubhamVG

const std = @import("std");

const rl = @import("raylib");

const app = @import("app.zig");
const bitmaster = @import("bitmaster.zig");

const Allocator = std.mem.Allocator;

pub const Particle = struct {
    pos: rl.Vector2 = .{ .x = 0.0, .y = 0.0 },
    vel: rl.Vector2 = .{ .x = 0.0, .y = 0.0 },
    acc: rl.Vector2 = .{ .x = 0.0, .y = 0.0 },
    dest: ?rl.Vector2 = null,
    chase_pixel_idx: ?usize = null,
};

pub const ParticleSystem = struct {
    soa: std.MultiArrayList(Particle).Slice,

    const Self = @This();

    pub fn init(allocator: Allocator, rng: std.Random, app_state: *app.AppState) Allocator.Error!Self {
        var unowned_soa = std.MultiArrayList(Particle){};
        try unowned_soa.ensureTotalCapacity(allocator, @intCast(app_state.particle_count));

        // Assign random position, then pick a random set bit (which represents image border pixel)
        // and calculate the velocity of the particles to run towards said set bit location.
        for (0..app_state.particle_count) |_| {
            const canvas_w_f32: f32 = @floatFromInt(app_state.canvas_w);
            const canvas_h_f32: f32 = @floatFromInt(app_state.canvas_h);
            const img_w: usize = @intCast(app_state.img_w);
            const img_h: usize = @intCast(app_state.img_h);

            const px = rng.float(f32) * canvas_w_f32;
            const py = rng.float(f32) * canvas_h_f32;
            const pos = rl.Vector2{ .x = px, .y = py };

            const pixel_idx = bitmaster.randomBitmaskIndex(rng, app_state.img_bitmask.?) catch unreachable;
            const cell_w: f32 = canvas_w_f32 / @as(f32, @floatFromInt(img_w));
            const cell_h: f32 = canvas_h_f32 / @as(f32, @floatFromInt(img_h));

            const dest_y: f32 = @as(f32, @floatFromInt(pixel_idx / img_w)) * cell_h +
                0.5 * cell_h; // Offset for centering
            const dest_x: f32 = @as(f32, @floatFromInt(pixel_idx % img_w)) * cell_w +
                0.5 * cell_w; // Offset for centering

            const dest = rl.Vector2.init(dest_x, dest_y);
            const vel = dest.subtract(pos).normalize().scale(50.0);

            unowned_soa.appendAssumeCapacity(.{
                .pos = pos,
                .vel = vel,
                .dest = dest,
                .chase_pixel_idx = pixel_idx,
            });
        }

        const soa = unowned_soa.toOwnedSlice();
        return .{ .soa = soa };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.soa.deinit(allocator);
    }

    pub fn update(self: *Self, app_state: app.AppState, rng: std.Random, dt: f32) void {
        // Updating the particles via the SOA.
        const positions: []rl.Vector2 = self.soa.items(.pos);
        const velocities: []rl.Vector2 = self.soa.items(.vel);
        const destinations: []?rl.Vector2 = self.soa.items(.dest);
        const pixel_indicies: []?usize = self.soa.items(.chase_pixel_idx);

        for (positions, velocities, destinations, pixel_indicies) |*pos, *vel, *dest, *pixel_idx| {
            // Wrap if goes out of screen.
            pos.* = pos.add(vel.scale(dt));
            if (pos.x < 0.0) {
                pos.x = @as(f32, @floatFromInt(app_state.canvas_w)) - 0.0001;
            } else if (pos.x >= @as(f32, @floatFromInt(app_state.canvas_w))) {
                pos.x = 0.0;
            }
            if (pos.y < 0.0) {
                pos.y = @as(f32, @floatFromInt(app_state.canvas_h)) - 0.0001;
            } else if (pos.y >= @as(f32, @floatFromInt(app_state.canvas_h))) {
                pos.y = 0.0;
            }

            // If pixel is almost near the pixel, then it has reached its destination. Update the
            // pixel to be chased to be a neighbor pixel.
            if (dest.* != null and dest.*.?.subtract(pos.*).lengthSqr() <= app_state.delta_sq) {
                const neighbors = app_state.neighbors_map.?.get(pixel_idx.*.?).?;

                const new_pixel_idx = bitmaster.randomBitmaskIndex(rng, neighbors) catch {
                    dest.* = null;
                    pixel_idx.* = null;
                    vel.* = .zero();
                    continue;
                };

                const screen_w_f32: f32 = @floatFromInt(app_state.canvas_w);
                const screen_h_f32: f32 = @floatFromInt(app_state.canvas_h);
                const cell_w: f32 = screen_w_f32 / @as(f32, @floatFromInt(app_state.img_w));
                const cell_h: f32 = screen_h_f32 / @as(f32, @floatFromInt(app_state.img_h));

                const dest_y: f32 = @as(f32, @floatFromInt(new_pixel_idx / app_state.img_w)) * cell_h +
                    0.5 * cell_h; // Offset for centering
                const dest_x: f32 = @as(f32, @floatFromInt(new_pixel_idx % app_state.img_w)) * cell_w +
                    0.5 * cell_w; // Offset for centering

                const new_dest = rl.Vector2.init(dest_x, dest_y);
                const new_vel = new_dest.subtract(pos.*).normalize().scale(30.0);

                dest.* = new_dest;
                pixel_idx.* = new_pixel_idx;
                vel.* = new_vel;
            }
        }
    }
};
