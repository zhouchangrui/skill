# Skill CLI

A command-line tool for vending and managing LLM skills from a central repository.

## Installation

### Windows

```powershell
# Using pre-compiled binary
# Download the latest release and add it to your PATH
```

### macOS / Linux

```bash
# Clone and build
git clone <this-repo>
cd skill
zig build -Doptimize=ReleaseSafe
# The binary will be available at zig-out/bin/skill
```

## Quick Start

Initialize the skills system in your project:

```bash
skill init --repo http://192.168.36.168:3002/trendy/skills.git
```

This creates a `skills/` directory and saves the configuration to `~/.config/skills/skills.json` (or `%USERPROFILE%\.config\skills\skills.json` on Windows).

## Usage

### Listing Available Skills

View all skills available in the configured remote repository:

```bash
skill list
```

### Adding Skills

Add one or more skills to your local project. By default, they are saved in the `skills/` directory of your current project.

```bash
# Add a skill from a specific path in the remote repository
skill add skills/pdf

# Add multiple skills
skill add skills/pdf skills/pptx

# Add a skill to a custom output directory
skill add skills/pdf -o ./my_custom_folder
```

### Removing Skills

Remove installed skills from your local project.

```bash
# Remove by relative path (assumes it's inside the skills/ directory)
skill remove skills/pdf

# Remove multiple skills
skill remove skills/pdf skills/pptx

# Remove by absolute path
skill remove C:\absolute\path\to\skills\pdf
```

### Updating Skills

Update your local skills to the latest version from the remote repository.

```bash
# Update specific skills
skill update skills/pdf

# Update all installed skills
skill update --all
```

### Environment and Configuration

View the current configuration and repository path:

```bash
skill env
```

### Onboarding

Print the `AGENTS.md` block for LLM instructions to integrate the skills system into your agent workflows:

```bash
skill onboard
```

## Configuration

The configuration file is typically stored at `~/.config/skills/skills.json` (or `%USERPROFILE%\.config\skills\skills.json` on Windows). You can specify the repository and the git reference (branch, tag, or sha).

```json
{
  "repo": "http://192.168.36.168:3002/trendy/skills.git"
  // "branch": "main"
  // "tag": "v1.0.0"
  // "sha": "abc123def456"
}
```

## Building from Source

Requires [Zig](https://ziglang.org/) version 0.15.1 or later.

```bash
zig build -Doptimize=ReleaseSafe
```
