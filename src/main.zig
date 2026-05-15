// Copyright (c) 2026 Shubham LaV. All Rights Reserved.
//
// Email: lav@brainiacs.in
// GitHub: ShubhamVG

const builtin = @import("builtin");
const std = @import("std");

const clap = @import("clap");
const nfd = @import("nfd");
const rl = @import("raylib");
const rgui = @import("raygui");
const zigimg = @import("zigimg");

const app = @import("app.zig");
const bitmaster = @import("bitmaster.zig");
const cli = @import("cli.zig");
const img_proc = @import("img_proc.zig");
const physics = @import("physics.zig");

const Allocator = std.mem.Allocator;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    // CLI setup
    //
    // NOTE: It is okay for the argparsing to propagate error since it *will* be reported in the
    // terminal, and only programmers will [hopefully] be using it through the terminal (mainly
    // for testing purposes.)

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &cli.params, cli.parsers, init.minimal.args, .{
        .diagnostic = &diag,
        .allocator = gpa,
        .assignment_separators = "=",
    }) catch |err| {
        // TODO: Check if this fails on WASM cuz of stderr
        var buffer: [512]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(io, &buffer);
        const buffered_stderr = &stderr_writer.interface;
        try diag.report(buffered_stderr, err);
        try cli.printHelp(io, .stderr());
        std.process.exit(1);
    };
    defer res.deinit();

    // If help flag, print usage and exit.
    if (res.args.help != 0) {
        // TODO: Check if this fails on WASM cuz of stdout
        try cli.printHelp(io, .stdout());
        return;
    }

    const rng_impl: std.Random.IoSource = .{ .io = io };
    const rng = rng_impl.interface();

    var state = app.AppState.init(
        if (res.args.width) |width| width else 900,
        if (res.args.height) |height| height else 900,
        if (res.args.particles) |p_count| p_count else 900,
    );
    defer {
        state.unloadImage();
        state.unloadParticles(gpa);
    }

    if (res.args.outline != 0) {
        state.show_outline = true;
    }

    if (res.positionals[0]) |img_path| {
        procImgAndUpdateError(gpa, io, rng, &state, img_path);
    }

    // Raylib and gui stuff
    const panel_width = 250;
    const footer_height = 50;

    rl.setConfigFlags(.{ .msaa_4x_hint = true });
    rl.initWindow(
        @intCast(state.canvas_w + panel_width),
        @intCast(state.canvas_h + footer_height),
        "Uruzi",
    );
    defer rl.closeWindow();
    rl.setTargetFPS(30);

    var particles_slider_val: f32 = @floatFromInt(state.particle_count);
    var dropdown_opened = false;
    var dropdown_idx_val: i32 = 0;
    // var edge_tol_slider_val: f32 = @floatFromInt(state.edge_tolerance);

    while (!rl.windowShouldClose()) {
        // INPUT HANDLING
        if (rl.isKeyPressed(.space)) {
            state.anim_status = switch (state.anim_status) {
                .playing => .paused,
                .paused => .playing,
                .none => .none,
            };
        }

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.black);

        const line_thickness: f32 = 5.0;
        rl.drawLineEx(
            .{ .x = 0.0, .y = @floatFromInt(state.canvas_h) },
            .{ .x = @floatFromInt(state.canvas_w), .y = @floatFromInt(state.canvas_h) },
            line_thickness,
            .violet,
        ); // Footer line
        rl.drawLineEx(
            .{ .x = @floatFromInt(state.canvas_w), .y = 0.0 },
            .{ .x = @floatFromInt(state.canvas_w), .y = @floatFromInt(state.canvas_h + footer_height) },
            line_thickness,
            .violet,
        ); // Control panel separator

        if (state.footer_msg) |err_msg| {
            const font_size = 30;
            const pad = 12;
            const x: i32 = pad;
            const y: i32 = @intCast(state.canvas_h + pad);
            rl.drawText(err_msg, x, y, font_size, .ray_white);
        } // Error message

        const show_fps = true; // TODO: add to app_state
        if (show_fps) {
            const x: i32 = @intCast(state.canvas_w + 10);
            const y: i32 = 10;

            rl.drawText("FPS: ", x, y, 20, .lime);
            rl.drawFPS(x + 60, y);
        } // FPS Text

        const btn_start_x: f32 = @floatFromInt(state.canvas_w + 35);
        const btn_w: f32 = @floatFromInt(panel_width - 60);
        const btn_h: f32 = 30.0;

        const slider_start_x: f32 = @floatFromInt(state.canvas_w + 10);
        const slider_h: f32 = 20.0;
        const slider_box_w: f32 = @floatFromInt(panel_width - 20);
        const slider_box_h: f32 = 40.0;
        const box_slider_pad: f32 = 10.0;

        _ = rgui.groupBox(.{
            .x = slider_start_x,
            .y = 50.0,
            .width = slider_box_w,
            .height = slider_box_h,
        }, "Particles"); // Particles slider container
        const particles_count_being_edited = rgui.slider(.{
            .x = btn_start_x,
            .y = 50.0 + box_slider_pad,
            .width = @floatFromInt(panel_width - 80),
            .height = slider_h,
        }, "100", "5000", &particles_slider_val, 100.0, 5000.0) != 0; // Particles slider

        // NOTE: Only true if the slider value is being *moved*. Might be a rgui limitation
        // preventing it from checking if the slider is in a _hold_ mode.
        if (particles_count_being_edited) {
            if (state.anim_status == .playing) {
                state.anim_status = .paused;
            }
        } else if (@as(u32, @trunc(particles_slider_val)) != state.particle_count) {
            state.unloadParticles(gpa);
            state.particle_count = @trunc(particles_slider_val);

            if (state.image_loaded) {
                loadParticlesAndUpdateError(gpa, rng, &state);
            }
        }

        const pause_play_clicked = rgui.button(.{
            .x = btn_start_x,
            .y = 100.0,
            .width = btn_w,
            .height = btn_h,
        }, switch (state.anim_status) {
            .playing => "PAUSE",
            .paused => "PLAY",
            .none => "Play/Pause",
        }); // Upload Image Button
        if (pause_play_clicked) {
            state.anim_status = switch (state.anim_status) {
                .playing => .paused,
                .paused => .playing,
                .none => .none,
            };
        }

        const toggle_outline_clicked = rgui.button(.{
            .x = btn_start_x,
            .y = 140.0,
            .width = btn_w,
            .height = btn_h,
        }, if (state.show_outline) "HIDE IMAGE" else "SHOW IMAGE"); // Upload Image Button
        if (toggle_outline_clicked) {
            state.show_outline = !state.show_outline;
        }

        const dropdown_clicked = rgui.dropdownBox(.{
            .x = btn_start_x,
            .y = 180.0,
            .width = btn_w,
            .height = btn_h,
        }, "30;60", &dropdown_idx_val, dropdown_opened) != 0;
        if (dropdown_clicked) {
            // If dropdown was opened, then it assumed the FPS was changed.
            state.fps = switch (dropdown_idx_val) {
                0 => 30,
                else => 60,
                // TODO: add more FPS choices like MAX
            };
            rl.setTargetFPS(@intCast(state.fps));
            dropdown_opened = !dropdown_opened;
        }

        // _ = rgui.groupBox(.{
        //     .x = @floatFromInt(state.canvas_w + 10),
        //     .y = 220.0,
        //     .width = slider_box_w,
        //     .height = slider_box_h,
        // }, "Edge Tolerance"); // Edge tolerance container
        // const edge_tol_being_edited = rgui.slider(.{
        //     .x = btn_start_x,
        //     .y = 220.0 + box_slider_pad,
        //     .width = @floatFromInt(panel_width - 72),
        //     .height = 20.0,
        // }, "150", "250", &edge_tol_slider_val, 150.0, 250.0) != 0;
        // if (edge_tol_being_edited) {
        //     state.show_outline = true;

        //     if (@as(u8, @trunc(edge_tol_slider_val)) != state.edge_tolerance) {
        //         state.edge_tolerance = @trunc(edge_tol_slider_val);
        //     }
        // }

        const upload_btn_clicked = rgui.button(.{
            .x = btn_start_x,
            .y = @floatFromInt(state.canvas_h + 10),
            .width = btn_w,
            .height = btn_h,
        }, "Upload Image"); // Upload Image Button
        if (upload_btn_clicked) {
            // TODO: Add more supported formats.
            // TODO: Get the footer to say "loading image".
            const img_path = try nfd.openFileDialog("png,jpg,jpeg,qoi,bmp", null);
            if (img_path != null) {
                state.unloadImage();
                state.unloadParticles(gpa);
                procImgAndUpdateError(gpa, io, rng, &state, img_path.?);
            }
        }

        if (state.image_loaded) {
            if (state.show_outline) {
                const canvas_w_f32: f32 = @floatFromInt(state.canvas_w);
                const canvas_h_f32: f32 = @floatFromInt(state.canvas_h);
                const img_w_f32: f32 = @floatFromInt(state.img_w);
                const img_h_f32: f32 = @floatFromInt(state.img_h);
                const cell_w: f32 = canvas_w_f32 / img_w_f32;
                const cell_h: f32 = canvas_h_f32 / img_h_f32;

                var iterator = state.img_bitmask.?.iterator(.{ .kind = .set });
                while (iterator.next()) |idx| {
                    const idx_f32: f32 = @floatFromInt(idx);
                    const y: f32 = (idx_f32 / img_w_f32) * cell_h;
                    const x: f32 = @rem(idx_f32, img_w_f32) * cell_w;

                    rl.drawRectangle(
                        @trunc(x),
                        @trunc(y),
                        @trunc(cell_w),
                        @trunc(cell_h),
                        .purple,
                    );
                }
            }

            // Drawing the particles.
            const pos_slice: []rl.Vector2 = state.particles.?.soa.items(.pos);
            for (pos_slice) |pos| {
                rl.drawCircleV(pos, 1.5, .red);
            }

            if (state.anim_status == .playing) {
                const dt: f32 = 1.0 / @as(f32, @floatFromInt(state.fps));
                state.particles.?.update(state, rng, dt); // TODO: change this shit
            }
        }
    }
}

