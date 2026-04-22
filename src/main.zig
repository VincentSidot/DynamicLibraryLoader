const std = @import("std");

const log = std.log;
const win = std.os.windows;
const math = std.math;

const PROCESSENTRY32W = extern struct {
    dwSize: win.DWORD,
    cntUsage: win.DWORD,
    th32ProcessID: win.DWORD,
    th32DefaultHeapID: usize,
    th32ModuleID: win.DWORD,
    cntThreads: win.DWORD,
    th32ParentProcessID: win.DWORD,
    pcPriClassBase: i32,
    dwFlags: win.DWORD,
    szExeFile: [win.MAX_PATH:0]u16, // WCHAR array
};

const SECURITY_ATTRIBUTES = extern struct {
    nLength: win.DWORD,
    lpSecurityDescriptor: win.LPVOID,
    bInheritHandle: win.BOOL,
};

const LPSECURITY_ATTRIBUTES = *const SECURITY_ATTRIBUTES;

const PTHREAD_START_ROUTINE = *const fn (win.LPVOID) callconv(.winapi) win.DWORD;

const INVALID_HANDLE_VALUE: win.HANDLE = @ptrFromInt(math.maxInt(usize));

extern "kernel32" fn VirtualAlloc(?win.LPVOID, win.SIZE_T, win.DWORD, win.DWORD) callconv(.winapi) ?win.LPVOID;
extern "kernel32" fn VirtualFree(win.LPVOID, win.SIZE_T, win.DWORD) callconv(.winapi) win.BOOL;
extern "kernel32" fn VirtualProtect(win.LPVOID, win.SIZE_T, win.DWORD, *win.DWORD) callconv(.winapi) win.BOOL;
extern "kernel32" fn VirtualAllocEx(win.HANDLE, ?win.LPVOID, win.SIZE_T, win.DWORD, win.DWORD) callconv(.winapi) ?win.LPVOID;
extern "kernel32" fn VirtualFreeEx(win.HANDLE, win.LPVOID, win.SIZE_T, win.DWORD) callconv(.winapi) win.BOOL;
extern "kernel32" fn VirtualProtectEx(win.HANDLE, win.LPVOID, win.SIZE_T, win.DWORD, *win.DWORD) callconv(.winapi) win.BOOL;
extern "kernel32" fn WriteProcessMemory(win.HANDLE, win.LPVOID, win.LPCVOID, win.SIZE_T, ?*win.SIZE_T) callconv(.winapi) win.BOOL;
extern "kernel32" fn CreateRemoteThread(
    win.HANDLE,
    ?LPSECURITY_ATTRIBUTES,
    win.SIZE_T,
    PTHREAD_START_ROUTINE,
    ?win.LPVOID,
    win.DWORD,
    ?*win.DWORD,
) callconv(.winapi) ?win.HANDLE;
extern "kernel32" fn WaitForSingleObject(win.HANDLE, win.DWORD) callconv(.winapi) win.DWORD;
extern "kernel32" fn GetExitCodeThread(win.HANDLE, *win.DWORD) callconv(.winapi) win.BOOL;

extern "user32" fn GetLastError() callconv(.winapi) win.DWORD;
extern "user32" fn CreateToolhelp32Snapshot(win.DWORD, win.DWORD) callconv(.winapi) win.HANDLE;
extern "user32" fn Process32FirstW(win.HANDLE, *PROCESSENTRY32W) callconv(.winapi) win.BOOL;
extern "user32" fn Process32NextW(win.HANDLE, *PROCESSENTRY32W) callconv(.winapi) win.BOOL;
extern "user32" fn OpenProcess(win.DWORD, win.BOOL, win.DWORD) callconv(.winapi) ?win.HANDLE;
extern "user32" fn CloseHandle(win.HANDLE) callconv(.winapi) win.BOOL;

const C = struct {
    // Constants
    const PAGE_EXECUTE_READ: win.DWORD = 0x20;
    const PAGE_READWRITE: win.DWORD = 0x04;
    const MEM_COMMIT: win.DWORD = 0x1000;
    const MEM_RESERVE: win.DWORD = 0x2000;
    const MEM_RELEASE: win.DWORD = 0x8000;

    const INFINITE: win.DWORD = 0xFFFFFFFF;
};

const lp_VoidArgs = ?*anyopaque;
const s_Args = extern struct {
    dllPath: [*:0]const u8,
    entryPoint: [*:0]const u8,
    args: lp_VoidArgs,
};

const LoaderFn = *const fn (*const s_Args) callconv(.winapi) u64;

fn createArgs(dllPath: [*:0]const u8, entryPoint: [*:0]const u8, args: anytype) s_Args {
    const ArgsT = @TypeOf(args);
    const info = @typeInfo(ArgsT);

    const resolved: lp_VoidArgs = switch (info) {
        .null => null,
        .pointer => @ptrCast(@constCast(args)),
        .array => @ptrCast(@constCast(&args)),
        else => @compileError("Unsupported args type"),
    };

    return s_Args{
        .dllPath = dllPath,
        .entryPoint = entryPoint,
        .args = resolved,
    };
}

