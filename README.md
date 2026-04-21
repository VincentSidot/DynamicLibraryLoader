# hijack

`hijack` is a small Windows x64 Zig project that:

- builds a sample DLL (`lib.dll`)
- builds a CLI loader (`hijack.exe`)
- assembles a tiny raw x64 loader stub with `fasm`
- copies that stub into executable memory and uses it to `LoadLibraryA`, resolve an exported symbol, call it, and unload the DLL

Despite the name, this project does not inject into a remote process. It loads a DLL into the current process and calls one exported entry point by name.

## Requirements

- Windows x64
- [Zig](https://ziglang.org/) available on `PATH`
- [FASM](https://flatassembler.net/) available on `PATH`

`build.zig` shells out to `fasm` directly, so builds fail if it is missing.

## Build

```powershell
zig build
```

Artifacts are written to `zig-out/bin`:

- `hijack.exe`
- `lib.dll`
- debug symbols (`.pdb`) when applicable

## Run

The CLI accepts:

```text
hijack.exe <dll-path> [entry-point]
```

- `<dll-path>`: path to the DLL to load
- `[entry-point]`: optional exported function name
- default entry point: `entrypoint`

Example using the sample DLL built by this project:

```powershell
zig build run -- zig-out/bin/lib.dll entrypoint
```

The sample DLL in [src/lib.zig](./src/lib.zig) exports `entrypoint`, which shows a `MessageBoxA` dialog.

You can also run the installed binary directly:

```powershell
.\zig-out\bin\hijack.exe .\zig-out\bin\lib.dll entrypoint
```

## How It Works

1. `build.zig` assembles [src/loader.s](./src/loader.s) into a raw binary blob with `fasm`.
2. `src/main.zig` embeds that blob with `@embedFile`.
3. At runtime, `hijack.exe` allocates RW memory with `VirtualAlloc`, copies the blob into it, then switches the page to RX with `VirtualProtect`.
4. The loader stub receives pointers to `LoadLibraryA`, `FreeLibrary`, `GetProcAddress`, the DLL path, the export name, and an optional user argument.
5. The stub loads the DLL, resolves the export, calls it, then frees the library.

## Project Layout

- [build.zig](./build.zig): build graph for the executable, sample DLL, and assembled payload
- [src/main.zig](./src/main.zig): CLI entry point and runtime loader setup
- [src/loader.s](./src/loader.s): raw x64 assembly stub executed from allocated memory
- [src/lib.zig](./src/lib.zig): sample DLL export used for local testing
- [src/dynamic.zig](./src/dynamic.zig): experimental helper code that is not currently wired into the build
- `asm/`: scratch assembly examples
- `build/`: generated local binaries checked into the tree

## Calling Convention

The loader calls the resolved export using the Windows x64 ABI.

- The CLI currently passes `null` as the optional user argument.
- The loader places that optional pointer in `RCX` before calling the export.
- The sample DLL ignores that argument and still works.

A matching Zig export would look like:

```zig
export fn entrypoint(ctx: ?*anyopaque) callconv(.winapi) void {
    _ = ctx;
}
```

## Current Limitations

- The loader uses `LoadLibraryA`, so non-ASCII DLL paths are not handled correctly.
- The assembly payload is hard-coded for x64 (`use64`), even though the Zig build exposes generic target selection.
- Loader return codes are logged but not propagated as process exit codes by the CLI.
- If symbol resolution fails after the DLL is loaded, the failure path does not currently call `FreeLibrary`.
- The project has no automated tests at the moment.

## Notes

- `zig build run -- --help` prints:

```text
Usage: ...\hijack.exe /path/to/dll <entry_point>
```

The source actually treats the entry point as optional and defaults it to `entrypoint`.