/// Loads image (resize if necessary), bitmask, neighbors, etc. Updates footer_msg if encounters error.
///
/// NOTE: Will pause the play.
fn procImgAndUpdateError(allocator: Allocator, io: std.Io, rng: std.Random, state: *app.AppState, img_path: []const u8) void {
    state.loadAndProcessImage(allocator, io, img_path) catch |err| switch (err) {
        img_proc.Error.OutOfMemory => {
            state.footer_msg = "ERROR: Out of memory.";
            return;
        },
        // NOTE: FileNotFound can only happen from bad CLI usage.
        img_proc.Error.FileNotFound, img_proc.LoadError.AccessDenied => {
            state.footer_msg = "ERROR: File not found or access denied.";
            return;
        },
        img_proc.Error.Unsupported => {
            state.footer_msg = "ERROR: File or format not supported.";
            return;
        },
        img_proc.Error.Failed => {
            state.footer_msg = "ERROR: Failed to load image.";
            return;
        },
        img_proc.Error.NoEdges => {
            state.footer_msg = "Exception: Image has no edges.";
            return;
        },
        else => unreachable,
    };

    state.footer_msg = null;
    loadParticlesAndUpdateError(allocator, rng, state);
}

/// Loads particles in the soa.
///
/// NOTE: Will pause the play.
fn loadParticlesAndUpdateError(allocator: Allocator, rng: std.Random, state: *app.AppState) void {
    state.loadParticles(allocator, rng) catch {
        state.footer_msg = "ERROR: Out of memory.";
        return;
    };

    state.anim_status = .paused;
}
