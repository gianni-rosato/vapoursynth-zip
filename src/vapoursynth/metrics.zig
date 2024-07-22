const std = @import("std");
const vszip = @import("../vszip.zig");
const helper = @import("../helper.zig");
const ssimulacra2 = @import("../filters/metric_ssimulacra2.zig");
const xpsnr = @cImport({
    @cInclude("../filters/metric_xpsnr.h");
});

const vs = vszip.vs;
const vsh = vszip.vsh;
const zapi = vszip.zapi;
const math = std.math;

const allocator = std.heap.c_allocator;
pub const filter_name = "Metrics";

const Data = struct {
    node1: ?*vs.Node,
    node2: ?*vs.Node,
};

const Mode = enum(i32) {
    SSIMU2 = 0,
    XPSNR = 1,
};

fn ssimulacra2GetFrame(n: c_int, activation_reason: vs.ActivationReason, instance_data: ?*anyopaque, frame_data: ?*?*anyopaque, frame_ctx: ?*vs.FrameContext, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.C) ?*const vs.Frame {
    _ = frame_data;
    const d: *Data = @ptrCast(@alignCast(instance_data));

    if (activation_reason == .Initial) {
        vsapi.?.requestFrameFilter.?(n, d.node1, frame_ctx);
        vsapi.?.requestFrameFilter.?(n, d.node2, frame_ctx);
    } else if (activation_reason == .AllFramesReady) {
        const src1 = vsapi.?.getFrameFilter.?(n, d.node1, frame_ctx);
        const src2 = vsapi.?.getFrameFilter.?(n, d.node2, frame_ctx);
        defer vsapi.?.freeFrame.?(src1);
        defer vsapi.?.freeFrame.?(src2);

        const width: usize = @intCast(vsapi.?.getFrameWidth.?(src1, 0));
        const height: usize = @intCast(vsapi.?.getFrameHeight.?(src1, 0));
        const stride: usize = @intCast(vsapi.?.getStride.?(src1, 0));
        const dst = vsapi.?.copyFrame.?(src2, core).?;

        const srcp1 = [3][*]const u8{
            vsapi.?.getReadPtr.?(src1, 0),
            vsapi.?.getReadPtr.?(src1, 1),
            vsapi.?.getReadPtr.?(src1, 2),
        };

        const srcp2 = [3][*]const u8{
            vsapi.?.getReadPtr.?(src2, 0),
            vsapi.?.getReadPtr.?(src2, 1),
            vsapi.?.getReadPtr.?(src2, 2),
        };

        const val = ssimulacra2.process(
            srcp1,
            srcp2,
            stride,
            width,
            height,
        );

        _ = vsapi.?.mapSetFloat.?(vsapi.?.getFramePropertiesRW.?(dst), "_SSIMULACRA2", val, .Replace);
        return dst;
    }
    return null;
}

fn xpsnrGetFrame(n: c_int, activation_reason: vs.ActivationReason, instance_data: ?*anyopaque, frame_data: ?*?*anyopaque, frame_ctx: ?*vs.FrameContext, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.C) ?*const vs.Frame {
    _ = frame_data;
    const d: *Data = @ptrCast(@alignCast(instance_data));

    if (activation_reason == .Initial) {
        vsapi.?.requestFrameFilter.?(n, d.node1, frame_ctx);
        vsapi.?.requestFrameFilter.?(n, d.node2, frame_ctx);
    } else if (activation_reason == .AllFramesReady) {
        const src1 = vsapi.?.getFrameFilter.?(n, d.node1, frame_ctx);
        const src2 = vsapi.?.getFrameFilter.?(n, d.node2, frame_ctx);
        defer vsapi.?.freeFrame.?(src1);
        defer vsapi.?.freeFrame.?(src2);

        const width: usize = @intCast(vsapi.?.getFrameWidth.?(src1, 0));
        const height: usize = @intCast(vsapi.?.getFrameHeight.?(src1, 0));
        const stride: usize = @intCast(vsapi.?.getStride.?(src1, 0));
        const dst = vsapi.?.copyFrame.?(src2, core).?;

        // const srcp1 = [3][*c]const u8{
        //     vsapi.?.getReadPtr.?(src1, 0),
        //     vsapi.?.getReadPtr.?(src1, 1),
        //     vsapi.?.getReadPtr.?(src1, 2),
        // };

        // const srcp2 = [3][*c]const u8{
        //     vsapi.?.getReadPtr.?(src2, 0),
        //     vsapi.?.getReadPtr.?(src2, 1),
        //     vsapi.?.getReadPtr.?(src2, 2),
        // };

        const srcp1_0: [*c]u8 = @constCast(vsapi.?.getReadPtr.?(src1, 0));
        const srcp1_1: [*c]u8 = @constCast(vsapi.?.getReadPtr.?(src1, 1));
        const srcp1_2: [*c]u8 = @constCast(vsapi.?.getReadPtr.?(src1, 2));

        const srcp2_0: [*c]u8 = @constCast(vsapi.?.getReadPtr.?(src1, 0));
        const srcp2_1: [*c]u8 = @constCast(vsapi.?.getReadPtr.?(src1, 1));
        const srcp2_2: [*c]u8 = @constCast(vsapi.?.getReadPtr.?(src1, 2));

        const val = xpsnr.process(
            @intCast(width),
            @intCast(height),
            @intCast(stride),
            @ptrCast(@alignCast(srcp1_0)),
            @ptrCast(@alignCast(srcp1_1)),
            @ptrCast(@alignCast(srcp1_2)),
            @ptrCast(@alignCast(srcp2_0)),
            @ptrCast(@alignCast(srcp2_1)),
            @ptrCast(@alignCast(srcp2_2)),
        );

        _ = vsapi.?.mapSetFloat.?(vsapi.?.getFramePropertiesRW.?(dst), "_XPSNR", val, .Replace);
        return dst;
    }
    return null;
}

