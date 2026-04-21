const std = @import("std");
const win = std.os.windows;

const LoadLibraryFn = *const fn ([*:0]const u8) callconv(.winapi) ?win.HMODULE;
const GetProcAddressFn = *const fn (win.HMODULE, [*:0]const u8) callconv(.winapi) ?win.FARPROC;
const MessageBoxAFn = *const fn (?win.HWND, [*:0]const u8, [*:0]const u8, u32) callconv(.winapi) i32;

const Args = struct {
    loadLibrary: LoadLibraryFn,
    getProcAddress: GetProcAddressFn,
};

pub fn greet(loadLibrary: LoadLibraryFn, getProcAddress: GetProcAddressFn) void {
    const hHandle = loadLibrary("user32.dll") orelse {
        std.debug.print("Failed to load user32.dll\n", .{});
        return;
    };
    // Note: we never Freelibrary here.

    const raw = getProcAddress(hHandle, "MessageBoxA") orelse {
        std.debug.print("Failed to get address of MessageBoxA\n", .{});
        return;
    };

    const messageBoxA: MessageBoxAFn = @ptrCast(raw);

    _ = messageBoxA(null, "Hello from the dynamic library!", "Hijack", 0);

    return;
}

pub fn __greet_sentinel() void {}

pub const GreetFn = *const fn (LoadLibraryFn, GetProcAddressFn) callconv(.winapi) void;
