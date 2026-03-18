const std = @import("std");
const config = @import("config.zig");

pub fn checkGitInstalled(allocator: std.mem.Allocator) !void {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "--version" },
    }) catch {
        try std.fs.File.stderr().writeAll("Error: This tool requires git to be installed\n");
        return error.GitNotInstalled;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
}

pub fn listSkills(allocator: std.mem.Allocator, cfg: config.Config) ![][]const u8 {
    try checkGitInstalled(allocator);

    // Create secure temp directory with cryptographic random name
    const temp_dir_path = try createSecureTempDir(allocator);
    defer allocator.free(temp_dir_path);
    defer std.fs.deleteDirAbsolute(temp_dir_path) catch {};

    // Initialize git repo
    try runGitCommand(allocator, &[_][]const u8{ "git", "init" }, temp_dir_path);

    // Add remote
    try runGitCommand(allocator, &[_][]const u8{ "git", "remote", "add", "origin", cfg.repo }, temp_dir_path);

    // Configure sparse checkout
    try runGitCommand(allocator, &[_][]const u8{ "git", "config", "core.sparseCheckout", "true" }, temp_dir_path);

    // Set sparse checkout pattern - fetch all directories at root level
    const sparse_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ temp_dir_path, ".git/info" });
    defer allocator.free(sparse_dir_path);
    std.fs.makeDirAbsolute(sparse_dir_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const sparse_path = try std.fs.path.join(allocator, &[_][]const u8{ temp_dir_path, ".git/info/sparse-checkout" });
    defer allocator.free(sparse_path);

    const sparse_file = try std.fs.createFileAbsolute(sparse_path, .{});
    defer sparse_file.close();
    try sparse_file.writeAll("*/\n");

    // Fetch based on ref type
    const ref = if (cfg.ref_value) |r| r else "HEAD";

    var fetch_argv = try std.ArrayList([]const u8).initCapacity(allocator, 6);
    defer fetch_argv.deinit(allocator);
    try fetch_argv.appendSlice(allocator, &[_][]const u8{ "git", "fetch", "--depth", "1", "origin" });

    switch (cfg.ref_type) {
        .branch => try fetch_argv.append(allocator, try std.fmt.allocPrint(allocator, "{s}:{s}", .{ ref, ref })),
        .tag, .sha => try fetch_argv.append(allocator, ref),
        .none => try fetch_argv.append(allocator, "HEAD"),
    }

    try runGitCommand(allocator, fetch_argv.items, temp_dir_path);
    if (cfg.ref_type == .branch) {
        allocator.free(fetch_argv.items[fetch_argv.items.len - 1]);
    }

    // Checkout
    try runGitCommand(allocator, &[_][]const u8{ "git", "checkout", "FETCH_HEAD" }, temp_dir_path);

    // List skill directories at root level
    var skills_dir = try std.fs.openDirAbsolute(temp_dir_path, .{ .iterate = true });
    defer skills_dir.close();

    var skills = try std.ArrayList([]const u8).initCapacity(allocator, 10);
    errdefer {
        for (skills.items) |skill| {
            allocator.free(skill);
        }
        skills.deinit(allocator);
    }

    var iter = skills_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .directory) {
            // Skip .git directory
            if (std.mem.eql(u8, entry.name, ".git")) continue;
            try skills.append(allocator, try allocator.dupe(u8, entry.name));
        }
    }

    return skills.toOwnedSlice(allocator);
}