export fn MetricsFree(instance_data: ?*anyopaque, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.C) void {
    _ = core;
    const d: *Data = @ptrCast(@alignCast(instance_data));

    vsapi.?.freeNode.?(d.node1);
    vsapi.?.freeNode.?(d.node2);
    allocator.destroy(d);
}

pub export fn MetricsCreate(in: ?*const vs.Map, out: ?*vs.Map, user_data: ?*anyopaque, core: ?*vs.Core, vsapi: ?*const vs.API) callconv(.C) void {
    _ = user_data;
    var d: Data = undefined;

    var map = zapi.Map.init(in, out, vsapi);
    d.node1, const vi1 = map.getNodeVi("reference");
    d.node2, const vi2 = map.getNodeVi("distorted");
    helper.compareNodes(out, d.node1, d.node2, vi1, vi2, filter_name, vsapi) catch return;
    const dt = helper.DataType.select(map, d.node1, vi1, filter_name) catch return;
    _ = dt; // autofix

    const mode = map.getInt(i32, "mode") orelse 0;
    // if (mode != 0) {
    //     vsapi.?.mapSetError.?(out, filter_name ++ " : only mode=0 is implemented.");
    //     vsapi.?.freeNode.?(d.node1);
    //     vsapi.?.freeNode.?(d.node2);
    //     return;
    // }

    if ((vi1.format.colorFamily == .YUV)) {
        d.node1 = helper.YUVtoRGBS(d.node1, core, vsapi);
        d.node2 = helper.YUVtoRGBS(d.node2, core, vsapi);
    }

    d.node1 = sRGBtoLinearRGB(d.node1, core, vsapi);
    d.node2 = sRGBtoLinearRGB(d.node2, core, vsapi);

    const vi_out = vsapi.?.getVideoInfo.?(d.node1);
    const data: *Data = allocator.create(Data) catch unreachable;
    data.* = d;

    var deps = [_]vs.FilterDependency{
        vs.FilterDependency{
            .source = d.node1,
            .requestPattern = .StrictSpatial,
        },
        vs.FilterDependency{
            .source = d.node2,
            .requestPattern = .StrictSpatial,
        },
    };

    if (mode == 0) {
        vsapi.?.createVideoFilter.?(out, filter_name, vi_out, ssimulacra2GetFrame, MetricsFree, .Parallel, &deps, deps.len, data, core);
    } else if (mode == 1) {
        vsapi.?.createVideoFilter.?(out, filter_name, vi_out, xpsnrGetFrame, MetricsFree, .Parallel, &deps, deps.len, data, core);
    }
}

pub fn sRGBtoLinearRGB(node: ?*vs.Node, core: ?*vs.Core, vsapi: ?*const vs.API) ?*vs.Node {
    var in = node;
    var err: vs.MapPropertyError = undefined;
    const frame = vsapi.?.getFrame.?(0, node, null, 0);
    const transfer_in = vsapi.?.mapGetInt.?(vsapi.?.getFramePropertiesRO.?(frame), "_Transfer", 0, &err);
    const reszplugin = vsapi.?.getPluginByID.?(vsh.RESIZE_PLUGIN_ID, core);

    const args = vsapi.?.createMap.?();
    var ret: ?*vs.Map = null;

    if (transfer_in != 8) {
        _ = vsapi.?.mapConsumeNode.?(args, "clip", in, .Replace);
        _ = vsapi.?.mapSetData.?(args, "prop", "_Transfer", -1, .Utf8, .Replace);
        _ = vsapi.?.mapSetInt.?(args, "intval", 13, .Replace);
        const stdplugin = vsapi.?.getPluginByID.?(vsh.STD_PLUGIN_ID, core);
        ret = vsapi.?.invoke.?(stdplugin, "SetFrameProp", args);
        in = vsapi.?.mapGetNode.?(ret, "clip", 0, null);
        vsapi.?.freeMap.?(ret);
        vsapi.?.clearMap.?(args);
    }

    _ = vsapi.?.mapConsumeNode.?(args, "clip", in, .Replace);
    _ = vsapi.?.mapSetInt.?(args, "transfer", 8, .Replace);
    ret = vsapi.?.invoke.?(reszplugin, "Bicubic", args);
    const out = vsapi.?.mapGetNode.?(ret, "clip", 0, null);
    vsapi.?.freeMap.?(ret);
    vsapi.?.freeMap.?(args);

    return out;
}
