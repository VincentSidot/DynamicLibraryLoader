const std = @import("std");

const win = std.os.windows;

extern "user32" fn MessageBoxA(?win.HWND, [*:0]const u8, [*:0]const u8, u32) callconv(.winapi) i32;

const Args = extern struct {
    text: [*:0]const u8,
    title: [*:0]const u8,
};

export fn displayBox(args: *const Args) callconv(.winapi) void {
    _ = MessageBoxA(null, args.text, args.title, 0);
}
