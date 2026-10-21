// Zig wabt
//
// by Tobias Simetsreiter <dasimmet@gmail.com>
//

const std = @import("std");
const LazyPath = std.Build.LazyPath;
const Dependency = std.Build.Dependency;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const src_dep = b.dependency("wabt", .{});

    const fmt = b.addFmt(.{
        .check = b.option(bool, "fmtcheck", "check formatting") orelse false,
        .paths = &.{
            b.path("build.zig"),
            b.path("build.zig.zon"),
        },
    });
    b.step("fmt", "format source code").dependOn(&fmt.step);

    const wabt_config_h = b.addConfigHeader(.{
        .include_path = "wabt/config.h",
        .style = .{ .cmake = src_dep.path("src/config.h.in") },
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
    const wabt_config_include = wabt_config_h.getOutputDir();

    const lib = b.addLibrary(.{
        .name = "wabt",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libcpp = true,
        }),
    });
    lib.root_module.addIncludePath(src_dep.path("include"));
    lib.root_module.addIncludePath(wabt_config_include);

    if (b.systemIntegrationOption("wasmc", .{})) {
        const wasmc_path: LazyPath = .{ .cwd_relative = b.option(
            []const u8,
            "wasmc",
            "wasmc include path",
        ) orelse @panic("\"wasmc\" include path option not given") };
        lib.root_module.addIncludePath(wasmc_path);
    } else {
        if (b.lazyDependency("wasmc", .{})) |wasmc| {
            lib.root_module.addIncludePath(wasmc.path("include"));
        }
    }

    if (b.systemIntegrationOption("picosha", .{})) {
        const picosha_path: LazyPath = .{ .cwd_relative = b.option(
            []const u8,
            "picosha",
            "picosha include path",
        ) orelse @panic("picosha include path not defined") };
        lib.root_module.addIncludePath(picosha_path);
    } else {
        if (b.lazyDependency("picosha", .{})) |picosha| {
            lib.root_module.addIncludePath(picosha.path(""));
        }
    }

    lib.root_module.addCSourceFiles(.{
        .files = libwabt_sources,
        .root = src_dep.path("src"),
    });
    if (target.result.os.tag == .wasi) {
        lib.root_module.addCMacro("_WASI_EMULATED_MMAN", "");
        lib.root_module.linkSystemLibrary("wasi-emulated-mman", .{});
    } else {
        lib.root_module.addCSourceFiles(.{
            .files = wasm2c_sources,
            .root = src_dep.path("wasm2c"),
        });
    }
    const lib_install = b.addInstallArtifact(lib, .{});
    b.step("lib", "install lib").dependOn(&lib_install.step);

    inline for (wabt_tools) |exe_tpl| {
        const exe_name = exe_tpl[0];
        const exe_extra_sources = exe_tpl[1..];
        const exe = b.addExecutable(.{
            .name = exe_name,
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
            }),
            .linkage = if (target.result.os.tag != .macos) .static else null,
        });
        exe.root_module.addCSourceFiles(.{
            .files = &.{
                "tools/" ++ exe_name ++ ".cc",
            },
            .root = src_dep.path("src"),
        });
        if (exe_extra_sources.len > 0) {
            exe.root_module.addCSourceFiles(.{
                .files = exe_extra_sources,
                .root = src_dep.path("src"),
            });
        }
        exe.root_module.linkLibrary(lib);
        exe.root_module.addIncludePath(src_dep.path("include"));
        exe.root_module.addIncludePath(wabt_config_include);

        const exe_install = b.addInstallArtifact(exe, .{});
        b.default_step.dependOn(&exe_install.step);
        b.step("wabt-" ++ exe_name, "wabt tool " ++ exe_name).dependOn(&exe_install.step);
    }
}

pub const wabt_tools: []const []const []const u8 = &.{
    &.{"spectest-interp"},
    &.{"wasm2c"},
    &.{"wasm2wat"},
    &.{ "wasm2wat-fuzz", "tools/wasm2wat.cc" },
    &.{"wasm-decompile"},
    &.{"wasm-interp"},
    &.{ "wasm-objdump", "binary-reader-objdump.cc" },
    &.{ "wasm-stats", "binary-reader-stats.cc" },
    &.{"wasm-strip"},
    &.{"wasm-validate"},
    &.{"wast2json"},
    &.{"wat2wasm"},
    &.{"wat-desugar"},
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
