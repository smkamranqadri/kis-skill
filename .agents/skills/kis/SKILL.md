---
name: kis
description: Operate the KIS (Knowledge/Intent/State) project memory system under `kis/`. Use at the start of project work, before planning or implementation, when resuming context, when creating or updating project memory, when synchronizing decisions/status/proof, or when choosing between Fast, Standard, and Phase work modes. Load the smallest relevant KIS context, classify facts into Knowledge, Intent, or State, challenge weak assumptions, plan only as much as needed, act with proof, and keep KIS synchronized.
metadata:
  version: "0.6.4"
  source: "archive/kis-v0.5.0-todo-kis-system-4"
  compatibility: "Codex and Claude"
---

# KIS Agent Skill

## Host Compatibility

Use this skill in Codex or Claude. Keep the KIS workflow the same across hosts, and adapt only the mechanics for the current environment:

- In Codex, use available skills, MCP tools, thread tools, plugin install flows, and repository commands exposed in the session.
- In Claude, use available Skills, agents, hooks, slash commands, and repository commands exposed in the session.
- If a named tool, skill, agent, or command is unavailable, do not pretend it ran. Use the availability checkpoint in [specialist-routing.md](references/specialist-routing.md).

## Quality Assets

- Run the repository root `bootstrap.sh` for one-command GitHub install, check, or update flows.
- Run `scripts/validate-skill.sh` from the skill root to validate this package against the official Agent Skills reference validator.
- Run `scripts/install-skill.sh --source <path> --target <project-root>` for first install into a project.
- Run `scripts/update-installed-skill.sh --source <path> --check` to compare an installed package with a source package, and add `--apply` to update after validation.
- Run `scripts/test-bootstrap.sh` after changing the root bootstrap flow.
- Run `scripts/test-install-skill.sh` after changing install behavior.
- Run `scripts/test-update-installed-skill.sh` after changing update behavior.
- Use `evals/evals.json` for output-quality evaluation prompts.
- Use `evals/trigger-queries.json` for description-trigger evaluation prompts.

## Purpose

Use KIS as the project's operational memory and recovery system.

KIS means:

- Knowledge: stable facts and rules
- Intent: goals, plans, requirements, accepted direction
- State: current operational reality

Keep KIS concise and synchronized so a fresh agent can recover:

- what the project is
- why it exists
- what the user wants
- what has been decided
- what is happening now
- what is done, blocked, and next

Do not create documentation for its own sake. KIS is a working memory system, not a docs pile.

## Structure

Only create this structure unless the user asks otherwise:

```text
kis/
  knowledge/
  intent/
  state/
```

If `kis/` does not exist, use the bootstrap flow in [bootstrap.md](references/bootstrap.md).

## Core Rules

- Load State first, then relevant Intent, then only the Knowledge needed.
- Choose the smallest useful work mode.
- Ask only questions that change direction, scope, risk, acceptance, business meaning, or irreversible decisions.
- Challenge weak requirements, risky assumptions, unnecessary complexity, and plans that do not match the user's goal.
- Put each fact in exactly one KIS layer.
- Prefer updating existing KIS files over creating new files.
- Keep State operational and resumable.
- Prove work before marking it done.
- Synchronize only what changed.

## Truth Hierarchy

Trust information in this order:

```text
State
Intent
Knowledge
Conversation
Repository inspection
```

Operational reality overrides stale plans. If files contradict, update the single source of truth instead of duplicating the fact.

## Memory Layers

### Knowledge

Store stable facts:

- project overview
- stack and architecture
- domain terms
- constraints
- coding standards
- user preferences
- durable decisions

### Intent

Store direction:

- vision and goals
- PRDs
- feature plans
- acceptance criteria
- app flows
- design direction
- implementation plans

### State

Store current reality:

- active branch
- current task
- current blocker
- run/test/build commands
- status
- proof
- next action

State should answer, near the top:

```text
What branch?
What task?
What command?
What blocker?
What's next?
```

Keep State lean. Move stable information into Knowledge and plans into Intent.

## Work Modes

Choose one mode before starting.

### Fast Mode

Use for tiny, low-risk work:

- quick lookup
- small copy/config change
- obvious bug fix
- localized refactor

Process:

