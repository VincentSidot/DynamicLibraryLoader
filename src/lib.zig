const std = @import("std");

const win = std.os.windows;

extern "kernel32" fn GetModuleFileNameA(?win.HMODULE, ?[*]u8, u32) callconv(.winapi) u32;
extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) u32;

extern "user32" fn MessageBoxA(?win.HWND, [*:0]const u8, [*:0]const u8, u32) callconv(.winapi) i32;

const title: [*:0]const u8 = "Hijack Demo";

export fn entrypoint() callconv(.winapi) void {
    const allocator = std.heap.page_allocator;

    // Fetch the program's name for the message box title
    const bufferSize = 260; // MAX_PATH
    var buffer: [bufferSize]u8 = undefined; // MAX_PATH is 260
    const length = GetModuleFileNameA(null, &buffer, bufferSize);
    const programName = if (length > 0) buffer[0..length] else "Unknown Program";

    const pid = GetCurrentProcessId();

    const message = std.fmt.allocPrintSentinel(
        allocator,
        "Hello from process ID: {d}\nProgram: {s}",
        .{ pid, programName },
        0,
    ) catch {
        return;
    };
    defer allocator.free(message);

    _ = MessageBoxA(null, message, title, 0);
}
