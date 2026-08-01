# Specialist Routing

Use specialists when they reduce risk, improve quality, or provide a focused expert lens. Do not use them for tiny obvious work.

Specialists do not own project memory. They must not edit `kis/`. They may report KIS-relevant updates for the orchestrator to classify and write.

## Availability Rule

If a matched specialist skill or subagent tool is unavailable:

1. Say what is unavailable.
2. If installation or enablement is supported and the work is Standard/Phase risk, ask for approval or use the available install flow.
3. If unavailable tooling blocks the ideal path, create a checkpoint.
4. Continue only when the user enables the tool, reduces scope, switches to Fast Mode, or explicitly accepts fallback risk.

Do not silently pretend an unavailable specialist ran. Do not deadlock when a safe fallback is accepted.

## Common Routing

```text
Which skill fits?              -> inspect available skills, then use the best match
Idea unclear / need thinking?  -> brainstorming or request focused user input
Requirements need structure?   -> brainstorming, writing-plans, or a PRD skill if installed
Break plan into issues?        -> writing-plans or an issue-planning skill if installed
Domain/terminology unclear?    -> domain-modeling/grilling skill if installed; otherwise inspect docs and ask focused questions
Architecture risky?            -> architecture/system-design skill if installed; otherwise write and challenge the design explicitly
Architecture diagram?          -> Figma/FigJam diagram skill or Mermaid, depending on the requested output
Deep module design?            -> codebase-design/system-design skill if installed
Implement feature or bugfix?   -> test-driven-development when behavior changes
End-to-end / browser test?     -> browser or playwright skill/tooling when available
Hard bug or regression?        -> systematic-debugging
Triage incoming issues?        -> triage skill if installed; otherwise classify by impact, evidence, and next action
Explore a design fast?         -> prototype skill if installed; otherwise use Fast Mode with clear fallback risk
Web UI/design?                 -> frontend/design skill or the host app's frontend guidance
React/Next.js implementation?  -> framework-specific skill if installed; otherwise follow repo patterns
Auth / login / accounts?       -> auth-specific skill if installed; otherwise map security and session risks first
API design?                    -> system-design/API skill if installed; otherwise define contracts and failure modes
Mobile design?                 -> mobile/UI skill if installed; otherwise verify responsive behavior directly
UI review?                     -> UI/design review skill plus live browser or screenshot verification
Code review?                   -> code-review workflow or requesting-code-review skill
Security review?               -> security scan/review skill or tool
Hand off to another session?   -> thread/handoff tool if available
```

Use the skill names exposed in the current environment, whichever host you are running in. Discover what is installed through the session's own skill, agent, command, and tool surfaces rather than assuming a fixed set. If a routing example names a capability but the exact skill is unavailable, search installed skills and tools first, then use the host's install flow when supported.

Skip a matched skill only with a one-line reason.

## Agent Selection

Use one specialist when:

- task is small
- risk is low
- changes are localized
- orchestrator can review directly

Use implementer + reviewer when:

- code changes are non-trivial
- visible UI changes
- user behavior changes
- architecture/data flow changes
- regression risk exists

Use multiple agents when:

- feature spans frontend and backend
- mobile and web both change
- architecture is uncertain
- plan needs challenge before execution
- independent review would catch meaningful risk

## Dispatch Brief

Before launching a specialist, prepare:

```text
Role:
Skill:
Task:
Relevant KIS context:
Relevant files:
Constraints:
Acceptance criteria:
Commands to run:
Expected proof:
KIS boundary:
```

Required KIS boundary:

```text
Do not modify kis/.

Report any KIS-relevant updates under this heading:

KIS-relevant updates:
- Knowledge:
- Intent:
- State:

Only the KIS orchestrator updates KIS.
```

## Report Handling

Treat specialist reports as claims. Verify:

- changed files actually changed
- commands were actually run where possible
- test output is credible
- implementation matches the task
- no unrelated changes were made
- `kis/` was not modified by the specialist
- KIS updates are routed to the right layer

Preferred report:

```text
Summary:
- ...

Changed files:
- ...

Commands run:
- ...

Proof:
- ...

Issues / risks:
- ...

KIS-relevant updates:
- Knowledge:
- Intent:
- State:
```

If no KIS update is needed:

```text
KIS-relevant updates:
- none
```

## Install Notes

When the environment supports skill installation, prefer the host's supported install mechanism over raw shell commands, unless the user explicitly asks for a shell-based installer.

Useful companion capability categories:

- brainstorming or grilling
- PRD and issue planning
- test-driven development
- systematic debugging
- browser or Playwright verification
- frontend/UI review
- code review
- security review
- architecture/system design
- handoff or thread coordination

Before installing, confirm the exact skill/plugin exists and that the install target matches the current environment. If install support is unavailable, checkpoint and ask whether to reduce scope, switch to Fast Mode, or proceed with accepted fallback risk.
