# WebAssembly Tools on the zig build system

uses the [Zig](https://ziglang.org/) build system to build WebAssembly's binary
C tools.

## building

```zig build
zig build
```

## add to your zig project

```bash
zig fetch --save git+https://github.com/dasimmet/wabt.git
```

## [WebAssembly Binary Toolkit](https://github.com/WebAssembly/wabt.git)

```
> ./zig-out/bin/wasm2c --help
usage: wasm2c [options] filename

  Read a file in the WebAssembly binary format, and convert it to
  a C source file and header.
```

## [Binaryen](https://github.com/WebAssembly/binaryen.git)

```
> ./zig-out/bin/wasm-merge --help
================================================================================
wasm-merge INFILE1 NAME1 INFILE2 NAME2 [..]

Merge wasm files into one.
```

## build.zig usage

```zig
const wabt = @import("wabt");

// wasm-opt

const optimized_wasm: LazyPath = wabt.wasm_opt(
    b,
    b.path("my.wasm"),                // source path
    "optimized.wasm",                 // out_basename
    &.{"--mvp-features", "-Oz", "-c"}, // extra args array
);

// wasm2wat

const my_wat: LazyPath = wabt.wasm2wat(
    b,
    optimized_wasm, // source path
    "my.wat",       // out_basename
    &.{},            // extra args array
);
```
