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
const GetProcAddressFn = *const fn (win.HMODULE, [*:0]const u8) callconv(.winapi) ?win.FARPROC;
const MessageBoxAFn = *const fn (?win.HWND, [*:0]const u8, [*:0]const u8, u32) callconv(.winapi) i32;

fn run(dllPath: [*:0]const u8, entryPoint: [*:0]const u8) !void {
    const LoaderFn = *const fn (LoadLibraryFn, GetProcAddressFn, [*:0]const u8, [*:0]const u8) callconv(.winapi) i32;

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

    const ret = fnPtr(&LoadLibraryA, &GetProcAddress, dllPath, entryPoint);

    log.debug("Function {s} returned: {d}", .{ entryPoint, ret });
}

pub fn main(init: std.process.Init) !void {
    _ = init;

    const dllPath = "zig-out\\bin\\lib.dll";
    const entryPoint = "displayBox";

    log.info("Hello, World!", .{});

    try run(dllPath, entryPoint);
}
