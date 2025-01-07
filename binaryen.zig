const std = @import("std");
const LazyPath = std.Build.LazyPath;

pub fn build(b: *std.Build, target: std.Build.ResolvedTarget, opt: std.builtin.OptimizeMode) void {
    const src_dep = b.dependency("binaryen", .{});
    const lib = b.addStaticLibrary(.{
        .name = "binaryen",
        .target = target,
        .optimize = opt,
    });
    const src_path = src_dep.path("src");
    lib.linkLibCpp();
    lib.addIncludePath(src_path);
    lib.addCSourceFiles(.{
        .files = lib_sources,
        .root = src_dep.path("src"),
    });

    inline for (tools) |t| {
        const exe = b.addExecutable(.{
            .name = t,
            .target = target,
            .optimize = opt,
        });
        exe.linkLibCpp();
        exe.linkLibrary(lib);
        exe.addIncludePath(src_path);
        exe.addCSourceFiles(.{
            .files = &.{t ++ ".cpp"},
            .root = src_dep.path("src/tools"),
        });
        b.installArtifact(exe);
    }
}

const tools = &.{
    "wasm-as",
    "wasm-ctor-eval",
    "wasm-dis",
    "wasm-emscripten-finalize",
    "wasm-fuzz-lattices",
    "wasm-fuzz-types",
    "wasm-merge",
    "wasm-metadce",
    "wasm-opt",
    "wasm-reduce",
    "wasm-shell",
};

const lib_sources = &.{
    "ir/module-utils.cpp",
};