1. Load State if it exists.
2. Inspect only relevant files.
3. Act directly.
4. Run the smallest useful verification.
5. Update State only if operational reality changed.

### Standard Mode

Use for normal project work:

- multi-file changes
- normal feature work
- unclear product changes
- decisions that may affect future work
- work that changes KIS

Follow the KIS loop below. Use specialist agents when available and they reduce real risk, but do not block forever if tooling is unavailable; create a checkpoint and ask whether to enable tools, reduce scope, use Fast Mode, or proceed with accepted fallback risk.

### Phase Mode

Use for large or risky work:

- multi-session implementation
- major refactor
- architecture change
- UI flow redesign
- migration
- production deployment work

Create or refine Intent, split work into phases, verify each phase, synchronize KIS, and run review before shipping. Read [execution.md](references/execution.md) for detailed phase execution.

## Operating Loop

Use this loop for Standard and Phase work:

```text
LOAD -> QUESTION -> CHALLENGE -> STRUCTURE -> PLAN -> ACT -> SYNCHRONIZE
```

Each step may or may not require a specialist agent. If a specialist is unavailable, create a checkpoint and ask whether to install skills, reduce scope, use Fast Mode, or proceed with accepted fallback risk.

### LOAD

1. Read `kis/state/*` first.
2. Read relevant `kis/intent/*`.
3. Read only required `kis/knowledge/*`.
4. Inspect the repo only where needed.

If there is no KIS yet, read [bootstrap.md](references/bootstrap.md).

### QUESTION

Ask one focused question only when blocked or when the answer changes scope, direction, risk, acceptance criteria, business meaning, or a hard-to-reverse decision.

Do not ask questions that can be answered by reading KIS, inspecting files, running commands, or making a safe reversible assumption.

### CHALLENGE

Challenge vague ideas, weak requirements, risky assumptions, missing edge cases, scope creep, and unnecessarily heavy approaches. Explain the practical tradeoff and offer a clearer path.

When replicating an existing product, screen, workflow, or artifact, study the reference before choosing an architecture.

### STRUCTURE

Classify new information:

```text
Knowledge = what is true / how things work
Intent    = what we want / plan to do
State     = what is happening now
```

Do not put the same fact in multiple places.

### PLAN

Plan only enough to execute safely:

- scope
- acceptance checks
- risk
- files likely involved
- verification method
- specialist/review need

For specialist routing, read [specialist-routing.md](references/specialist-routing.md).

### ACT

Before implementation, update State when useful:

- current task
- work mode
- status
- blocker
- verification plan

Then implement only the current scope, avoid unrelated changes, and keep changes reviewable.

For written plans and Phase Mode, read [execution.md](references/execution.md).

### SYNCHRONIZE

After work, ask:

- Did Knowledge change?
- Did Intent change?
- Did State change?

Update only changed KIS files. Record proof in State when it helps recovery. Do not paste long implementation history into KIS.

## Proof Before Done

Never mark a task done based only on intuition, code inspection, or an agent report.

Proof can be:

- test/build/lint/typecheck output
- manual verification result
- screenshot for visible UI
- browser/device preview
- deployment check
- diff review
- reproduction no longer failing

Use this shape in State when useful:

```text
Proof:
- npm test - passed
- npm run build - passed
- Manual check: login flow works
```

## Maintenance

Run a KIS cleanup when:

- State grows past roughly 80 lines
- any KIS file becomes hard to skim
- plans pile up
- the project pivots
- stale information causes confusion

Actions:

- dedupe repeated facts
- relocate stable facts from State to Knowledge
- move goals/plans from State to Intent
- mark superseded plans clearly
- prune obsolete blockers, stale notes, and old ledgers

Healthy KIS trends small.

## Writing Style

Prefer concise operational bullets:

```text
Done
- Added retry logic
- Fixed lesson unlock bug

Pending
- Mobile validation
- Accessibility review
```

Avoid essays. Use headings that make scanning easy.

## References

- [bootstrap.md](references/bootstrap.md): initialize KIS for a new or existing project.
- [specialist-routing.md](references/specialist-routing.md): choose specialist skills and agents.
- [execution.md](references/execution.md): execute written plans and Phase Mode work.
- [file-hygiene.md](references/file-hygiene.md): organize, clean, and evolve KIS files.
