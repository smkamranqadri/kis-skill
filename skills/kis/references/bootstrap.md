# KIS Bootstrap

Use this when `kis/` does not exist or when joining an existing project whose KIS foundation is incomplete.

## New Project

1. Interview the user until the foundation is clear: what is being built, who it is for and the problem, constraints, and project stage, then the direction: why it should exist, the vision, the North Star, principles, what not to build, and POC versus MVP. One question at a time, each with your recommended answer, waiting for the answer before the next.
2. Challenge assumptions before creating long-lived project memory.
3. Create only the useful parts of:

```text
kis/
  knowledge/
  intent/
  state/
```

4. Write the smallest useful Knowledge, Intent, and State files: what the product is today in `knowledge/project.md`, where it is going in `intent/compass.md` (see Compass).
5. Ask the user to approve the next work mode and first phase before non-trivial implementation.

Do not create empty files.

## First Response Shape

When starting a brand new project, open the interview instead of dumping a questionnaire:

```text
I'll initialize KIS for this project.

First question: what are we building?

My read from what you've said so far: <recommendation>.
```

Then walk the rest one at a time, in dependency order: who it is for and the problem, hard constraints, and whether this is a prototype, MVP, or production system, then the direction questions. Skip anything the user already answered or the repository already shows. Stop asking as soon as the foundation is decidable, and continue to the work-mode checkpoint.

## Compass

`kis/knowledge/project.md` says what the product is today; `kis/intent/compass.md` says where it is going. The vision stays stable while features, technology, and experiments change, so keep those out of the compass.

```text
# Compass: <product>

## Why
## Who and problem
## Vision
## North Star
## Principles
## Not building
## POC vs MVP
### POC (testing)
### MVP (committed)
```

- Never invent metrics, targets, or a North Star. Without one the user can name, write `none yet`.
- Mark a belief that is not yet proven as a hypothesis.
- Leave out a section nothing is known about.

## Existing Project

When joining a project with KIS already present:

```text
I'll recover the project from KIS first.

I'll read State, then relevant Intent and Knowledge, inspect the repo only where needed, and continue from the current resume pointer.
```

Then:

1. Read State.
2. Read relevant Intent.
3. Load only necessary Knowledge.
4. Inspect the repository only where required.
5. Summarize current understanding briefly.
6. Ask questions only if blocked.
7. Continue from the resume pointer.

Do not ask the user to re-explain information KIS should already contain.

## Suggested Files

Create only when useful:

```text
kis/
  knowledge/
    project.md
    technical.md
    rules.md
  intent/
    PRD.md
    compass.md
    ImplementationPlan.md
  state/
    current.md
```

Small projects should remain small.

## Classic Document Mapping

For medium or large projects:

```text
PRD                 -> intent/
Product direction   -> intent/compass.md
Tech spec           -> knowledge/
App flow            -> intent/
Design direction    -> intent/
Schema              -> knowledge/
Implementation plan -> intent/
Tracker             -> state/
Rules               -> knowledge/
```

Do not create these automatically. Create them only when they reduce confusion or improve recovery.
