const std = @import("std");
const vszip = @import("../vszip.zig");
const helper = @import("../helper.zig");
const process = @import("process/planeaverage.zig");

const vs = vszip.vs;
const vsh = vszip.vsh;
const zapi = vszip.zapi;
const math = std.math;

const allocator = std.heap.c_allocator;
pub const filter_name = "PlaneAverage";

const PlaneAverageData = struct {
    node1: ?*vs.Node,
    node2: ?*vs.Node,
    vi: *const vs.VideoInfo,
    exclude: process.Exclude,
    dt: helper.DataType,
    peak: f32,
    planes: [3]bool,
};

export fn planeAverageGetFrame(n: c_int, activation_reason: vs.ActivationReason, instance_data: ?*anyopaque, frame_data: ?*?*anyopaque, frame_ctx: ?*vs.FrameContext, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.C) ?*const vs.Frame {
    _ = frame_data;
    const d: *PlaneAverageData = @ptrCast(@alignCast(instance_data));

    if (activation_reason == .Initial) {
        vsapi.?.requestFrameFilter.?(n, d.node1, frame_ctx);
        if (d.node2) |node| {
            vsapi.?.requestFrameFilter.?(n, node, frame_ctx);
        }
    } else if (activation_reason == .AllFramesReady) {
        var src = zapi.Frame.init(d.node1, n, frame_ctx, core, vsapi);
        defer src.deinit();

        var ref: ?zapi.Frame = null;
        if (d.node2) |node| {
            ref = zapi.Frame.init(node, n, frame_ctx, core, vsapi);
            defer ref.?.deinit();
        }

        const dst = src.copyFrame();
        const props = dst.getPropertiesRW();

        var plane: u32 = 0;
        while (plane < d.vi.format.numPlanes) : (plane += 1) {
            if (!(d.planes[plane])) {
                continue;
            }

            const srcp = src.getReadPtr(plane);
            const w, const h, const stride = src.getDimensions(plane);
            var avg: f64 = undefined;

            if (ref == null) {
                avg = switch (d.dt) {
                    .U8 => process.average(u8, srcp, stride, w, h, d.exclude, d.peak),
                    .U16 => process.average(u16, srcp, stride, w, h, d.exclude, d.peak),
                    .F32 => process.average(f32, srcp, stride, w, h, d.exclude, d.peak),
                };
            } else {
                const refp = ref.?.getReadPtr(plane);
                const stats = switch (d.dt) {
                    .U8 => process.averageRef(u8, srcp, refp, stride, w, h, d.exclude, d.peak),
                    .U16 => process.averageRef(u16, srcp, refp, stride, w, h, d.exclude, d.peak),
                    .F32 => process.averageRef(f32, srcp, refp, stride, w, h, d.exclude, d.peak),
                };
                _ = vsapi.?.mapSetFloat.?(props, "psmDiff", stats.diff, .Append);
                avg = stats.avg;
            }
            _ = vsapi.?.mapSetFloat.?(props, "psmAvg", avg, .Append);
        }

        return dst.frame;
    }

    return null;
}

export fn planeAverageFree(instance_data: ?*anyopaque, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.C) void {
    _ = core;
    const d: *PlaneAverageData = @ptrCast(@alignCast(instance_data));
    switch (d.exclude) {
        .i => allocator.free(d.exclude.i),
        .f => allocator.free(d.exclude.f),
    }

    if (d.node2) |node| {
        vsapi.?.freeNode.?(node);
    }

    vsapi.?.freeNode.?(d.node1);
    allocator.destroy(d);
}

pub export fn planeAverageCreate(in: ?*const vs.Map, out: ?*vs.Map, user_data: ?*anyopaque, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.C) void {
    _ = user_data;
    var d: PlaneAverageData = undefined;

    var map = zapi.Map.init(in, out, vsapi);
    d.node1, d.vi = map.getNodeVi("clipa");
    d.node2, const vi2 = map.getNodeVi("clipb");
    helper.compareNodes(out, d.node1, d.node2, d.vi, vi2, filter_name, vsapi) catch return;

    d.dt = @enumFromInt(d.vi.format.bytesPerSample);
    d.peak = @floatFromInt(math.shl(i32, 1, d.vi.format.bitsPerSample) - 1);
    var nodes = [_]?*vs.Node{ d.node1, d.node2 };
    var planes = [3]bool{ true, false, false };
    helper.mapGetPlanes(in, out, &nodes, &planes, d.vi.format.numPlanes, filter_name, vsapi) catch return;
    d.planes = planes;

    const exclude_in = map.getIntArray("exclude");
    if (exclude_in) |ein| {
        if (d.dt == .F32) {
            d.exclude = process.Exclude{ .f = allocator.alloc(f32, ein.len) catch unreachable };
            for (d.exclude.f, ein) |*df, *ei| {
                df.* = @floatFromInt(ei.*);
            }
        } else {
            d.exclude = process.Exclude{ .i = allocator.alloc(i32, ein.len) catch unreachable };
            for (d.exclude.i, ein) |*di, *ei| {
                di.* = math.lossyCast(i32, ei.*);
            }
        }
    }

    const data: *PlaneAverageData = allocator.create(PlaneAverageData) catch unreachable;
    data.* = d;

    var deps1 = [_]vs.FilterDependency{
        vs.FilterDependency{
            .source = d.node1,
            .requestPattern = .StrictSpatial,
        },
    };

    var deps_len: c_int = deps1.len;
    var deps: [*]const vs.FilterDependency = &deps1;
    if (d.node2 != null) {
        var deps2 = [_]vs.FilterDependency{
            deps1[0],
            vs.FilterDependency{
                .source = d.node2,
                .requestPattern = if (d.vi.numFrames <= vi2.numFrames) .StrictSpatial else .General,
            },
        };

        deps_len = deps2.len;
        deps = &deps2;
    }

    vsapi.?.createVideoFilter.?(out, filter_name, d.vi, planeAverageGetFrame, planeAverageFree, .Parallel, deps, deps_len, data, core);
}