pub fn fetchSkill(allocator: std.mem.Allocator, cfg: config.Config, skill_name: []const u8, dest_path: []const u8) !void {
    try checkGitInstalled(allocator);

    // Create secure temp directory with cryptographic random name
    const temp_dir_path = try createSecureTempDir(allocator);
    defer allocator.free(temp_dir_path);
    defer std.fs.deleteDirAbsolute(temp_dir_path) catch {};

    // Initialize git repo
    try runGitCommand(allocator, &[_][]const u8{ "git", "init" }, temp_dir_path);

    // Add remote
    try runGitCommand(allocator, &[_][]const u8{ "git", "remote", "add", "origin", cfg.repo }, temp_dir_path);

    // Configure sparse checkout
    try runGitCommand(allocator, &[_][]const u8{ "git", "config", "core.sparseCheckout", "true" }, temp_dir_path);

    // Set sparse checkout pattern for specific skill
    const sparse_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ temp_dir_path, ".git/info" });
    defer allocator.free(sparse_dir_path);
    std.fs.makeDirAbsolute(sparse_dir_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const sparse_path = try std.fs.path.join(allocator, &[_][]const u8{ temp_dir_path, ".git/info/sparse-checkout" });
    defer allocator.free(sparse_path);

    const sparse_file = try std.fs.createFileAbsolute(sparse_path, .{});
    defer sparse_file.close();

    // Support nested skills (e.g. skills/pdf)
    const pattern = try std.fmt.allocPrint(allocator, "{s}/\n", .{skill_name});
    defer allocator.free(pattern);
    try sparse_file.writeAll(pattern);

    // Fetch based on ref type
    const ref = if (cfg.ref_value) |r| r else "HEAD";
    var fetch_argv = try std.ArrayList([]const u8).initCapacity(allocator, 6);
    defer fetch_argv.deinit(allocator);
    try fetch_argv.appendSlice(allocator, &[_][]const u8{ "git", "fetch", "--depth", "1", "origin" });

    switch (cfg.ref_type) {
        .branch => try fetch_argv.append(allocator, try std.fmt.allocPrint(allocator, "{s}:{s}", .{ ref, ref })),
        .tag, .sha => try fetch_argv.append(allocator, ref),
        .none => try fetch_argv.append(allocator, "HEAD"),
    }

    try runGitCommand(allocator, fetch_argv.items, temp_dir_path);
    if (cfg.ref_type == .branch) {
        allocator.free(fetch_argv.items[fetch_argv.items.len - 1]);
    }

    // Checkout
    try runGitCommand(allocator, &[_][]const u8{ "git", "checkout", "FETCH_HEAD" }, temp_dir_path);

    // Copy skill directory to destination
    // If skill_name is a path (e.g. "skills/pdf"), we need to use the full path to find it in the temp repo
    const skill_source = try std.fs.path.join(allocator, &[_][]const u8{ temp_dir_path, skill_name });
    defer allocator.free(skill_source);

    // Verify source exists
    var dir = std.fs.openDirAbsolute(skill_source, .{}) catch {
        return error.SkillNotFound;
    };
    dir.close();

    try copyDirectory(allocator, skill_source, dest_path);
}

fn runGitCommand(allocator: std.mem.Allocator, argv: []const []const u8, cwd: []const u8) !void {
    var child = std.process.Child.init(argv, allocator);
    child.cwd = cwd;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Pipe;

    try child.spawn();
    const stderr = try child.stderr.?.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(stderr);

    const term = try child.wait();
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                const msg = try std.fmt.allocPrint(allocator, "Error: Git command failed: {s}\n", .{stderr});
                defer allocator.free(msg);
                try std.fs.File.stderr().writeAll(msg);
                return error.GitCommandFailed;
            }
        },
        else => return error.GitCommandFailed,
    }
}

fn copyDirectory(allocator: std.mem.Allocator, source: []const u8, dest: []const u8) !void {
    var source_dir = try std.fs.openDirAbsolute(source, .{ .iterate = true });
    defer source_dir.close();

    try std.fs.cwd().makePath(dest);
    var dest_dir = try std.fs.cwd().openDir(dest, .{});
    defer dest_dir.close();

    var iter = source_dir.iterate();
    while (try iter.next()) |entry| {
        // Security: Skip symlinks to prevent symlink attacks
        if (entry.kind == .sym_link) {
            const msg = try std.fmt.allocPrint(allocator, "Warning: Skipping symlink: {s}\n", .{entry.name});
            defer allocator.free(msg);
            try std.fs.File.stderr().writeAll(msg);
            continue;
        }

        if (entry.kind == .directory) {
            const sub_source = try std.fs.path.join(allocator, &[_][]const u8{ source, entry.name });
            defer allocator.free(sub_source);
            const sub_dest = try std.fs.path.join(allocator, &[_][]const u8{ dest, entry.name });
            defer allocator.free(sub_dest);
            try copyDirectory(allocator, sub_source, sub_dest);
        } else if (entry.kind == .file) {
            try source_dir.copyFile(entry.name, dest_dir, entry.name, .{});
        }
    }
}

fn createSecureTempDir(allocator: std.mem.Allocator) ![]const u8 {
    const tmp_dir_base = if (std.process.getEnvVarOwned(allocator, "TMPDIR")) |tmp|
        tmp
    else |_| if (std.process.getEnvVarOwned(allocator, "TEMP")) |temp|
        temp
    else |_| if (std.process.getEnvVarOwned(allocator, "TMP")) |tmp2|
        tmp2
    else |_| try allocator.dupe(u8, "/tmp");
    defer allocator.free(tmp_dir_base);

    // Use cryptographically random name to prevent race conditions
    var random_bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&random_bytes);
    const random_hex = std.fmt.bytesToHex(random_bytes, .lower);

    const temp_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_dir_base, &random_hex });
    errdefer allocator.free(temp_dir_path);

    // Create directory - fails if already exists (prevents race condition)
    std.fs.makeDirAbsolute(temp_dir_path) catch |err| {
        allocator.free(temp_dir_path);
        return err;
    };

    return temp_dir_path;
}
