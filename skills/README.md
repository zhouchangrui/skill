# Skills System

## Instructions for AI Agents

You MUST follow this precedence order when reading skills:

1. Read `SKILL.md` for the base skill instructions
2. If `OVERRIDE.md` exists in the same directory, it takes precedence and overrides `SKILL.md`
3. Always check for `OVERRIDE.md` before applying skill instructions

## Discovering Skills

To discover available skills in this project:

1. List all directories under `skills/`
2. Each directory represents one skill
3. Read the `SKILL.md` file in each skill directory for instructions
4. Check for `OVERRIDE.md` which contains local customizations

## Precedence Rules

- `OVERRIDE.md` is local-only and takes absolute precedence over `SKILL.md`
- `OVERRIDE.md` is gitignored to keep local customizations out of version control
- When both files exist, apply `OVERRIDE.md` instructions instead of `SKILL.md`
- Never assume all skills exist; only use those present under `skills/`

## Using Skills

When applying skills to your work:

1. Read `AGENTS.md` first for project-level behavior
2. Read this `skills/README.md` for system rules
3. For each required skill:
   - Read `skills/<name>/SKILL.md` first
   - If `skills/<name>/OVERRIDE.md` exists, use it instead

## Examples

If you need to apply the "testing" skill:
- Check if `skills/testing/` exists
- Read `skills/testing/SKILL.md`
- Check if `skills/testing/OVERRIDE.md` exists and use it if present

## Maintenance

Skills are managed using the `skill` CLI:

- Add skills: `skill add <name>`
- Remove skills: `skill remove <name>`
- Update skills: `skill update --all` or `skill update <name>`
- List available skills: `skill list`