fn runOnSelf(dllPath: [*:0]const u8, entryPoint: [*:0]const u8, args: anytype) !void {
    const loaderPath = createArgs(dllPath, entryPoint, args);

    const rawData = @embedFile("payload_bin");
    log.debug("Raw data length: {d}", .{rawData.len});

    // Allocate memory for the function and copy it there.
    const mem = VirtualAlloc(null, rawData.len, C.MEM_COMMIT | C.MEM_RESERVE, C.PAGE_READWRITE) orelse {
        return error.VirtualAllocFailed;
    };
    defer {
        _ = VirtualFree(mem, 0, C.MEM_RELEASE);
    }
    const dst: []u8 = @as([*]u8, @ptrCast(mem))[0..rawData.len];
    @memcpy(dst, rawData);

    // Change memory protection to executable.
    var oldProtect: win.DWORD = 0;
    if (VirtualProtect(mem, rawData.len, C.PAGE_EXECUTE_READ, &oldProtect) == .FALSE) {
        return error.VirtualProtectFailed;
    }

    // Call the function from its new location.
    const fnPtr: LoaderFn = @ptrCast(mem);

    const ret = fnPtr(&loaderPath);

    log.debug("Function {s} returned: {d}", .{ entryPoint, ret });
}

fn runOnTarget(
    hProcess: win.HANDLE,
    dllPath: [*:0]const u8,
    entryPoint: [*:0]const u8,
) !void {
    var buffer: [win.MAX_PATH]u8 = undefined;

    // Resolve the dllPath to absolute path if it's relative
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    const dllPathLen = std.mem.len(dllPath);
    const dllPathSlice = dllPath[0..dllPathLen];

    const writeBytes = try std.Io.Dir.cwd().realPathFile(
        io,
        dllPathSlice,
        &buffer,
    );

    buffer[writeBytes] = 0; // Null-terminate the path
    const resolvedDllPath: [*:0]const u8 = @ptrCast(&buffer);

    log.debug("Resolved DLL path: {s}", .{resolvedDllPath});

    // Allocate memory for the function and copy it there.
    const rawPayloadData = @embedFile("payload_bin");
    const remotePayloadFn = VirtualAllocEx(
        hProcess,
        null,
        rawPayloadData.len,
        C.MEM_COMMIT | C.MEM_RESERVE,
        C.PAGE_READWRITE,
    ) orelse {
        return error.VirtualAllocExFailed;
    };
    defer {
        _ = VirtualFreeEx(hProcess, remotePayloadFn, 0, C.MEM_RELEASE);
    }

    // Write the function code to the target process.
    if (WriteProcessMemory(
        hProcess,
        remotePayloadFn,
        rawPayloadData.ptr,
        rawPayloadData.len,
        null,
    ) == .FALSE) {
        return error.WriteProcessMemoryFailed;
    }

    // Change memory protection to executable.
    var oldProtect: win.DWORD = 0;
    if (VirtualProtectEx(
        hProcess,
        remotePayloadFn,
        rawPayloadData.len,
        C.PAGE_EXECUTE_READ,
        &oldProtect,
    ) == .FALSE) {
        return error.VirtualProtectExFailed;
    }

    // Allocate memory for the arguments in the target process.
    const dllPathSize = std.mem.len(resolvedDllPath) + 1; // Include null terminator
    const entryPointSize = std.mem.len(entryPoint) + 1; // Include null terminator
    const remoteArgsSize = @sizeOf(s_Args) + dllPathSize + entryPointSize;

    const remoteArgs = VirtualAllocEx(
        hProcess,
        null,
        remoteArgsSize,
        C.MEM_COMMIT | C.MEM_RESERVE,
        C.PAGE_READWRITE,
    ) orelse {
        return error.VirtualAllocExFailed;
    };
    defer {
        _ = VirtualFreeEx(hProcess, remoteArgs, 0, C.MEM_RELEASE);
    }

    const remoteArgsInt: usize = @intFromPtr(remoteArgs);
    const dllPathAddr = remoteArgsInt + @sizeOf(s_Args);
    const entryPointAddr = dllPathAddr + dllPathSize;

    // Write the arguments to the target process.
    const localArgs: s_Args = .{ .args = null, .dllPath = @ptrFromInt(dllPathAddr), .entryPoint = @ptrFromInt(entryPointAddr) };

    if (WriteProcessMemory(
        hProcess,
        remoteArgs,
        &localArgs,
        @sizeOf(s_Args),
        null,
    ) == .FALSE) {
        return error.WriteProcessMemoryFailed;
    }
    if (WriteProcessMemory(
        hProcess,
        @ptrFromInt(dllPathAddr),
        resolvedDllPath,
        dllPathSize,
        null,
    ) == .FALSE) {
        return error.WriteProcessMemoryFailed;
    }
    if (WriteProcessMemory(
        hProcess,
        @ptrFromInt(entryPointAddr),
        entryPoint,
        entryPointSize,
        null,
    ) == .FALSE) {
        return error.WriteProcessMemoryFailed;
    }

    // Create a remote thread to execute the function.
    var threadId: win.DWORD = 0;
    const hThread = CreateRemoteThread(
        hProcess,
        null,
        0,
        @ptrCast(remotePayloadFn),
        remoteArgs,
        0,
        &threadId,
    ) orelse {
        return error.CreateRemoteThreadFailed;
    };
    defer {
        _ = CloseHandle(hThread);
    }

    log.debug("Created remote thread with ID: {d}", .{threadId});

    log.debug("Waiting for remote thread to finish execution...", .{});

    // Wait for the remote thread to finish execution.
    const waitResult = WaitForSingleObject(hThread, C.INFINITE);
    if (waitResult != 0) {
        return error.WaitForSingleObjectFailed;
    }

    // Fetch the exit code of the remote thread to check for success.
    var exitCode: win.DWORD = 0;
    if (GetExitCodeThread(hThread, &exitCode) == .FALSE) {
        return error.GetExitCodeThreadFailed;
    }

    log.debug("Remote thread exited with code: {d}", .{exitCode});
}

