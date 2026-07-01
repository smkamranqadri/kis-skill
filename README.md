# KIS Skill

KIS is an Agent Skill for project memory and execution discipline.

KIS means:

- **Knowledge**: stable facts, constraints, architecture, rules, and durable decisions
- **Intent**: goals, PRDs, plans, acceptance criteria, and approved direction
- **State**: current task, blocker, proof, commands, branch, and next action

The skill helps Codex and Claude recover project context, choose a work mode, challenge weak assumptions, execute with proof, and keep project memory synchronized.

## Install

From the project where you want to use KIS:

```bash
curl -fsSL https://raw.githubusercontent.com/smkamranqadri/kis-skill/main/bootstrap.sh \
  | bash -s -- install --repo https://github.com/smkamranqadri/kis-skill.git
```

This installs:

```text
.agents/skills/kis/
.claude/skills/kis -> ../../.agents/skills/kis
```

Use `--force` if the project already has an installed copy:

```bash
curl -fsSL https://raw.githubusercontent.com/smkamranqadri/kis-skill/main/bootstrap.sh \
  | bash -s -- install --repo https://github.com/smkamranqadri/kis-skill.git --force
```

Skip the Claude compatibility link:

```bash
curl -fsSL https://raw.githubusercontent.com/smkamranqadri/kis-skill/main/bootstrap.sh \
  | bash -s -- install --repo https://github.com/smkamranqadri/kis-skill.git --no-claude-link
```

## Pin A Version

Install from a specific tag:

```bash
curl -fsSL https://raw.githubusercontent.com/smkamranqadri/kis-skill/v0.6.4/bootstrap.sh \
  | bash -s -- install \
    --repo https://github.com/smkamranqadri/kis-skill.git \
    --ref v0.6.4
```

## Check For Updates

From a project with KIS installed:

```bash
curl -fsSL https://raw.githubusercontent.com/smkamranqadri/kis-skill/main/bootstrap.sh \
  | bash -s -- check --repo https://github.com/smkamranqadri/kis-skill.git
```

## Apply Updates

From a project with KIS installed:

```bash
curl -fsSL https://raw.githubusercontent.com/smkamranqadri/kis-skill/main/bootstrap.sh \
  | bash -s -- update --repo https://github.com/smkamranqadri/kis-skill.git
```

The updater compares the installed `metadata.version` in `SKILL.md` against the source package. It validates before copying, backs up the current install during update, and validates again after copying.

## Validate

Validate the installed skill:

```bash
.agents/skills/kis/scripts/validate-skill.sh .agents/skills/kis
.agents/skills/kis/scripts/validate-skill.sh .claude/skills/kis
```

The validator uses the official `skills-ref` path when `uv` is installed and falls back to Ruby structural validation otherwise.

## Use

In Codex or Claude, ask:

```text
Use $kis. Recover this project from KIS and tell me the current task, blocker, proof, and next action.
```

For a new project:

```text
Use $kis. Initialize the smallest useful KIS memory for this project and stop before implementation.
```

KIS stores project memory under the consuming project's `kis/` directory:

```text
kis/
  knowledge/
  intent/
  state/
```

The skill package itself lives under `.agents/skills/kis/`.

## Development

Run checks from this repository:

```bash
.agents/skills/kis/scripts/test-bootstrap.sh
.agents/skills/kis/scripts/test-install-skill.sh
.agents/skills/kis/scripts/test-update-installed-skill.sh
.agents/skills/kis/scripts/validate-skill.sh .agents/skills/kis
.agents/skills/kis/scripts/validate-skill.sh .claude/skills/kis
```

Current version is tracked in:

- `ACTIVE_VERSION`
- `.agents/skills/kis/SKILL.md` frontmatter under `metadata.version`

Release tags should match the active version, for example `v0.6.4`.
