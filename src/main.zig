const std = @import("std");
const config = @import("config.zig");
const commands = @import("commands.zig");

const VERSION = "0.2.0";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
        std.process.exit(1);
    }

    const command = args[1];

    // Handle --version flag
    if (std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "-v")) {
        const msg = try std.fmt.allocPrint(allocator, "skill version {s}\n", .{VERSION});
        defer allocator.free(msg);
        try std.fs.File.stdout().writeAll(msg);
        return;
    }

    // Handle --help flag
    if (std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h") or std.mem.eql(u8, command, "help")) {
        try printUsage();
        return;
    }

    if (std.mem.eql(u8, command, "init")) {
        try commands.init(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "list")) {
        try commands.list(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "add")) {
        try commands.add(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "remove")) {
        try commands.remove(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "update")) {
        try commands.update(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "env")) {
        try commands.env(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "onboard")) {
        try commands.onboard(allocator, args[2..]);
    } else {
        std.debug.print("Error: Unknown command '{s}'\n", .{command});
        try printUsage();
        std.process.exit(1);
    }
}

fn printUsage() !void {
    const stdout = std.fs.File.stdout();
    try stdout.writeAll(
        \\skill - Vendor and manage LLM skills from a central repository
        \\
        \\Usage:
        \\  skill <command> [options]
        \\
        \\Commands:
        \\  init      Initialize skills system in current project
        \\  list      List all available skills from remote repository
        \\  add       Add one or more skills to the project
        \\  remove    Remove one or more skills from the project
        \\  update    Update skills to latest version
        \\  env       Show configuration path and values
        \\  onboard   Print AGENTS.md block for LLM instructions
        \\
        \\Examples:
        \\  skill init
        \\  skill init --repo https://github.com/org/skills
        \\  skill list
        \\  skill add skills/docs
        \\  skill add skills/pdf -o ./my_skills/
        \\  skill remove skills/docs
        \\  skill remove C:\absolute\path\to\skills\pdf
        \\  skill update --all
        \\  skill env
        \\  skill onboard
        \\
    );
}
