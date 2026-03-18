const std = @import("std");
const config_mod = @import("config.zig");
const git = @import("git.zig");
const render = @import("render.zig");

// Helper functions for I/O
fn print(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const msg = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(msg);
    try std.fs.File.stdout().writeAll(msg);
}

fn eprint(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const msg = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(msg);
    try std.fs.File.stderr().writeAll(msg);
}

pub fn init(allocator: std.mem.Allocator, args: []const []const u8) !void {
    // Check if skills/ already exists
    if (std.fs.cwd().access("skills", .{})) {
        try eprint(allocator, "Error: skills/ directory already exists. Project already initialized.\n", .{});
        std.process.exit(1);
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    // Parse arguments
    var repo: ?[]const u8 = null;
    var ref_type: config_mod.RefType = .none;
    var ref_value: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--repo") and i + 1 < args.len) {
            repo = std.mem.trim(u8, args[i + 1], " `\t\n\r");
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--branch") and i + 1 < args.len) {
            if (ref_type != .none) {
                try eprint(allocator, "Error: Only one of --branch, --tag, or --sha can be specified\n", .{});
                std.process.exit(1);
            }
            ref_type = .branch;
            ref_value = std.mem.trim(u8, args[i + 1], " `\t\n\r");
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--tag") and i + 1 < args.len) {
            if (ref_type != .none) {
                try eprint(allocator, "Error: Only one of --branch, --tag, or --sha can be specified\n", .{});
                std.process.exit(1);
            }
            ref_type = .tag;
            ref_value = std.mem.trim(u8, args[i + 1], " `\t\n\r");
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--sha") and i + 1 < args.len) {
            if (ref_type != .none) {
                try eprint(allocator, "Error: Only one of --branch, --tag, or --sha can be specified\n", .{});
                std.process.exit(1);
            }
            ref_type = .sha;
            ref_value = std.mem.trim(u8, args[i + 1], " `\t\n\r");
            i += 1;
        }
    }

    // Load or create config
    var cfg = if (repo != null or ref_value != null) blk: {
        const cfg_repo = repo orelse config_mod.DEFAULT_REPO;
        break :blk config_mod.Config{
            .repo = try allocator.dupe(u8, cfg_repo),
            .ref_type = ref_type,
            .ref_value = if (ref_value) |r| try allocator.dupe(u8, r) else null,
        };
    } else try config_mod.loadConfig(allocator);
    defer cfg.deinit(allocator);

    // Display source repo
    try print(allocator, "Initializing skills system with repository: {s}\n", .{cfg.repo});

    // Create skills/ directory
    try std.fs.cwd().makeDir("skills");

    // Create skills/.gitignore
    const gitignore_file = try std.fs.cwd().createFile("skills/.gitignore", .{});
    defer gitignore_file.close();
    try gitignore_file.writeAll("*/OVERRIDE.md\n");

    // Generate skills/README.md
    try render.saveSkillsReadme(allocator);

    // Save config if flags were provided
    if (repo != null or ref_value != null) {
        try config_mod.saveConfig(allocator, cfg);
    }

    try std.fs.File.stdout().writeAll("✓ Created skills/ directory\n");
    try std.fs.File.stdout().writeAll("✓ Created skills/.gitignore\n");
    try std.fs.File.stdout().writeAll("✓ Created skills/README.md\n");
    if (repo != null or ref_value != null) {
        try std.fs.File.stdout().writeAll("✓ Saved configuration to .config/skills/skills.json\n");
    }
    try std.fs.File.stdout().writeAll("\n");

    // Print AGENTS.md block
    const agents_block = try render.generateAgentsBlock(allocator, cfg.repo);
    defer allocator.free(agents_block);
    try std.fs.File.stdout().writeAll(agents_block);
}

