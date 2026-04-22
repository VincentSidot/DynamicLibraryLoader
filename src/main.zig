const std = @import("std");

const log = std.log;
const win = std.os.windows;

extern "kernel32" fn VirtualAlloc(?win.LPVOID, win.SIZE_T, win.DWORD, win.DWORD) callconv(.winapi) ?win.LPVOID;
extern "kernel32" fn VirtualFree(win.LPVOID, win.SIZE_T, win.DWORD) callconv(.winapi) win.BOOL;
extern "kernel32" fn VirtualProtect(win.LPVOID, win.SIZE_T, win.DWORD, *win.DWORD) callconv(.winapi) win.BOOL;

const lp_VoidArgs = ?*anyopaque;
const s_Args = extern struct {
    dllPath: [*:0]const u8,
    entryPoint: [*:0]const u8,
    args: lp_VoidArgs,
};

const LoaderFn = *const fn (*const s_Args) callconv(.winapi) u64;

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

    const loaderPath: s_Args = .{
        .dllPath = dllPath,
        .entryPoint = entryPoint,
        .args = resolved,
    };

    const ret = fnPtr(&loaderPath);

    log.debug("Function {s} returned: {d}", .{ entryPoint, ret });
}

fn printUsage(programName: []const u8) void {
    log.info("Usage: {s} /path/to/dll <entry_point>", .{programName});
}

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.smp_allocator;

    const args = try init.minimal.args.toSlice(allocator);

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage(args[0]);
            return;
        }
    }

    if (args.len < 2) {
        log.err("Invalid number of arguments. Expected 2, got {d}", .{args.len - 1});
        printUsage(args[0]);
        return;
    }

    const dllPath = args[1];
    var entryPoint: [*:0]const u8 = "entrypoint"; // Default entry point
    if (args.len >= 3) {
        entryPoint = args[2];
    }

    try run(dllPath, entryPoint, null);
}
