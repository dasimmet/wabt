const std = @import("std");
const LazyPath = std.Build.LazyPath;

pub fn build(b: *std.Build, target: std.Build.ResolvedTarget, opt: std.builtin.OptimizeMode) void {
    const src_dep = b.dependency("binaryen", .{});
    const config_h = b.addConfigHeader(.{
        .style = .{ .cmake = src_dep.path("config.h.in") },
        .include_path = "config.h",
    }, .{
        .PROJECT_VERSION = "121",
    });
    const config_h_include = config_h.getOutput().dirname();
    const lib = b.addStaticLibrary(.{
        .name = "binaryen",
        .target = target,
        .optimize = opt,
    });
    const src_path = src_dep.path("src");
    const fp16_path = src_dep.path("third_party/FP16/include");
    const llvm_path = src_dep.path("third_party/llvm-project/include");
    lib.linkLibCpp();
    lib.addIncludePath(config_h_include);
    lib.addIncludePath(src_path);
    lib.addIncludePath(fp16_path);
    lib.addIncludePath(llvm_path);
    lib.addCSourceFiles(.{
        .files = lib_sources,
        .root = src_path,
    });
    inline for (dep_libs) |dep_lib| {
        const d_lib = b.addStaticLibrary(.{
            .name = "binaryen_" ++ dep_lib.path,
            .target = target,
            .optimize = opt,
        });
        d_lib.linkLibCpp();
        const d_root = src_dep.path(b.pathJoin(&.{ "src", dep_lib.path }));
        d_lib.addCSourceFiles(.{
            .files = dep_lib.sources,
            .root = d_root,
        });
        d_lib.addIncludePath(src_path);
        d_lib.addIncludePath(config_h_include);
        d_lib.addIncludePath(fp16_path);
        d_lib.addIncludePath(llvm_path);
        lib.linkLibrary(d_lib);
        b.step("binaryen-lib-" ++ dep_lib.path, "binaryen-library").dependOn(&d_lib.step);
    }

    const tools_path = src_dep.path("src/tools");
    const tools_fuzzing_path = src_dep.path("src/tools/fuzzing");
    inline for (tools) |t| {
        const exe = b.addExecutable(.{
            .name = t,
            .target = target,
            .optimize = opt,
        });
        exe.linkLibCpp();
        exe.linkLibrary(lib);
        exe.addIncludePath(src_path);
        exe.addIncludePath(fp16_path);
        exe.addIncludePath(tools_path);
        exe.addCSourceFiles(.{
            .files = &.{t ++ ".cpp"},
            .root = tools_path,
        });
        exe.addCSourceFiles(.{
            .files = tools_fuzzing,
            .root = tools_fuzzing_path,
        });
        b.installArtifact(exe);
    }
}

const tools = &.{
    // "wasm-as",
    // "wasm-ctor-eval",
    // "wasm-dis",
    // "wasm-emscripten-finalize",
    // "wasm-fuzz-lattices",
    // "wasm-fuzz-types",
    // "wasm-merge",
    // "wasm-metadce",
    "wasm-opt",
    // "wasm-reduce",
    // "wasm-shell",
};

const tools_fuzzing = &.{
    "fuzzing.cpp",
    "heap-types.cpp",
    "random.cpp",
};

const lib_sources = &.{
    "analysis/cfg.cpp",
    "binaryen-c.cpp",
    "cfg/Relooper.cpp",
    // "tools/fuzzing/fuzzing.cpp",
    // "tools/fuzzing/heap-types.cpp",
    // "tools/fuzzing/random.cpp",
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
