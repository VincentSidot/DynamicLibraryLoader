const std = @import("std");

const log = std.log;
const win = std.os.windows;

extern "kernel32" fn LoadLibraryA([*:0]const u8) callconv(.winapi) ?win.HMODULE;
extern "kernel32" fn GetProcAddress(win.HMODULE, [*:0]const u8) callconv(.winapi) ?win.FARPROC;
extern "kernel32" fn FreeLibrary(win.HMODULE) callconv(.winapi) win.BOOL;
extern "kernel32" fn VirtualAlloc(?win.LPVOID, win.SIZE_T, win.DWORD, win.DWORD) callconv(.winapi) ?win.LPVOID;
extern "kernel32" fn VirtualFree(win.LPVOID, win.SIZE_T, win.DWORD) callconv(.winapi) win.BOOL;
extern "kernel32" fn VirtualProtect(win.LPVOID, win.SIZE_T, win.DWORD, *win.DWORD) callconv(.winapi) win.BOOL;

const LoadLibraryFn = *const fn ([*:0]const u8) callconv(.winapi) ?win.HMODULE;
const FreeLibraryFn = *const fn (win.HMODULE) callconv(.winapi) win.BOOL;
const GetProcAddressFn = *const fn (win.HMODULE, [*:0]const u8) callconv(.winapi) ?win.FARPROC;

const s_LoaderFunctions = extern struct {
    loadLibrary: LoadLibraryFn,
    freeLibrary: FreeLibraryFn,
    getProcAddress: GetProcAddressFn,
};

const s_LoaderPath = extern struct {
    dllPath: [*:0]const u8,
    entryPoint: [*:0]const u8,
};

const lp_VoidArgs = ?*anyopaque;

const LoaderFn = *const fn (*const s_LoaderFunctions, *const s_LoaderPath, lp_VoidArgs) callconv(.winapi) i32;

fn run(dllPath: [*:0]const u8, entryPoint: [*:0]const u8, args: anytype) !void {

    // Ensure args is a pointer type
    const ArgsT = @TypeOf(args);
    const info = @typeInfo(ArgsT);

    const resolved: lp_VoidArgs = switch (info) {
        .null => null,
        .pointer => @ptrCast(@constCast(args)),
        .array => @ptrCast(@constCast(&args)),
        else => @compileError("Unsupported args type"),
    };

    // Constants
    const PAGE_EXECUTE_READ: win.DWORD = 0x20;
    const PAGE_READWRITE: win.DWORD = 0x04;
    const MEM_COMMIT: win.DWORD = 0x1000;
    const MEM_RESERVE: win.DWORD = 0x2000;
    const MEM_RELEASE: win.DWORD = 0x8000;

    const rawData = @embedFile("payload_bin");
    log.debug("Raw data length: {d}", .{rawData.len});

    // Allocate memory for the function and copy it there.
    const mem = VirtualAlloc(null, rawData.len, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE) orelse {
        return error.VirtualAllocFailed;
    };
    defer {
        _ = VirtualFree(mem, 0, MEM_RELEASE);
    }
    const dst: []u8 = @as([*]u8, @ptrCast(mem))[0..rawData.len];
    @memcpy(dst, rawData);

    // Change memory protection to executable.
    var oldProtect: win.DWORD = 0;
    if (VirtualProtect(mem, rawData.len, PAGE_EXECUTE_READ, &oldProtect) == .FALSE) {
        return error.VirtualProtectFailed;
    }

    // Call the function from its new location.
    const fnPtr: LoaderFn = @ptrCast(mem);

    const loaderFunction: s_LoaderFunctions = .{
        .loadLibrary = LoadLibraryA,
        .freeLibrary = FreeLibrary,
        .getProcAddress = GetProcAddress,
    };

    const loaderPath: s_LoaderPath = .{
        .dllPath = dllPath,
        .entryPoint = entryPoint,
    };

    const ret = fnPtr(&loaderFunction, &loaderPath, resolved);

    log.debug("Function {s} returned: {d}", .{ entryPoint, ret });
}

pub fn main(init: std.process.Init) !void {
    _ = init;

    const dllPath = "zig-out\\bin\\lib.dll";
    const entryPoint = "displayBox";

    const Args = extern struct {
        text: [*:0]const u8,
        title: [*:0]const u8,
    };

    try run(dllPath, entryPoint, &Args{
        .text = "Hello from the loader!",
        .title = "Loader Message",
    });
}
