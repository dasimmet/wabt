const std = @import("std");
const builtin = @import("builtin");
const LazyPath = std.Build.LazyPath;
const Dependency = std.Build.Dependency;

const binaryen_version_h = "121";

pub fn build(b: *std.Build, target: std.Build.ResolvedTarget, opt: std.builtin.OptimizeMode) void {
    if (b.lazyDependency("binaryen", .{})) |src_dep| {
        buildLazy(b, src_dep, target, opt);
    }
}

pub fn buildLazy(
    b: *std.Build,
    src_dep: *Dependency,
    target: std.Build.ResolvedTarget,
    opt: std.builtin.OptimizeMode,
) void {
    const config_h = b.addConfigHeader(.{
        .style = .{ .cmake = src_dep.path("config.h.in") },
        .include_path = "config.h",
    }, .{
        .PROJECT_VERSION = binaryen_version_h,
    });
    const config_h_include = config_h.getOutputDir();

    const intrinsics_basename = "WasmIntrinsics.cpp";
    const intrinsics_src = b.addConfigHeader(.{
        .style = .{ .cmake = src_dep.path("src/passes/WasmIntrinsics.cpp.in") },
        .include_path = intrinsics_basename,
    }, .{
        .WASM_INTRINSICS_EMBED = "0x00", // TODO: read the intrinsics wasm to populate this header
    });
    const intrinsics = intrinsics_src.getOutputDir();

    const lib = b.addLibrary(.{
        .name = "binaryen",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = opt,
            .link_libcpp = true,
        }),
    });
    const src_path = src_dep.path("src");
    const fp16_path = src_dep.path("third_party/FP16/include");
    lib.root_module.addIncludePath(config_h_include);
    lib.root_module.addIncludePath(src_path);
    lib.root_module.addIncludePath(fp16_path);
    lib.root_module.addIncludePath(src_dep.path(llvm.include_path));
    lib.root_module.addCSourceFiles(.{
        .files = lib_sources,
        .root = src_path,
    });
    b.installArtifact(lib);

    const llvm_lib = b.addLibrary(.{
        .name = "LLVMDWARF",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = opt,
            .link_libcpp = true,
        }),
    });
    llvm_lib.root_module.addCSourceFiles(.{
        .files = llvm.sources,
        .root = src_dep.path(llvm.src_path),
    });
    llvm_lib.root_module.addIncludePath(src_dep.path(llvm.include_path));

    inline for (dep_libs) |dep_lib| {
        const d_lib = b.addLibrary(.{
            .name = "binaryen_" ++ dep_lib.path,
            .root_module = b.createModule(.{
                .target = target,
                .optimize = opt,
                .link_libcpp = true,
            }),
        });
        const d_root = src_dep.path(b.pathJoin(&.{ "src", dep_lib.path }));
        d_lib.root_module.addCSourceFiles(.{
            .files = dep_lib.sources,
            .root = d_root,
        });
        if (ptrHasField(dep_lib, "add_intrinsics")) {
            d_lib.root_module.addCSourceFiles(.{
                .files = &.{intrinsics_basename},
                .root = intrinsics,
            });
        }
        if (ptrHasField(dep_lib, "link_llvm")) {
            d_lib.root_module.addIncludePath(src_dep.path(llvm.include_path));
        }
        d_lib.root_module.addIncludePath(src_path);
        d_lib.root_module.addIncludePath(config_h_include);
        d_lib.root_module.addIncludePath(fp16_path);
        lib.root_module.linkLibrary(d_lib);
        b.step("binaryen-lib-" ++ dep_lib.path, "binaryen-library").dependOn(&d_lib.step);
    }

    const tools_path = src_dep.path("src/tools");
    const tools_fuzzing_path = src_dep.path(tools_fuzzing.path);
    inline for (tools) |t| {
        const exe = b.addExecutable(.{
            .name = t,
            .root_module = b.createModule(.{
                .target = target,
                .optimize = opt,
                .link_libcpp = true,
            }),
        });
        exe.root_module.linkLibrary(lib);
        exe.root_module.addIncludePath(src_path);
        exe.root_module.addIncludePath(fp16_path);
        exe.root_module.addIncludePath(tools_path);
        exe.root_module.addCSourceFiles(.{
            .files = &.{t ++ ".cpp"},
            .root = tools_path,
        });
        exe.root_module.addCSourceFiles(.{
            .files = tools_fuzzing.sources,
            .root = tools_fuzzing_path,
        });
        exe.root_module.linkLibrary(llvm_lib);
        const exe_install = b.addInstallArtifact(exe, .{});
        b.default_step.dependOn(&exe_install.step);
        b.step("binaryen-" ++ t, "binaryen-tool " ++ t).dependOn(&exe_install.step);

        if (std.mem.eql(u8, "wasm-opt", t)) {
            if (b.option(
                LazyPath,
                "wasmopt_path",
                "path to a wasm file to convert to .wasm",
            )) |wasm_path| {
                const run = b.addRunArtifact(exe);
                run.addFileArg(wasm_path);
                const out_basename = b.option(
                    []const u8,
                    "wasmopt_out_basename",
                    "basename of generated .wasm",
                ) orelse "out.wasm";
                const output = run.addPrefixedOutputFileArg("--output=", out_basename);
                const default_args: []const []const u8 = &.{
                    "-Oz",
                    "-c",
                };
                const extra_args = b.option(
                    []const []const u8,
                    "wasmopt_extra_args",
                    "basename of generated .wasm",
                ) orelse default_args;
                run.addArgs(extra_args);
                b.addNamedLazyPath(out_basename, output);
            }
        }
    }
}