fn compareProcessName(name: [*:0]const u16, target: [*:0]const u8) bool {
    var i: usize = 0;
    while (target[i] != 0) {
        const c: u8 = target[i];
        const d: u16 = name[i];

        if (d & 0xFF00 != 0) {
            return false; // Non-ASCII character found
        }

        if (@as(u8, @intCast(d)) != c) {
            return false; // Character mismatch
        }

        i += 1;
    }

    if (name[i] != 0) {
        return false; // Target string ended but name has more characters
    }

    return true; // All characters matched
}

fn findTargetProcess(target: [*:0]const u8) !win.HANDLE {
    const TH32CS_SNAPPROCESS: win.DWORD = 0x2;
    const STANDARD_RIGHTS_REQUIRED: win.DWORD = 0x000F0000;
    const SYNCHRONIZE: win.DWORD = 0x00100000;
    const PROCESS_ALL_ACCESS: win.DWORD = STANDARD_RIGHTS_REQUIRED | SYNCHRONIZE | 0xFFFF;

    var entry: PROCESSENTRY32W = undefined;
    entry.dwSize = @sizeOf(PROCESSENTRY32W);

    const snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) {
        return error.CreateSnapshotFailed;
    }
    defer {
        _ = CloseHandle(snapshot);
    }

    if (Process32FirstW(snapshot, &entry) == .FALSE) {
        return error.ProcessEnumerationFailed;
    }

    while (true) {
        const exeName = entry.szExeFile;

        if (compareProcessName(&exeName, target)) {
            log.debug("Found target process: {s} (PID: {d})", .{ target, entry.th32ProcessID });

            // Found the target process, now open it with necessary permissions
            const hProcess = OpenProcess(PROCESS_ALL_ACCESS, .FALSE, entry.th32ProcessID) orelse {
                return error.OpenProcessFailed;
            };

            return hProcess;
        }

        if (Process32NextW(snapshot, &entry) == .FALSE) {
            break; // No more processes
        }
    }

    return error.TargetProcessNotFound;
}

const Args = struct {
    targetProcess: [*:0]const u8,
    dllPath: [*:0]const u8,
    entryPoint: [*:0]const u8 = "entrypoint", // Default entry point
};

fn printUsage(programName: []const u8) void {
    log.info("Usage: {s} <target_process> /path/to/dll <entry_point>", .{programName});
}

fn parseArgs(init: *const std.process.Init) !Args {
    const allocator = std.heap.smp_allocator;
    const args = try init.minimal.args.toSlice(allocator);
    const programName = args[0];

    var newArgs: Args = .{
        .targetProcess = undefined,
        .dllPath = undefined,
    };

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage(programName);
            std.process.exit(0); // Early process exit
        }
    }

    if (args.len < 3 or args.len > 4) {
        printUsage(programName);
        log.err("Invalid number of arguments. Expected 2 or 3, got {d}", .{args.len - 1});
        return error.InvalidArguments;
    }

    newArgs.targetProcess = args[1];
    newArgs.dllPath = args[2];

    if (args.len == 4) {
        newArgs.entryPoint = args[3];
    }

    return newArgs;
}

pub fn main(init: std.process.Init) void {
    const args = parseArgs(&init) catch |err| {
        log.err("Failed to parse arguments: {any}", .{err});
        return;
    };

    const hHandle = findTargetProcess(args.targetProcess) catch |err| {
        log.err("Failed to find target process: {any}", .{err});
        return;
    };
    defer {
        _ = CloseHandle(hHandle);
    }

    runOnTarget(hHandle, args.dllPath, args.entryPoint) catch |err| {
        log.err("Failed to run on target: {any}", .{err});
        return;
    };
}
