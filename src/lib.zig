const std = @import("std");

const win = std.os.windows;

extern "user32" fn MessageBoxA(?win.HWND, [*:0]const u8, [*:0]const u8, u32) callconv(.winapi) i32;

export fn displayBox() callconv(.winapi) void {
    _ = MessageBoxA(null, "Hello, World!", "Title", 0);
}
