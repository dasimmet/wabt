// Zig wabt
//
// by Tobias Simetsreiter <dasimmet@gmail.com>
//

const std = @import("std");
const zon = @import("build.zig.zon");
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
        .WABT_VERSION_STRING = zon.version,
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

    const cxx_flags: []const []const u8 = &.{
        "-std=c++20",
    };

    lib.root_module.addCSourceFiles(.{
        .files = libwabt_cc_sources,
        .root = src_dep.path("src"),
        .flags = cxx_flags,
    });
    lib.root_module.addCSourceFiles(.{
        .files = libwabt_c_sources,
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

    inline for (wabt_tools) |tool| {
        const exe = b.addExecutable(.{
            .name = tool.name,
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
            }),
            .linkage = if (target.result.os.tag != .macos) .static else null,
        });
        if (tool.files) |files| {
            exe.root_module.addCSourceFiles(.{
                .files = files,
                .root = src_dep.path("src"),
                .flags = cxx_flags,
            });
        } else {
            exe.root_module.addCSourceFiles(.{
                .files = &.{
                    "tools/" ++ tool.name ++ ".cc",
                },
                .root = src_dep.path("src"),
                .flags = cxx_flags,
            });
        }
        exe.root_module.linkLibrary(lib);
        exe.root_module.addIncludePath(src_dep.path("include"));
        exe.root_module.addIncludePath(wabt_config_include);

        const exe_install = b.addInstallArtifact(exe, .{});
        b.default_step.dependOn(&exe_install.step);
        b.step("wabt-" ++ tool.name, "wabt tool " ++ tool.name).dependOn(&exe_install.step);
    }
}

const Tool = struct {
    name: []const u8,
    files: ?[]const []const u8 = null,
};

pub const wabt_tools: []const Tool = &.{
    .{ .name = "spectest-interp" },
    .{ .name = "wasm2c" },
    .{
        .name = "wasm2wat-fuzz",
        .files = &.{
            "tools/wasm2wat-fuzz.cc",
            "tools/wasm2wat.cc",
        },
    },
    .{ .name = "wasm2wat" },
    .{ .name = "wasm-interp" },
    .{
        .name = "wasm-objdump",
        .files = &.{
            "tools/wasm-objdump.cc",
            "binary-reader-objdump.cc",
        },
    },
    .{
        .name = "wasm-stats",
        .files = &.{
            "tools/wasm-stats.cc",
            "binary-reader-stats.cc",
        },
    },
    .{ .name = "wasm-strip" },
    .{ .name = "wasm-validate" },
    .{ .name = "wast2json" },
    .{ .name = "wat2wasm" },
    .{ .name = "wat-desugar" },
};

pub const wasm2c_sources = &.{
    "wasm-rt-impl.c",
    "wasm-rt-exceptions-impl.c",
    "wasm-rt-mem-impl.c",
};

pub const libwabt_c_sources = &.{
    "opcode-code-table.c",
};

pub const libwabt_cc_sources = &.{
    "apply-names.cc",
    "binary-reader-ir.cc",
    "binary-reader-logging.cc",
    "binary-reader.cc",
    "binary-writer-spec.cc",
    "binary-writer.cc",
    "binary.cc",
    "binding-hash.cc",
    "c-writer.cc",
    "color.cc",
    "common.cc",
    "config.cc",
    "error-formatter.cc",
    "expr-visitor.cc",
    "feature.cc",
    "filenames.cc",
    "generate-names.cc",
    "interp/binary-reader-interp.cc",
    "interp/interp-util.cc",
    "interp/interp.cc",
    "interp/istream.cc",
    "ir-util.cc",
    "ir.cc",
    "leb128.cc",
    "lexer-source-line-finder.cc",
    "lexer-source.cc",
    "literal.cc",
    "opcode.cc",
    "option-parser.cc",
    "prebuilt/wasm2c_atomicops_source_declarations.cc",
    "prebuilt/wasm2c_header_bottom.cc",
    "prebuilt/wasm2c_header_top.cc",
    "prebuilt/wasm2c_simd_source_declarations.cc",
    "prebuilt/wasm2c_source_declarations.cc",
    "prebuilt/wasm2c_source_includes.cc",
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
};
