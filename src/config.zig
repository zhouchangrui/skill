const std = @import("std");

pub const DEFAULT_REPO = "git@github.com:DockYard/skills.git";

pub const RefType = enum {
    none,
    branch,
    tag,
    sha,
};

pub const Config = struct {
    repo: []const u8,
    ref_type: RefType,
    ref_value: ?[]const u8,

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        allocator.free(self.repo);
        if (self.ref_value) |ref| {
            allocator.free(ref);
        }
    }
};

pub fn loadConfig(allocator: std.mem.Allocator) !Config {
    // Try local config first
    if (loadConfigFromPath(allocator, ".config/skills/skills.json")) |cfg| {
        return cfg;
    } else |_| {}

    // Try global config
    const home_dir = if (std.process.getEnvVarOwned(allocator, "HOME")) |home|
        home
    else |err| switch (err) {
        error.EnvironmentVariableNotFound => if (std.process.getEnvVarOwned(allocator, "USERPROFILE")) |profile|
            profile
        else |_| return Config{
            .repo = try allocator.dupe(u8, DEFAULT_REPO),
            .ref_type = .none,
            .ref_value = null,
        },
        else => return Config{
            .repo = try allocator.dupe(u8, DEFAULT_REPO),
            .ref_type = .none,
            .ref_value = null,
        },
    };
    defer allocator.free(home_dir);

    const global_config_path = try std.fs.path.join(allocator, &[_][]const u8{
        home_dir,
        ".config/skills/skills.json",
    });
    defer allocator.free(global_config_path);

    if (loadConfigFromPath(allocator, global_config_path)) |cfg| {
        return cfg;
    } else |_| {}

    // Return default
    return Config{
        .repo = try allocator.dupe(u8, DEFAULT_REPO),
        .ref_type = .none,
        .ref_value = null,
    };
}

fn loadConfigFromPath(allocator: std.mem.Allocator, path: []const u8) !Config {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    // Parse JSON5 (for now, we'll parse as JSON and strip comments manually)
    const cleaned = try stripComments(allocator, content);
    defer allocator.free(cleaned);

    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        cleaned,
        .{},
    );
    defer parsed.deinit();

    const root = parsed.value.object;

    const repo_raw = if (root.get("repo")) |r|
        r.string
    else
        return error.MissingRepo;
        
    const repo = try allocator.dupe(u8, std.mem.trim(u8, repo_raw, " `\t\n\r"));

    // Check for ref types
    var ref_type: RefType = .none;
    var ref_value: ?[]const u8 = null;
    var ref_count: u8 = 0;

    if (root.get("branch")) |b| {
        ref_type = .branch;
        ref_value = try allocator.dupe(u8, b.string);
        ref_count += 1;
    }
    if (root.get("tag")) |t| {
        if (ref_count > 0) return error.MultipleRefTypes;
        ref_type = .tag;
        ref_value = try allocator.dupe(u8, t.string);
        ref_count += 1;
    }
    if (root.get("sha")) |s| {
        if (ref_count > 0) return error.MultipleRefTypes;
        ref_type = .sha;
        ref_value = try allocator.dupe(u8, s.string);
        ref_count += 1;
    }

    return Config{
        .repo = repo,
        .ref_type = ref_type,
        .ref_value = ref_value,
    };
}

fn stripComments(allocator: std.mem.Allocator, content: []const u8) ![]u8 {
    var result = try std.ArrayList(u8).initCapacity(allocator, content.len);
    errdefer result.deinit(allocator);

    var in_string: bool = false;
    var escape: bool = false;

    var i: usize = 0;
    while (i < content.len) {
        if (!in_string and i + 1 < content.len and content[i] == '/' and content[i + 1] == '/') {
            // Skip until end of line
            while (i < content.len and content[i] != '\n') : (i += 1) {}
            continue;
        }

        if (!escape and content[i] == '"') {
            in_string = !in_string;
        }

        if (in_string and content[i] == '\\' and !escape) {
            escape = true;
        } else {
            escape = false;
        }

        try result.append(allocator, content[i]);
        i += 1;
    }

    return result.toOwnedSlice(allocator);
}

pub fn saveConfig(allocator: std.mem.Allocator, cfg: Config) !void {
    // Create .config/skills directory
    try std.fs.cwd().makePath(".config/skills");

    const file = try std.fs.cwd().createFile(".config/skills/skills.json", .{});
    defer file.close();

    // Build JSON content
    const content = if (cfg.ref_value) |ref| blk: {
        const ref_line = switch (cfg.ref_type) {
            .branch => try std.fmt.allocPrint(allocator, ",\n  \"branch\": \"{s}\"", .{ref}),
            .tag => try std.fmt.allocPrint(allocator, ",\n  \"tag\": \"{s}\"", .{ref}),
            .sha => try std.fmt.allocPrint(allocator, ",\n  \"sha\": \"{s}\"", .{ref}),
            .none => try allocator.dupe(u8, ""),
        };
        defer allocator.free(ref_line);

        break :blk try std.fmt.allocPrint(allocator, "{{\n  \"repo\": \"{s}\"{s}\n}}\n", .{ cfg.repo, ref_line });
    } else try std.fmt.allocPrint(allocator,
        \\{{
        \\  "repo": "{s}"
        \\  // "branch": "main"
        \\  // "tag": "v1.0.0"
        \\  // "sha": "abc123def456"
        \\}}
        \\
    , .{cfg.repo});
    defer allocator.free(content);

    try file.writeAll(content);
}

pub fn getConfigSource(allocator: std.mem.Allocator) ![]const u8 {
    // Check local first
    std.fs.cwd().access(".config/skills/skills.json", .{}) catch |err| {
        if (err == error.FileNotFound) {
            // Check global
            const home_dir = if (std.process.getEnvVarOwned(allocator, "HOME")) |home|
                home
            else |e| switch (e) {
                error.EnvironmentVariableNotFound => if (std.process.getEnvVarOwned(allocator, "USERPROFILE")) |profile|
                    profile
                else |_| return try allocator.dupe(u8, "default"),
                else => return try allocator.dupe(u8, "default"),
            };
            defer allocator.free(home_dir);

            const global_path = try std.fs.path.join(allocator, &[_][]const u8{
                home_dir,
                ".config/skills/skills.json",
            });
            defer allocator.free(global_path);

            std.fs.cwd().access(global_path, .{}) catch {
                return try allocator.dupe(u8, "default");
            };

            return try std.fs.path.join(allocator, &[_][]const u8{
                home_dir,
                ".config/skills/skills.json",
            });
        }
        return err;
    };

    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    return try std.fs.path.join(allocator, &[_][]const u8{
        cwd,
        ".config/skills/skills.json",
    });
}
