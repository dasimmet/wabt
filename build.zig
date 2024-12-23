// Zig wabt
//
// by Tobias Simetsreiter <dasimmet@gmail.com>
//

const std = @import("std");
const LazyPath = std.Build.LazyPath;

pub fn wasm2wat(b: *std.Build, wasm: LazyPath, out_basename: []const u8) LazyPath {
    const this_dep = b.dependencyFromBuildZig(@This(), .{
        .target = b.graph.host,
        .optimize = std.builtin.OptimizeMode.ReleaseFast,
    });
    if (this_dep.builder.lazyDependency("wabt", .{})) |wabt_dep| {
        _ = wabt_dep;
        const wat_run = b.addRunArtifact(this_dep.artifact("wasm2wat"));
        wat_run.addFileArg(wasm);
        return wat_run.addPrefixedOutputFileArg("--output=", out_basename);
    }
    return b.path("");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const opt = b.standardOptimizeOption(.{});

    const static_target = b.resolveTargetQuery(.{
        .cpu_arch = target.result.cpu.arch,
        .os_tag = target.result.os.tag,
        .abi = if (target.result.os.tag == .linux) .musl else null,
    });

    const wabt = b.dependency("wabt", .{
        .target = target,
        .optimize = opt,
    });
    const wabt_config_h = b.addConfigHeader(.{
        .include_path = "wabt/config.h",
        .style = .{ .cmake = wabt.path("src/config.h.in") },
    }, .{
        .WABT_VERSION_STRING = "1.0.36",
        .HAVE_ALLOCA_H = 0,
        .HAVE_UNISTD_H = 1,
        .HAVE_SNPRINTF = 1,
        .HAVE_SSIZE_T = 1,
        .HAVE_STRCASECMP = 1,
        .HAVE_WIN32_VT100 = 0,
        .WABT_BIG_ENDIAN = @as(u1, if (target.result.cpu.arch.endian() == .big) 1 else 0),
        .HAVE_OPENSSL_SHA_H = 0,
        .WITH_EXCEPTIONS = b.option(bool, "WITH_EXCEPTIONS", "compile with exceptions") orelse false,
        .SIZEOF_SIZE_T = 8,
        .COMPILER_IS_CLANG = 1,
        .WABT_DEBUG = b.option(bool, "WABT_DEBUG", "compile with debug support"),
    });
    const wabt_config_include = wabt_config_h.getOutput().dirname().dirname();

    const lib = b.addStaticLibrary(.{
        .name = "wabt",
        .target = static_target,
        .optimize = opt,
    });
    lib.linkLibCpp();
    lib.addIncludePath(wabt.path("include"));
    lib.addIncludePath(wabt_config_include);

    if (b.systemIntegrationOption("wasmc", .{})) {
        const wasmc_path: LazyPath = .{ .cwd_relative = b.option(
            []const u8,
            "wasmc",
            "wasmc include path",
        ) orelse @panic("wasmc include path not defined") };
        lib.addIncludePath(wasmc_path);
    } else {
        if (b.lazyDependency("wasmc", .{})) |wasmc| {
            lib.addIncludePath(wasmc.path("include"));
        }
    }

    if (b.systemIntegrationOption("picosha", .{})) {
        const picosha_path: LazyPath = .{ .cwd_relative = b.option(
            []const u8,
            "picosha",
            "picosha include path",
        ) orelse @panic("picosha include path not defined") };
        lib.addIncludePath(picosha_path);
    } else {
        if (b.lazyDependency("picosha", .{})) |picosha| {
            lib.addIncludePath(picosha.path(""));
        }
    }

    lib.addCSourceFiles(.{
        .files = libwabt_sources,
        .root = wabt.path("src"),
    });
    if (static_target.result.isWasm()) {
        lib.root_module.addCMacro("_WASI_EMULATED_MMAN", "");
        lib.linkSystemLibrary("wasi-emulated-mman");
    } else {
        lib.addCSourceFiles(.{
            .files = wasm2c_sources,
            .root = wabt.path("wasm2c"),
        });
    }
    b.installArtifact(lib);

    inline for (wabt_tools) |exe_name| {
        const exe = b.addExecutable(.{
            .name = exe_name,
            .target = static_target,
            .optimize = opt,
            .linkage = if (target.result.os.tag != .macos) .static else null,
        });
        exe.addCSourceFiles(.{
            .files = &.{"tools/" ++ exe_name ++ ".cc"},
            .root = wabt.path("src"),
        });
        exe.linkLibrary(lib);
        exe.addIncludePath(wabt.path("include"));
        exe.addIncludePath(wabt_config_include);

        b.installArtifact(exe);
    }
}