pub fn list(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = args;

    const cfg = try config_mod.loadConfig(allocator);
    defer {
        var mut_cfg = cfg;
        mut_cfg.deinit(allocator);
    }

    try print(allocator, "Fetching skills from {s}...\n\n", .{cfg.repo});

    const skills = try git.listSkills(allocator, cfg);
    defer {
        for (skills) |skill| {
            allocator.free(skill);
        }
        allocator.free(skills);
    }

    if (skills.len == 0) {
        try std.fs.File.stdout().writeAll("No skills found in repository.\n");
        return;
    }

    try std.fs.File.stdout().writeAll("Available skills:\n\n");
    for (skills) |skill| {
        try print(allocator, "  {s}\n", .{skill});
    }
}

pub fn add(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        try eprint(allocator, "Error: No skills specified. Usage: skill add <name> [<name> ...] [-o <output_dir>]\n", .{});
        std.process.exit(1);
    }

    // Parse arguments
    var skill_names = try std.ArrayList([]const u8).initCapacity(allocator, args.len);
    defer skill_names.deinit(allocator);
    var output_dir: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if ((std.mem.eql(u8, args[i], "-o") or std.mem.eql(u8, args[i], "--output")) and i + 1 < args.len) {
            output_dir = args[i + 1];
            i += 1;
        } else {
            try skill_names.append(allocator, args[i]);
        }
    }

    if (skill_names.items.len == 0) {
        try eprint(allocator, "Error: No skills specified. Usage: skill add <name> [<name> ...] [-o <output_dir>]\n", .{});
        std.process.exit(1);
    }

    // Check if skills/ exists when not using custom output dir
    if (output_dir == null) {
        if (std.fs.cwd().access("skills", .{})) {} else |_| {
            try eprint(allocator, "Error: skills/ directory not found. Run 'skill init' first or use -o to specify output directory.\n", .{});
            std.process.exit(1);
        }
    } else {
        // Ensure output dir exists or create it
        if (std.fs.cwd().access(output_dir.?, .{})) {} else |_| {
            try std.fs.cwd().makePath(output_dir.?);
        }
    }

    const cfg = try config_mod.loadConfig(allocator);
    defer {
        var mut_cfg = cfg;
        mut_cfg.deinit(allocator);
    }

    var had_errors = false;

    for (skill_names.items) |skill_name| {
        // Handle nested skills (e.g. skills/pdf) by using the basename for local directory
        const skill_basename = std.fs.path.basename(skill_name);
        
        const skill_path = if (output_dir) |dir|
            try std.fs.path.join(allocator, &[_][]const u8{ dir, skill_basename })
        else
            try std.fmt.allocPrint(allocator, "skills/{s}", .{skill_basename});
            
        defer allocator.free(skill_path);

        if (std.fs.cwd().access(skill_path, .{})) {
            try eprint(allocator, "Error: Skill '{s}' already exists at {s}\n", .{ skill_name, skill_path });
            had_errors = true;
            continue;
        } else |err| {
            if (err != error.FileNotFound) {
                try eprint(allocator, "Error: Failed to check skill '{s}': {}\n", .{ skill_name, err });
                had_errors = true;
                continue;
            }
        }

        // Fetch skill from remote
        if (git.fetchSkill(allocator, cfg, skill_name, skill_path)) {
            try print(allocator, "✓ Added skill '{s}' to {s}\n", .{ skill_name, skill_path });
        } else |err| {
            try eprint(allocator, "Error: Failed to fetch skill '{s}': {}\n", .{ skill_name, err });
            had_errors = true;
        }
    }

    // Regenerate README only if we are using the default skills/ directory
    if (output_dir == null) {
        try render.saveSkillsReadme(allocator);
    }

    if (had_errors) {
        std.process.exit(1);
    }
}

