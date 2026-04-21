const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const loader_path = b.path("src/loader.s");

    // Build dll library
    const lib = b.addLibrary(.{
        .name = "lib",
        .linkage = .dynamic,
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(lib);

    // Run FASM to produce a raw binary blob for @embedFile
    const fasm = b.addSystemCommand(&.{"fasm"});
    fasm.addFileArg(loader_path);
    const asm_bin = fasm.addOutputFileArg("payload.bin");

    // Build executable
    const exe = b.addExecutable(.{
        .name = "hijack",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),

            .target = target,
            .optimize = optimize,
        }),
    });
    // Make the generated payload visible to @embedFile("payload_bin")
    exe.root_module.addAnonymousImport("payload_bin", .{
        .root_source_file = asm_bin,
    });

    b.installArtifact(exe);

    // Setup run steps
    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