pub const wabt_tools = &.{
    "wasm2c",
    "wasm2wat",
    // "wasm2wat-fuzz",
    "wasm-decompile",
    "wasm-interp",
    // "wasm-objdump",
    // "wasm-stats",
    "wasm-strip",
    "wasm-validate",
    "wast2json",
    "wat2wasm",
    "wat-desugar",
};

pub const wasm2c_sources = &.{
    "wasm-rt-impl.c",
    "wasm-rt-exceptions-impl.c",
    "wasm-rt-mem-impl.c",
};

pub const libwabt_sources = &.{
    "apply-names.cc",
    "binary-reader-ir.cc",
    "binary-reader-logging.cc",
    "binary-reader.cc",
    "binary-writer-spec.cc",
    "binary-writer.cc",
    "binary.cc",
    "binding-hash.cc",
    "color.cc",
    "common.cc",
    "config.cc",
    "decompiler.cc",
    "error-formatter.cc",
    "expr-visitor.cc",
    "feature.cc",
    "filenames.cc",
    "generate-names.cc",
    "ir-util.cc",
    "ir.cc",
    "leb128.cc",
    "lexer-source-line-finder.cc",
    "lexer-source.cc",
    "literal.cc",
    "opcode-code-table.c",
    "opcode.cc",
    "option-parser.cc",
    "resolve-names.cc",
    "sha256.cc",
    "shared-validator.cc",
    "stream.cc",
    "token.cc",
    "tracing.cc",
    "type-checker.cc",
    "utf8.cc",
    "validator.cc",
    "wast-lexer.cc",
    "wast-parser.cc",
    "wat-writer.cc",
    "c-writer.cc",
    "prebuilt/wasm2c_header_top.cc",
    "prebuilt/wasm2c_header_bottom.cc",
    "prebuilt/wasm2c_source_includes.cc",
    "prebuilt/wasm2c_source_declarations.cc",
    "prebuilt/wasm2c_simd_source_declarations.cc",
    "prebuilt/wasm2c_atomicops_source_declarations.cc",
    "interp/binary-reader-interp.cc",
    "interp/interp.cc",
    "interp/interp-util.cc",
    "interp/istream.cc",
    "apply-names.cc",
    "binary-reader-ir.cc",
    "binary-reader-logging.cc",
    "binary-reader.cc",
    "binary-writer-spec.cc",
    "binary-writer.cc",
    "binary.cc",
    "binding-hash.cc",
    "color.cc",
    "common.cc",
    "config.cc",
    "decompiler.cc",
    "error-formatter.cc",
    "expr-visitor.cc",
    "feature.cc",
    "filenames.cc",
    "generate-names.cc",
    "ir-util.cc",
    "ir.cc",
    "leb128.cc",
    "lexer-source-line-finder.cc",
    "lexer-source.cc",
    "literal.cc",
    "opcode-code-table.c",
    "opcode.cc",
    "option-parser.cc",
    "resolve-names.cc",
    "sha256.cc",
    "shared-validator.cc",
    "stream.cc",
    "token.cc",
    "tracing.cc",
    "type-checker.cc",
    "utf8.cc",
    "validator.cc",
    "wast-lexer.cc",
    "wast-parser.cc",
    "wat-writer.cc",
    "c-writer.cc",
    "prebuilt/wasm2c_header_top.cc",
    "prebuilt/wasm2c_header_bottom.cc",
    "prebuilt/wasm2c_source_includes.cc",
    "prebuilt/wasm2c_source_declarations.cc",
    "prebuilt/wasm2c_simd_source_declarations.cc",
    "prebuilt/wasm2c_atomicops_source_declarations.cc",
    "interp/binary-reader-interp.cc",
    "interp/interp.cc",
    "interp/interp-util.cc",
    "interp/istream.cc",
    "interp/interp-wasm-c-api.cc",
};
