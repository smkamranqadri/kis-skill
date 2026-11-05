---
description: Clarify product direction through an interview, then write or revise the Product Compass in kis/intent/compass.md.
argument-hint: [product idea or direction question]
---

# KIS Compass

Run the QUESTION, CHALLENGE, and STRUCTURE steps of the KIS loop for product direction on `$ARGUMENTS`, then write `kis/intent/compass.md` after the user confirms. Do not implement anything in this command.

Full instructions: `.agents/skills/kis/SKILL.md`. The compass rules, sections, evidence tags, and file shape: `.agents/skills/kis/references/product-compass.md`. Read it before the interview.

## Steps

1. If `kis/` does not exist, say so and ask whether to run the init command first (recommended) or write the compass alone, creating only `kis/intent/compass.md` and the Knowledge file its outside facts need.
2. Load: `kis/state/*` first, then `kis/intent/compass.md` if it exists, then other relevant `kis/intent/*`, then only the `kis/knowledge/*` you need. Note any direction Knowledge holds (who the product is for, where it is going, a product choice): it belongs in the compass.
3. Inspect existing product documentation before asking anything: README, PRD, docs, landing copy, pitch notes, anything the user points at. Whatever they answer is not asked again.
4. Pick the path. No compass: build one. Compass exists: ask what changed or what is being questioned, keep every unaffected decision, and interview only on the affected sections.
5. Interview the user. One consequential question at a time, waiting for each answer. Follow the order of the sections in the reference, since each one depends on the ones before it. Give your recommended answer and the tradeoff with every question. Stop as soon as the direction is decidable; do not walk every section for a small product.
6. Challenge vague intent, a vision that is really a feature or a technology, a promise nobody asked for, untested assumptions presented as facts, and anything that belongs in the PRD or plan instead. Offer a clearer framing.
7. Keep facts, hypotheses, experiments, and confirmed decisions apart, using the evidence tags. Invent no metrics, thresholds, sample sizes, research, quotes, or market evidence; unknowns become hypotheses with a way to learn them under Discovery, stated without numbers the user did not give. A fact about the outside world (a related product, a provider's rule) belongs in Knowledge with its source and the date it was read; the compass links to it and never holds it alone.
8. Separate the POC from the MVP: what is being tested, what is temporary, and what is committed.
9. Present the proposed compass: concise, tagged, ready to review. Name any stable section it changes, and list the Knowledge lines it adds or moves. Ask the user to confirm, edit, or reject it. A request to skip the interview or to write directly shortens the interview; it is not confirmation of a compass the user has not seen.

## Write

Only after explicit confirmation, create or update `kis/intent/compass.md` in the shape the reference defines. Preserve earlier decisions unless the user explicitly revised them, and log each revision in `## Revisions`. Then write the Knowledge lines the proposal listed: outside facts added, each linked from the compass, and direction moved out of Knowledge with a one-line pointer to the compass left in its place. Write nothing else: no edits to the PRD, plan, or State.

## Report

```text
Written: kis/intent/compass.md (created | revised)
Knowledge lines added or moved:
Decisions confirmed:
Hypotheses still open:
POC vs MVP:
Contradictions found elsewhere in KIS:
```

## Stop Condition

Stop after the compass is written. Suggest the plan command as the next step and wait. If the user does not confirm, write nothing.
