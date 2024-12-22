# [WebAssembly Binary Toolkit](https://github.com/WebAssembly/wabt.git) on the zig build system

this builds the [WebAssembly Binary Toolkit](https://github.com/WebAssembly/wabt.git) to
use on the [Zig](https://ziglang.org/) build system

# build.zig usage

```zig
const wabt = @import("wabt");
const my_wat: LazyPath = wabt.wasm2wat(b.path("my.wasm"), "my.wat");
```