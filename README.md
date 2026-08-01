# KIS Skill

KIS is an Agent Skill for project memory and execution discipline. It works in Claude, Pi, and Codex.

- **Knowledge**: stable facts, architecture, constraints, rules, durable decisions
- **Intent**: goals, PRDs, plans, acceptance criteria, approved direction
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
.agents/skills/kis/        the skill package, discovered by Pi and Codex
.claude/skills/kis         link for Claude
.claude/commands/kis       link for Claude commands
.pi/prompts/kis-*.md       links for Pi prompts
.claude/settings.json      SessionStart hook that re-injects current State
AGENTS.md                  KIS block between <!-- kis:anchor:start|end --> markers
```

Useful flags: `--force` to replace an existing install, `--no-commands` or `--no-anchor` to skip a layer, `--ref v0.9.0` to pin a version.

This repository holds the source package under `skills/kis/`; nothing here is a live install. The installer copies it to `.agents/skills/kis` in your project, which is where every host looks.

Codex prompts are user-level and are not installed by default:

```bash
.agents/skills/kis/scripts/install-commands.sh --host codex
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

| Step | Claude | Pi | Codex |
| --- | --- | --- | --- |
| Recover context | `/kis:start` | `/kis-start` | `/prompts:kis-start` |
| Interview and scope | `/kis:plan` | `/kis-plan` | `/prompts:kis-plan` |
| Execute with proof | `/kis:act` | `/kis-act` | `/prompts:kis-act` |
| Write back to memory | `/kis:sync` | `/kis-sync` | `/prompts:kis-sync` |
| Audit memory | `/kis:check` | `/kis-check` | `/prompts:kis-check` |
| Bootstrap `kis/` | `/kis:init` | `/kis-init` | `/prompts:kis-init` |

Memory lives in the consuming project under `kis/knowledge/`, `kis/intent/`, and `kis/state/`.

## Anti-Drift

Commands only help when you remember to type one. The re-anchor layer covers the rest: a Claude `SessionStart` hook that prints current State into context on startup, resume, clear, and compact, and a marked KIS block in `AGENTS.md` and `CLAUDE.md` for Pi and Codex, which have no hook equivalent.

```bash
.agents/skills/kis/scripts/install-anchor.sh --check
.agents/skills/kis/scripts/install-anchor.sh --remove
```

## Development

See [AGENTS.md](AGENTS.md).
