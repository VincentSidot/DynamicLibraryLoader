const std = @import("std");

const win = std.os.windows;

extern "user32" fn MessageBoxA(?win.HWND, [*:0]const u8, [*:0]const u8, u32) callconv(.winapi) i32;

const message: [*:0]const u8 = "Hello from the DLL!";
const title: [*:0]const u8 = "DLL Message";

export fn entrypoint() callconv(.winapi) void {
    _ = MessageBoxA(null, message, title, 0);
}
