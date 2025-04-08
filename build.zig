const std = @import("std");

const Build = std.Build;

pub fn build(builder: *Build) void {

    // Builds application.
    const executable = builder.addExecutable(.{
        .name = "extractor",
        .root_source_file = builder.path("src/extract_tables.zig"),
        .target = builder.graph.host,
    });
    builder.installArtifact(executable);

    // Allow users to add "run" after build to run the application executable.
    const run_executable = builder.addRunArtifact(executable);
    const run_step = builder.step("run", "Run application");
    run_step.dependOn(&run_executable.step);

    // Allow users to add "test" after build to execute test cases.
    const unit_tests = builder.addTest(.{
        .root_source_file = builder.path("src/modules.zig"),
        .target = builder.graph.host,
    });
    const test_executable = builder.addRunArtifact(unit_tests);
    const test_step = builder.step("test", "Run unit tests");
    test_step.dependOn(&test_executable.step);
}
