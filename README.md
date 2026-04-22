# hijack

`hijack` is a small Windows x64 Zig project that:

- builds a sample DLL (`lib.dll`)
- builds a CLI loader (`hijack.exe`)
- assembles a tiny raw x64 loader stub with `fasm`
- finds a target process by executable name
- copies that stub into the target process and starts it with `CreateRemoteThread`
- uses the stub to resolve `kernel32.dll` exports, call `LoadLibraryA` for a target DLL, resolve an exported symbol, call it, and unload the DLL

The loader injects the raw stub and argument block into the selected target process. The sample DLL shows a message box from inside that target process.

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
hijack.exe <target-process> <dll-path> [entry-point]
```

- `<target-process>`: executable name of the process to inject into, such as `notepad.exe`
- `<dll-path>`: path to the DLL to load
- `[entry-point]`: optional exported function name
- default entry point: `entrypoint`

Example using the sample DLL built by this project:

```powershell
zig build run -- notepad.exe zig-out/bin/lib.dll entrypoint
```

The sample DLL in [src/lib.zig](./src/lib.zig) exports `entrypoint`, which shows a `MessageBoxA` dialog.

You can also run the installed binary directly:

```powershell
.\zig-out\bin\hijack.exe notepad.exe .\zig-out\bin\lib.dll entrypoint
```

## How It Works

1. `build.zig` assembles [src/loader.s](./src/loader.s) into a raw binary blob with `fasm`.
2. `src/main.zig` embeds that blob with `@embedFile`.
3. At runtime, `hijack.exe` enumerates processes with the Tool Help API and opens the process whose executable name exactly matches `<target-process>`.
4. The CLI resolves the DLL path to an absolute path, allocates memory in the target process with `VirtualAllocEx`, and writes both the loader stub and its argument block with `WriteProcessMemory`.
5. The payload page is switched to executable memory with `VirtualProtectEx`, then started with `CreateRemoteThread`.
6. The loader stub receives one pointer to a small argument struct containing the DLL path, export name, and optional user argument.
7. The stub walks the process PEB loader list to find `kernel32.dll`, then parses its PE export table to resolve `GetProcAddress`, `LoadLibraryA`, and `FreeLibrary`.
8. The stub loads the target DLL, resolves the requested export, calls it, then frees the library.

## Project Layout

- [build.zig](./build.zig): build graph for the executable, sample DLL, and assembled payload
- [src/main.zig](./src/main.zig): CLI entry point, process lookup, remote allocation, and runtime loader setup
- [src/loader.s](./src/loader.s): raw x64 assembly stub executed from allocated memory
- [src/lib.zig](./src/lib.zig): sample DLL export used for local testing
- [src/dynamic.zig](./src/dynamic.zig): experimental helper code that is not currently wired into the build
- `asm/`: scratch assembly examples
- `build/`: generated local binaries checked into the tree

## Calling Convention

The raw loader entry point is called in the target process using the Windows x64 ABI with this argument in `RCX`:

```c
typedef struct {
    const char *dllPath;
    const char *entryPoint;
    void *args;
} s_Args;
```

The loader then calls the resolved DLL export using the Windows x64 ABI.

- The CLI currently passes `null` as the optional user argument.
- The loader places that optional pointer in `RCX` before calling the export.
- The sample DLL declares no parameters and still works; a custom export can accept the pointer explicitly.

A matching Zig export would look like:

```zig
export fn entrypoint(ctx: ?*anyopaque) callconv(.winapi) void {
    _ = ctx;
}
```

## Loader Return Codes

The loader returns a numeric status that `src/main.zig` currently logs at debug level:

| Code | Meaning |
| ---: | --- |
| 0 | Success |
| 1 | Could not find `kernel32.dll` through the PEB loader list |
| 2 | Could not resolve `GetProcAddress` from `kernel32.dll` |
| 3 | Could not resolve `LoadLibraryA` from `kernel32.dll` |
| 4 | Could not resolve `FreeLibrary` from `kernel32.dll` |
| 5 | `LoadLibraryA` failed for the target DLL |
| 6 | `FreeLibrary` failed |
| 7 | `GetProcAddress` failed for the requested target export |

## Current Limitations

- The loader uses `LoadLibraryA`, so non-ASCII DLL paths are not handled correctly.
- The assembly payload is hard-coded for x64 (`use64`), even though the Zig build exposes generic target selection.
- The loader relies on current Windows x64 PEB/LDR and PE export table layouts.
- Target process names are matched exactly and case-sensitively.
- The CLI opens targets with broad process access rights, so protected or higher-integrity processes can fail with access denied.
- Loader return codes are logged but not propagated as process exit codes by the CLI.
- The project has no automated tests at the moment.

## Notes

- `zig build run -- --help` prints:

```text
Usage: ...\hijack.exe <target_process> /path/to/dll <entry_point>
```

The source actually treats the entry point as optional and defaults it to `entrypoint`.