pub fn remove(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        try eprint(allocator, "Error: No skills specified. Usage: skill remove <name> [<name> ...]\n", .{});
        std.process.exit(1);
    }

    var had_errors = false;

    for (args) |skill_name| {
        // Handle absolute paths
        const skill_path = if (std.fs.path.isAbsolute(skill_name))
            try allocator.dupe(u8, skill_name)
        else blk: {
            // If it's just a name, assume it's in skills/
            // If it's a relative path that exists, use it
            if (std.fs.cwd().access(skill_name, .{})) {
                 break :blk try allocator.dupe(u8, skill_name);
            } else |_| {
                const skill_basename = std.fs.path.basename(skill_name);
                break :blk try std.fmt.allocPrint(allocator, "skills/{s}", .{skill_basename});
            }
        };
        defer allocator.free(skill_path);

        // Check if skill exists
        // For absolute paths, we need to check if it exists directly
        // For relative paths, we've already constructed the path assuming "skills/" prefix or direct path
        if (std.fs.cwd().access(skill_path, .{})) {} else |err| {
            if (err == error.FileNotFound) {
                // If the user provided a simple name like "pdf" but meant a skill in "skills/pdf",
                // our logic above handles it. But if they provided a full path that doesn't exist,
                // we should report it clearly.
                try eprint(allocator, "Error: Skill '{s}' not found at {s}\n", .{ skill_name, skill_path });
                had_errors = true;
                continue;
            }
            return err;
        }

        // Check for OVERRIDE.md
        // If skill_path is a file path, we need to join it
        const override_path = try std.fs.path.join(allocator, &[_][]const u8{ skill_path, "OVERRIDE.md" });
        defer allocator.free(override_path);

        const has_override = if (std.fs.cwd().access(override_path, .{})) true else |_| false;

        if (has_override) {
            try print(allocator, "Skill '{s}' has an OVERRIDE.md file. Remove anyway? [y/N]: ", .{skill_name});

            const stdin = std.fs.File.stdin();
            var buf: [10]u8 = undefined;
            const amt = try stdin.read(&buf);
            const response = buf[0..amt];
            const trimmed = std.mem.trim(u8, response, &std.ascii.whitespace);

            if (!std.mem.eql(u8, trimmed, "y") and !std.mem.eql(u8, trimmed, "Y")) {
                try print(allocator, "Skipped '{s}'\n", .{skill_name});
                continue;
            }
        }

        // Remove the skill directory
        if (std.fs.path.isAbsolute(skill_path)) {
            try std.fs.deleteTreeAbsolute(skill_path);
        } else {
            try std.fs.cwd().deleteTree(skill_path);
        }
        try print(allocator, "✓ Removed skill '{s}'\n", .{skill_name});
    }

    // Only regenerate README if skills/ directory still exists
    if (std.fs.cwd().access("skills", .{})) {
        try render.saveSkillsReadme(allocator);
    } else |_| {}

    if (had_errors) {
        std.process.exit(1);
    }
}

pub fn update(allocator: std.mem.Allocator, args: []const []const u8) !void {
    // Check if skills/ exists
    if (std.fs.cwd().access("skills", .{})) {} else |_| {
        try eprint(allocator, "Error: skills/ directory not found. Run 'skill init' first.\n", .{});
        std.process.exit(1);
    }

    const cfg = try config_mod.loadConfig(allocator);
    defer {
        var mut_cfg = cfg;
        mut_cfg.deinit(allocator);
    }

    // If no args, show usage
    if (args.len == 0) {
        try std.fs.File.stdout().writeAll("Installed skills:\n\n");

        var skills_dir = try std.fs.cwd().openDir("skills", .{ .iterate = true });
        defer skills_dir.close();

        var iter = skills_dir.iterate();
        var has_skills = false;
        while (try iter.next()) |entry| {
            if (entry.kind == .directory) {
                try print(allocator, "  {s}\n", .{entry.name});
                has_skills = true;
            }
        }

        if (!has_skills) {
            try std.fs.File.stdout().writeAll("  (none)\n");
        }

        try std.fs.File.stdout().writeAll(
            \\
            \\Usage:
            \\  skill update <name>     Update specific skill(s)
            \\  skill update --all      Update all skills
            \\
        );
        return;
    }

    var had_errors = false;

    // Check for --all flag
    if (args.len == 1 and std.mem.eql(u8, args[0], "--all")) {
        // Get all installed skills
        var skills = try std.ArrayList([]const u8).initCapacity(allocator, 10);
        defer {
            for (skills.items) |skill| {
                allocator.free(skill);
            }
            skills.deinit(allocator);
        }

        var skills_dir = try std.fs.cwd().openDir("skills", .{ .iterate = true });
        defer skills_dir.close();

        var iter = skills_dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .directory) {
                try skills.append(allocator, try allocator.dupe(u8, entry.name));
            }
        }

        for (skills.items) |skill_name| {
            try updateSkill(allocator, cfg, skill_name, &had_errors);
        }
    } else {
        // Update specific skills
        for (args) |skill_name| {
            try updateSkill(allocator, cfg, skill_name, &had_errors);
        }
    }

    // Regenerate README
    try render.saveSkillsReadme(allocator);

    if (had_errors) {
        std.process.exit(1);
    }
}

