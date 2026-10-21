# [WebAssembly Binary Toolkit](https://github.com/WebAssembly/wabt.git) on the zig build system

uses the [Zig](https://ziglang.org/) build system to build WebAssembly's binary
C tools.

## building

```zig build
zig build
```

## add to your zig project

```bash
zig fetch --save git+https://github.com/allyourcodebase/wabt.git
```

## Cli usage

```
> ./zig-out/bin/wasm2c --help
usage: wasm2c [options] filename

  Read a file in the WebAssembly binary format, and convert it to
  a C source file and header.
```
