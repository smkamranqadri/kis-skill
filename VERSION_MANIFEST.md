# KIS Skill Version Manifest

Active version: `0.6.4`

## Active Package

`.agents/skills/kis/` is the active skill package. `.claude/skills/kis` is a compatibility link for Claude clients that scan `.claude/skills/`.

The active package is based on `archive/kis-v0.5.0-todo-kis-system-4` with host-neutral specialist routing for Codex and Claude.

## Archived Candidates

| Version | Source | Path | Notes |
| --- | --- | --- | --- |
| `0.1.0` | `marble-game` | `archive/kis-v0.1.0-marble-game` | Single-file `.claude` skill, structurally valid, 631 lines. |
| `0.2.0` | `todo-kis-system` | `archive/kis-v0.2.0-todo-kis-system` | Single-file `.claude` skill, structurally valid, 1236 lines. |
| `0.3.0` | `todo-kis-system-2` | `archive/kis-v0.3.0-todo-kis-system-2` | Single-file `.claude` skill, malformed frontmatter, 1771 lines. |
| `0.4.0` | `todo-kis-system-3` | `archive/kis-v0.4.0-todo-kis-system-3` | Packaged `.agent` skill with `references/` and `agents/openai.yaml`, structurally valid, 306-line entrypoint. |
| `0.5.0` | `todo-kis-system-4` | `archive/kis-v0.5.0-todo-kis-system-4` | Newer packaged `.agent` skill with updated specialist availability wording, structurally valid, 308-line entrypoint. |

## Selection

`0.6.4` is the most valid current version because it keeps the latest packaged KIS structure, moves the active skill into the `.agents/skills/kis/` cross-client discovery path, preserves install-first/checkpoint behavior for unavailable specialists, makes the active instructions portable across Codex and Claude, adds one-command bootstrap, first-install, and installed-version update tooling, and validates with an official `uv` path or Ruby fallback.
