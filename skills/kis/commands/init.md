---
description: Bootstrap the smallest useful KIS memory for this project and stop before implementation.
argument-hint: [optional project description]
---

# KIS Init

Run the KIS bootstrap flow. Stop before implementation.

Read `.agents/skills/kis/references/bootstrap.md` and follow it.

## Steps

1. Check whether `kis/` already exists.
   - If it exists and is healthy, stop and tell the user to run the start command instead.
   - If it exists but is incomplete, repair only the missing parts. A missing `kis/intent/compass.md` counts as incomplete.
2. Decide whether this is a new project or an existing codebase.
   - New project: interview the user through what, who and the problem, constraints, and stage, then the direction: why it should exist, the vision, the North Star, principles, what not to build, and POC versus MVP. One question at a time, each with your recommended answer. Skip anything `$ARGUMENTS` or the repository already answers.
   - Existing codebase: inspect the repository, derive what you can, and interview only on what inspection cannot answer.
3. Challenge weak or contradictory answers before writing long-lived memory.
4. Create only the useful parts of:

```text
kis/
  knowledge/
  intent/
  state/
```

5. Write the smallest useful files. Do not create empty files or placeholder templates.
6. Put each fact in exactly one layer. What the product is today goes to `kis/knowledge/project.md`; where it is going goes to `kis/intent/compass.md`, in the shape `bootstrap.md` (Compass) gives.

## Report

List the files created, one line each, with what each one owns. Then propose the first work mode and first task, and wait for approval.
