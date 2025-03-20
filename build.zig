const std = @import("std");

const Build = std.Build;

pub fn build(builder: *Build) void {

    // Builds application.
    const executable = builder.addExecutable(.{
        .name = "extractor",
        .root_source_file = builder.path("src/main.zig"),
        .target = builder.graph.host,
    });
    builder.installArtifact(executable);

    // Allow users to add "run" after build to run the application executable.
    const run_executable = builder.addRunArtifact(executable);
    const run_step = builder.step("run", "Run application after build");
    run_step.dependOn(&run_executable.step);
}
