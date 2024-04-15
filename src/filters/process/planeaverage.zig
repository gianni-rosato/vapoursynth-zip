const std = @import("std");
const helper = @import("../../helper.zig");

const allocator = std.heap.c_allocator;

pub const Exclude = union(enum) {
    f: []f32,
    i: []i32,
};

const Stats = struct {
    avg: f64,
    diff: f64,
};

fn result(comptime T: type, acc: anytype, total: f64, peak: f32) f64 {
    if (total == 0) {
        return 0.0;
    } else if (@typeInfo(T) == .Float) {
        return acc / total;
    } else {
        return @as(f64, @floatFromInt(acc)) / total / peak;
    }
}

pub fn average(comptime T: type, src: []const u8, _stride: usize, w: usize, h: usize, exclude_union: Exclude, peak: f32) f64 {
    var srcp: []const T = @as([*]const T, @ptrCast(@alignCast(src)))[0..src.len];
    const stride: usize = @divTrunc(_stride, @sizeOf(T));
    const exclude = if (@typeInfo(T) == .Float) exclude_union.f else exclude_union.i;
    var total: i64 = @intCast(w * h);
    var acc: if (@typeInfo(T) == .Float) f64 else u64 = 0;

    for (0..h) |_| {
        for (srcp[0..w]) |v| {
            const found: bool = for (exclude) |e| {
                if (v == e) break true;
            } else false;

            if (found) {
                total -= 1;
            } else {
                acc += v;
            }
        }
        srcp = srcp[stride..];
    }

    return result(T, acc, @floatFromInt(total), peak);
}

pub fn averageRef(comptime T: type, src: []const u8, ref: []const u8, _stride: usize, w: usize, h: usize, exclude_union: Exclude, peak: f32) Stats {
    var srcp: []const T = @as([*]const T, @ptrCast(@alignCast(src)))[0..src.len];
    var refp: []const T = @as([*]const T, @ptrCast(@alignCast(ref)))[0..ref.len];
    const stride: usize = @divTrunc(_stride, @sizeOf(T));
    const exclude = if (@typeInfo(T) == .Float) exclude_union.f else exclude_union.i;
    const _total: i64 = @intCast(w * h);
    var total = _total;
    const T2 = if (@typeInfo(T) == .Float) f64 else u64;
    var acc: T2 = 0;
    var diffacc: T2 = 0;

    for (0..h) |_| {
        for (srcp[0..w], refp[0..w]) |v, j| {
            const found: bool = for (exclude) |e| {
                if (v == e) break true;
            } else false;

            if (found) {
                total -= 1;
            } else {
                acc += v;
            }

            diffacc += helper.absDiff(v, j);
        }
        srcp = srcp[stride..];
        refp = refp[stride..];
    }

    const _totalf: f64 = @floatFromInt(_total);
    return .{
        .avg = result(T, acc, @floatFromInt(total), peak),
        .diff = if (@typeInfo(T) == .Float) (diffacc / _totalf) else @as(f64, @floatFromInt(diffacc)) / _totalf / peak,
    };
}