fn updateSkill(
    allocator: std.mem.Allocator,
    cfg: config_mod.Config,
    skill_name: []const u8,
    had_errors: *bool,
) !void {
    const skill_path = try std.fmt.allocPrint(allocator, "skills/{s}", .{skill_name});
    defer allocator.free(skill_path);

    // Check if skill exists locally
    if (std.fs.cwd().access(skill_path, .{})) {} else |err| {
        if (err == error.FileNotFound) {
            try eprint(allocator, "Error: Skill '{s}' not installed locally\n", .{skill_name});
            had_errors.* = true;
            return;
        }
        return err;
    }

    // Check for OVERRIDE.md
    const override_path = try std.fmt.allocPrint(allocator, "skills/{s}/OVERRIDE.md", .{skill_name});
    defer allocator.free(override_path);

    var override_content: ?[]u8 = null;
    defer if (override_content) |c| allocator.free(c);

    if (std.fs.cwd().openFile(override_path, .{})) |file| {
        defer file.close();
        override_content = try file.readToEndAlloc(allocator, 1024 * 1024);
    } else |_| {}

    // Delete skill directory
    try std.fs.cwd().deleteTree(skill_path);

    // Fetch fresh copy
    if (git.fetchSkill(allocator, cfg, skill_name, skill_path)) {
        // Restore OVERRIDE.md if it existed
        if (override_content) |content| {
            const override_file = try std.fs.cwd().createFile(override_path, .{});
            defer override_file.close();
            try override_file.writeAll(content);
        }

        try print(allocator, "✓ Updated skill '{s}'\n", .{skill_name});
    } else |_| {
        // If fetch fails, skill might not exist remotely - silently skip for --all
        try eprint(allocator, "Error: Failed to update skill '{s}'\n", .{skill_name});
        had_errors.* = true;
    }
}

pub fn env(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = args;

    const cfg = try config_mod.loadConfig(allocator);
    defer {
        var mut_cfg = cfg;
        mut_cfg.deinit(allocator);
    }

    const config_source = try config_mod.getConfigSource(allocator);
    defer allocator.free(config_source);

    try print(allocator, "Version: 0.2.0\n", .{});
    try print(allocator, "Config: {s}\n", .{config_source});
    try print(allocator, "Repository: {s}\n", .{cfg.repo});

    if (cfg.ref_value) |ref| {
        switch (cfg.ref_type) {
            .branch => try print(allocator, "Branch: {s}\n", .{ref}),
            .tag => try print(allocator, "Tag: {s}\n", .{ref}),
            .sha => try print(allocator, "SHA: {s}\n", .{ref}),
            .none => {},
        }
    }
}

pub fn onboard(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = args;

    const cfg = try config_mod.loadConfig(allocator);
    defer {
        var mut_cfg = cfg;
        mut_cfg.deinit(allocator);
    }

    const agents_block = try render.generateAgentsBlock(allocator, cfg.repo);
    defer allocator.free(agents_block);

    try std.fs.File.stdout().writeAll(agents_block);
}
