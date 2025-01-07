// Zig wabt
//
// by Tobias Simetsreiter <dasimmet@gmail.com>
//

const std = @import("std");
const binaryen = @import("binaryen.zig");
const wabt = @import("wabt.zig");
const LazyPath = std.Build.LazyPath;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const opt = b.standardOptimizeOption(.{});
    const wabt_opt = b.option(bool, "wabt", "build wabt") orelse true;
    const binaryen_opt = b.option(bool, "binaryen", "build binaryen") orelse true;
    if (wabt_opt) {
        wabt.build(b, target, opt);
    }
    if (binaryen_opt) {
        binaryen.build(b, target, opt);
    }
}

pub const WasmTool = enum {

};

pub fn wasm2wat(b: *std.Build, wasm: LazyPath, out_basename: []const u8) LazyPath {
    const this_dep = b.dependencyFromBuildZig(@This(), .{
        .target = b.graph.host,
        .optimize = std.builtin.OptimizeMode.ReleaseFast,
        .wabt = true,
        .binaryen = false,
    });

    if (this_dep.builder.lazyDependency("wabt", .{})) |wabt_dep| {
        _ = wabt_dep;
        const run = b.addRunArtifact(this_dep.artifact("wasm2wat"));
        run.addFileArg(wasm);
        return run.addPrefixedOutputFileArg("--output=", out_basename);
    }

    return b.path("");
}

pub fn wasm_opt(b: *std.Build, wasm: LazyPath, out_basename: []const u8) LazyPath {
    const this_dep = b.dependencyFromBuildZig(@This(), .{
        .target = b.graph.host,
        .optimize = std.builtin.OptimizeMode.ReleaseFast,
        .wabt = false,
        .binaryen = true,
    });

    if (this_dep.builder.lazyDependency("binaryen", .{})) |wabt_dep| {
        _ = wabt_dep;
        const run = b.addRunArtifact(this_dep.artifact("wasm-opt"));
        run.addArgs(&.{"-Oz", "-c"});
        run.addFileArg(wasm);
        return run.addPrefixedOutputFileArg("--output=", out_basename);
    }

    return b.path("");
}