# KIS Skill

KIS is an Agent Skill for project memory and execution discipline. It works in Claude, Pi, OpenCode, Codex, and Antigravity.

- **Knowledge**: stable facts, architecture, constraints, rules, durable decisions, and `project.md`: what the product is today
- **Intent**: goals, PRDs, plans, acceptance criteria, approved direction, and `compass.md`: where the product is going (why it exists, who it serves, vision, North Star, principles, what not to build, POC versus MVP)
- **State**: branch, current task, blocker, commands, proof, next action

The skill makes an agent recover context before acting, interview you before non-trivial work, verify with proof before calling anything done, and keep project memory synchronized.

## Install

From the project where you want to use KIS:

```bash
curl -fsSL https://raw.githubusercontent.com/smkamranqadri/kis-skill/main/bootstrap.sh \
  | bash -s -- install --repo https://github.com/smkamranqadri/kis-skill.git
```

That gives the project:

```text
.agents/skills/kis/        the skill package, discovered by Pi, OpenCode, Codex, and Antigravity
.agents/hooks.json         Antigravity hook that injects current State at the start of every turn
.codex/hooks.json          Codex SessionStart hook (trust it once with /hooks)
.commandcode/settings.json Command Code SessionStart hook
.claude/skills/kis         link for Claude
.claude/commands/kis       link for Claude commands
.pi/prompts/kis-*.md       links for Pi prompts
.claude/settings.json      SessionStart hook that re-injects current State
AGENTS.md                  KIS block between <!-- kis:anchor:start|end --> markers
```

Useful flags: `--force` to replace an existing install, `--no-commands` or `--no-anchor` to skip a layer, `--ref v0.14.0` to pin a version.

This repository holds the source package under `skills/kis/`; nothing here is a live install. The installer copies it to `.agents/skills/kis` in your project, which is where every host looks.

By default the installer adds Claude and Pi commands, plus Codex prompts when your Codex home (`${CODEX_HOME:-~/.codex}`) already exists, so an update refreshes them too. Codex prompts are the one adapter written outside the project, which is why a machine without Codex is skipped; `--commands-host project` never writes there, and `--host codex` installs them even without a Codex home. OpenCode already finds the skill without commands, so its commands are opt-in:

```bash
.agents/skills/kis/scripts/install-commands.sh --host opencode
```

## Update

```bash
curl -fsSL https://raw.githubusercontent.com/smkamranqadri/kis-skill/main/bootstrap.sh \
  | bash -s -- check --repo https://github.com/smkamranqadri/kis-skill.git
```

Swap `check` for `update` to apply it. The updater compares `metadata.version`, validates before and after copying, and restores the previous install if validation fails.

## Use

Ask for the skill, or run a command:

```text
Use kis. Recover this project and tell me the current task, blocker, proof, and next action.
```

| Step | Claude | Pi and OpenCode | Codex |
| --- | --- | --- | --- |
| Recover context | `/kis:start` | `/kis-start` | `/prompts:kis-start` |
| Interview and scope | `/kis:plan` | `/kis-plan` | `/prompts:kis-plan` |
| Execute with proof | `/kis:act` | `/kis-act` | `/prompts:kis-act` |
| Write back to memory | `/kis:sync` | `/kis-sync` | `/prompts:kis-sync` |
| Audit memory | `/kis:check` | `/kis-check` | `/prompts:kis-check` |
| Bootstrap `kis/` | `/kis:init` | `/kis-init` | `/prompts:kis-init` |

`/kis:init` also writes `kis/intent/compass.md`, where the product is going, beside `kis/knowledge/project.md`, what it is today. `/kis:plan` reads both. In a project set up before the compass existed, `/kis:init` adds just the compass.

Antigravity supports rules, skills, plugins, hooks, and MCP, but not custom slash commands. Ask for the skill and name the step, or point it at `.agents/skills/kis/commands/sync.md` directly.

In Claude you get two entries with the same name, and both are meant to be there. `/kis` is the skill: the whole loop, and what Claude reaches for on its own. `/kis:start` and its siblings are the per-step commands.

Memory lives in the consuming project under `kis/knowledge/`, `kis/intent/`, and `kis/state/`.

## Anti-Drift

Commands only help when you remember to type one. The re-anchor layer covers the rest: a Claude `SessionStart` hook that prints current State into context on startup, resume, clear, and compact, an Antigravity `PreInvocation` hook that injects the same text at the first model call of every turn, a Codex `SessionStart` hook in `.codex/hooks.json`, a Command Code `SessionStart` hook in `.commandcode/settings.json`, and a marked KIS block in `AGENTS.md` and `CLAUDE.md` for Pi and OpenCode, which have no hook equivalent.

Codex skips a new hook until you review it: after installing, open Codex in the project and run `/hooks` once to trust the KIS hook (project hooks also need the project's `.codex/` layer trusted). Command Code needs no such step. Limits: Command Code cannot signal a compaction, so a compaction is not re-anchored there (it re-anchors on startup, resume, and clear). Command Code print mode (`cmd -p`) runs no SessionStart hooks, and a prompt passed at launch is answered before the hook context lands, so the anchor reaches the model from the second turn. Antigravity re-anchors every turn, so a compaction is covered. Codex re-anchors on compact too.

```bash
.agents/skills/kis/scripts/install-anchor.sh --check
.agents/skills/kis/scripts/install-anchor.sh --remove
```

## Development

See [AGENTS.md](AGENTS.md).
