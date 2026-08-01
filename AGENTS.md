# Agent Instructions

This repository is the **source** of the KIS skill. Nothing here is a live install: the package sits outside every host's auto-discovery path, so working in this repo does not load KIS as an active skill. To use KIS, install it into a real project.

## Layout

```text
skills/kis/     the package, and the only thing that ships
tests/          authoring tests, never installed
evals/          authoring evals, never installed
scripts/        install-skill.sh, run from a source clone only
bootstrap.sh    one-command install, check, and update entry point
```

Installing copies `skills/kis/` verbatim to `<target>/.agents/skills/kis`. If a file does not belong in someone else's project, it does not belong in `skills/kis/`.

`ACTIVE_VERSION` and `metadata.version` in `SKILL.md` must match. Release tags are that version prefixed with `v`.

## Rules

- Keep `SKILL.md` short. It is loaded into an agent's context on every use, so detail belongs in `references/`.
- `SKILL.md` is instructions to the agent at work time. It must not document the package, the installers, or this repository. That is what this file and `README.md` are for.
- Keep command bodies in `skills/kis/commands/` host-neutral. Host wiring lives only in `skills/kis/scripts/install-commands.sh`.
- Do not restate the same rule in `SKILL.md` and a reference. One owner per fact, the same rule KIS itself enforces.
- Commands are the exception and restate on purpose: a command body is loaded on its own, without `SKILL.md` in context, so it has to stand alone. `SKILL.md` stays authoritative. When a command and `SKILL.md` disagree, `SKILL.md` is right and the command is the bug. Restate a rule, not its examples, and never let a command introduce a rule that nothing in `SKILL.md` or `references/` owns.

## Checks

Run after any change:

```bash
skills/kis/scripts/validate-skill.sh skills/kis
tests/test-bootstrap.sh
tests/test-install-skill.sh
tests/test-update-installed-skill.sh
tests/test-install-commands.sh
tests/test-install-anchor.sh
```

The validator uses the official `skills-ref` path when `uv` is installed and falls back to Ruby structural validation otherwise. It requires the package directory to be named `kis`.

`evals/evals.json` holds output-quality prompts and `evals/trigger-queries.json` holds description-trigger prompts.