inline fn zig_13_or_older() bool {
    const zig_version = @import("builtin").zig_version;
    return zig_version.major == 0 and zig_version.minor <= 13;
}

fn ptrHasField(ptr: anytype, comptime name: []const u8) bool {
    const ptr_type = if (zig_13_or_older())
        @typeInfo(@TypeOf(ptr)).Pointer.child
    else
        @typeInfo(@TypeOf(ptr)).pointer.child;
    return @hasField(ptr_type, name);
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

const tools_fuzzing = .{
    .path = "src/tools/fuzzing",
    .sources = &.{
        "fuzzing.cpp",
        "heap-types.cpp",
        "random.cpp",
    },
};

const lib_sources = &.{
    "analysis/cfg.cpp",
    "binaryen-c.cpp",
    "cfg/Relooper.cpp",
};

const dep_libs = &.{
    &libasmjs,
    &libemscripten_optimizer,
    &libir,
    &libparser,
    &libpasses,
    &libsupport,
    &libwasm,
};

const libasmjs = .{
    .path = "asmjs",
    .sources = &.{
        "asmangle.cpp",
        "asm_v_wasm.cpp",
        "shared-constants.cpp",
    },
};

const libemscripten_optimizer = .{
    .path = "emscripten-optimizer",
    .sources = &.{
        "optimizer-shared.cpp",
        "parser.cpp",
        "simple_ast.cpp",
    },
};

const libparser = .{
    .path = "parser",
    .sources = &.{
        "context-decls.cpp",
        "context-defs.cpp",
        "lexer.cpp",
        "parse-1-decls.cpp",
        "parse-2-typedefs.cpp",
        "parse-3-implicit-types.cpp",
        "parse-4-module-types.cpp",
        "parse-5-defs.cpp",
        "wast-parser.cpp",
        "wat-parser.cpp",
    },
};

const libwasm = .{
    .path = "wasm",
    .sources = &.{
        "wasm-binary.cpp",
        "wasm-debug.cpp",
        "wasm-emscripten.cpp",
        "wasm-interpreter.cpp",
        "wasm-io.cpp",
        "wasm-ir-builder.cpp",
        "wasm-stack-opts.cpp",
        "wasm-stack.cpp",
        "wasm-type-shape.cpp",
        "wasm-type.cpp",
        "wasm-validator.cpp",
        "wasm.cpp",
        "literal.cpp",
        "parsing.cpp",
        "source-map.cpp",
    },
};

const libsupport = .{
    .path = "support",
    .link_llvm = true,
    .sources = &.{
        "archive.cpp",
        "bits.cpp",
        "colors.cpp",
        "command-line.cpp",
        "debug.cpp",
        "dfa_minimization.cpp",
        "file.cpp",
        "istring.cpp",
        "json.cpp",
        "name.cpp",
        "path.cpp",
        "safe_integer.cpp",
        "string.cpp",
        "suffix_tree.cpp",
        "suffix_tree_node.cpp",
        "threads.cpp",
        "utilities.cpp",
    },
};

const libpasses = .{
    .path = "passes",
    .add_intrinsics = true,
    .link_llvm = true,
    .sources = &.{
        "AbstractTypeRefining.cpp",
        "AlignmentLowering.cpp",
        "Asyncify.cpp",
        "AvoidReinterprets.cpp",
        "CoalesceLocals.cpp",
        "CodeFolding.cpp",
        "CodePushing.cpp",
        "ConstantFieldPropagation.cpp",
        "ConstHoisting.cpp",
        "DataFlowOpts.cpp",
        "DeadArgumentElimination.cpp",
        "DeadCodeElimination.cpp",
        "DeAlign.cpp",
        "DebugLocationPropagation.cpp",
        "DeNaN.cpp",
        "Directize.cpp",
        "DuplicateFunctionElimination.cpp",
        "DuplicateImportElimination.cpp",
        "DWARF.cpp",
        "EncloseWorld.cpp",
        "ExtractFunction.cpp",
        "Flatten.cpp",
        "FuncCastEmulation.cpp",
        "GenerateDynCalls.cpp",
        "GlobalEffects.cpp",
        "GlobalRefining.cpp",
        "GlobalStructInference.cpp",
        "GlobalTypeOptimization.cpp",
        "GUFA.cpp",
        "hash-stringify-walker.cpp",
        "Heap2Local.cpp",
        "HeapStoreOptimization.cpp",
        "I64ToI32Lowering.cpp",
        "Inlining.cpp",
        "InstrumentLocals.cpp",
        "InstrumentMemory.cpp",
        "Intrinsics.cpp",
        "J2CLItableMerging.cpp",
        "J2CLOpts.cpp",
        "JSPI.cpp",
        "LegalizeJSInterface.cpp",
        "LimitSegments.cpp",
        "LLVMMemoryCopyFillLowering.cpp",
        "LLVMNontrappingFPToIntLowering.cpp",
        "LocalCSE.cpp",
        "LocalSubtyping.cpp",
        "LogExecution.cpp",
        "LoopInvariantCodeMotion.cpp",
        "Memory64Lowering.cpp",
        "MemoryPacking.cpp",
        "MergeBlocks.cpp",
        "MergeLocals.cpp",
        "MergeSimilarFunctions.cpp",
        "Metrics.cpp",
        "MinifyImportsAndExports.cpp",
        "MinimizeRecGroups.cpp",
        "Monomorphize.cpp",
        "MultiMemoryLowering.cpp",
        "NameList.cpp",
        "NameTypes.cpp",
        "NoInline.cpp",
        "OnceReduction.cpp",
        "OptimizeAddedConstants.cpp",
        "OptimizeCasts.cpp",
        "OptimizeForJS.cpp",
        "OptimizeInstructions.cpp",
        "Outlining.cpp",
        "param-utils.cpp",
        "pass.cpp",
        "PickLoadSigns.cpp",
        "Poppify.cpp",
        "PostEmscripten.cpp",
        "Precompute.cpp",
        "Print.cpp",
        "PrintCallGraph.cpp",
        "PrintFeatures.cpp",
        "PrintFunctionMap.cpp",
        "RedundantSetElimination.cpp",
        "RemoveImports.cpp",
        "RemoveMemory.cpp",
        "RemoveNonJSOps.cpp",
        "RemoveUnusedBrs.cpp",
        "RemoveUnusedModuleElements.cpp",
        "RemoveUnusedNames.cpp",
        "RemoveUnusedTypes.cpp",
        "ReorderFunctions.cpp",
        "ReorderGlobals.cpp",
        "ReorderLocals.cpp",
        "ReReloop.cpp",
        "RoundTrip.cpp",
        "SafeHeap.cpp",
        "SeparateDataSegments.cpp",
        "SetGlobals.cpp",
        "SignaturePruning.cpp",
        "SignatureRefining.cpp",
        "SignExtLowering.cpp",
        "SimplifyGlobals.cpp",
        "SimplifyLocals.cpp",
        "Souperify.cpp",
        "SpillPointers.cpp",
        "SSAify.cpp",
        "StackCheck.cpp",
        "StringLowering.cpp",
        "Strip.cpp",
        "StripEH.cpp",
        "StripTargetFeatures.cpp",
        "test_passes.cpp",
        "TraceCalls.cpp",
        "TranslateEH.cpp",
        "TrapMode.cpp",
        "TupleOptimization.cpp",
        "TypeFinalizing.cpp",
        "TypeGeneralizing.cpp",
        "TypeMerging.cpp",
        "TypeRefining.cpp",
        "TypeSSA.cpp",
        "Unsubtyping.cpp",
        "Untee.cpp",
        "Vacuum.cpp",
    },
};

const libir = .{
    .path = "ir",
    .sources = &.{
        "debuginfo.cpp",
        "drop.cpp",
        "effects.cpp",
        "eh-utils.cpp",
        "export-utils.cpp",
        "ExpressionAnalyzer.cpp",
        "ExpressionManipulator.cpp",
        "intrinsics.cpp",
        "LocalGraph.cpp",
        "LocalStructuralDominance.cpp",
        "lubs.cpp",
        "memory-utils.cpp",
        "module-splitting.cpp",
        "module-utils.cpp",
        "names.cpp",
        "possible-contents.cpp",
        "properties.cpp",
        "ReFinalize.cpp",
        "return-utils.cpp",
        "stack-utils.cpp",
        "table-utils.cpp",
        "type-updating.cpp",
    },
};

const llvm = .{
    .src_path = "third_party/llvm-project",
    .include_path = "third_party/llvm-project/include",
    .sources = &.{
        "Binary.cpp",
        "ConvertUTF.cpp",
        "DataExtractor.cpp",
        "Debug.cpp",
        "DJB.cpp",
        "Dwarf.cpp",
        "dwarf2yaml.cpp",
        "DWARFAbbreviationDeclaration.cpp",
        "DWARFAcceleratorTable.cpp",
        "DWARFAddressRange.cpp",
        "DWARFCompileUnit.cpp",
        "DWARFContext.cpp",
        "DWARFDataExtractor.cpp",
        "DWARFDebugAbbrev.cpp",
        "DWARFDebugAddr.cpp",
        "DWARFDebugAranges.cpp",
        "DWARFDebugArangeSet.cpp",
        "DWARFDebugFrame.cpp",
        "DWARFDebugInfoEntry.cpp",
        "DWARFDebugLine.cpp",
        "DWARFDebugLoc.cpp",
        "DWARFDebugMacro.cpp",
        "DWARFDebugPubTable.cpp",
        "DWARFDebugRangeList.cpp",
        "DWARFDebugRnglists.cpp",
        "DWARFDie.cpp",
        "DWARFEmitter.cpp",
        "DWARFExpression.cpp",
        "DWARFFormValue.cpp",
        "DWARFGdbIndex.cpp",
        "DWARFListTable.cpp",
        "DWARFTypeUnit.cpp",
        "DWARFUnit.cpp",
        "DWARFUnitIndex.cpp",
        "DWARFVerifier.cpp",
        "DWARFVisitor.cpp",
        "DWARFYAML.cpp",
        "Error.cpp",
        "ErrorHandling.cpp",
        "FormatVariadic.cpp",
        "Hashing.cpp",
        "LEB128.cpp",
        "LineIterator.cpp",
        "MCRegisterInfo.cpp",
        "MD5.cpp",
        "MemoryBuffer.cpp",
        "NativeFormatting.cpp",
        "ObjectFile.cpp",
        "obj2yaml_Error.cpp",
        "Optional.cpp",
        "Path.cpp",
        "raw_ostream.cpp",
        "ScopedPrinter.cpp",
        "SmallVector.cpp",
        "SourceMgr.cpp",
        "StringMap.cpp",
        "StringRef.cpp",
        "SymbolicFile.cpp",
        "Twine.cpp",
        "UnicodeCaseFold.cpp",
        "WithColor.cpp",
        "YAMLParser.cpp",
        "YAMLTraits.cpp",
    },
};
