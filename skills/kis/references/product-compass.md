# Product Compass

Use this for product-direction work: why the product should exist, who it serves, the future experience it creates, where to focus, what not to build, and what a POC should test versus what an MVP commits to. It applies to any product, not only software.

The compass lives at `kis/intent/compass.md`. It keeps direction steady while features, technology, and experiments change. It informs planning and replaces nothing.

## Stable And Changeable

```text
Stable (change only by explicit revision)   Intent, Audience and Problem, Vision, Core Promise, Principles, Boundaries
Changeable (expected to move)               Strategy, Success Signals, Discovery, POC and MVP
```

The vision stays relatively stable. Features, technology, implementation, and experiments can change without touching it. A POC may contain temporary functionality that never becomes part of the MVP.

## Sections

| Section | Question it answers |
| --- | --- |
| Intent | Why should this product exist? |
| Audience and Problem | Who are we serving, and what problem matters to them? |
| Vision | What future experience are we creating? |
| Core Promise | What meaningful value should the product deliver? |
| Strategy | Where will we focus, and how will we differentiate? |
| Principles | What rules guide decisions? |
| Boundaries | What are we deliberately not building? |
| Success Signals | What would show customers get value? |
| Discovery | Which assumptions still need validating, and how? |
| POC and MVP | What are we experimenting with, and what are we committing to deliver? |

Success Signals may name a candidate North Star Metric only when the user can name the repeatable moment of customer value and a way to observe it. Otherwise write `North Star: none yet` or leave it out. Never propose targets, baselines, thresholds, or sample sizes the user did not give.

POC and MVP stay separate. POC lists the hypotheses under test and the temporary things built to test them, each with the condition the user set for keeping or dropping it. MVP lists the commitments to deliver, stated as outcomes for the audience, not as features or technology. Anything in the POC that the user has not committed to is not an MVP requirement.

## Evidence Tags

Every bullet carries exactly one tag, except the `North Star: none yet` line:

```text
[fact]        known and sourced; name the source (a file, a person's statement, a measurement)
[hypothesis]  believed, not yet validated
[experiment]  a test of a hypothesis, with what would confirm or refute it
[decision]    confirmed by the user
```

Do not invent metrics, research, user quotes, market sizes, competitors, or evidence. What is not known is a `[hypothesis]`, and the way to learn it goes under Discovery. Only the user's confirmation makes a `[decision]`. Recommendations and drafts you propose are not decisions until confirmed.

A choice is a `[decision]` once confirmed: the vision, promise, principles, boundaries, strategy, and the POC and MVP split. A belief about the world (what the audience needs, how people will behave, that the value is real) stays a `[hypothesis]` until evidence supports it, however firmly the user holds it. Confirming the compass confirms its choices, not its beliefs.

## Ownership

Write each fact once, in the layer that owns it.

```text
Compass                  direction and the reasoning behind it
PRD / requirements       feature behavior, acceptance criteria, scope of a release
Plan                     tasks, order, verification
State                    which stage the project is in now, current task, blocker, next
Knowledge                what is built, stack, architecture, domain terms, constraints, outside facts
```

Point to the owner instead of copying. If a PRD or README already states the audience, link to it and record only what the compass adds or disputes.

Outside facts the interview turns up belong to Knowledge (`SKILL.md`, STRUCTURE). Write each with its source and the date it was read, and link it from the compass bullet: `[fact] ... (kis/knowledge/<file>.md, <section>)`. When Knowledge already holds direction (who the product is for, where it is going, a product choice), move it into the compass and leave a one-line pointer in Knowledge.

## Writing

- Write only after the user confirms the proposed compass. Show the proposal first, concise enough to review in one read. A request to skip the interview, or to write the file directly, shortens the interview; it does not confirm a compass the user has not seen. Propose with recommended answers tagged `[hypothesis]`, and wait.
- Create or update `kis/intent/compass.md`. The only other writes are the Knowledge lines Ownership names: outside facts added, and direction moved out with a pointer left. List them in the proposal; they are confirmed with it. Prefer an existing Knowledge file. Do not edit the PRD, plan, or State from the compass step.
- Keep it short: one to three bullets per section, plain language, and omit a section nothing is known about rather than filling it with placeholders.
- Preserve existing decisions. Change a `[decision]` only when the user explicitly revises it, and record the change under `## Revisions` as one line: date, what changed, why. Do not rewrite or reorder untouched sections.
- When a stable section would change, say so and get explicit confirmation for that change separately from changes to changeable sections.
- Stop after writing. Do not start implementing.

## File Shape

```text
# Product Compass: <product name>

## Intent
- [decision] ...

## Audience and Problem
## Vision
## Core Promise
## Strategy
## Principles
## Boundaries
## Success Signals
## Discovery
## POC and MVP
### POC
### MVP

## Revisions
- <YYYY-MM-DD> <section>: <what changed> - <why>
```

Add `## Revisions` with the first revision, not before.

## Planning Use

When a plan touches product direction, scope, priorities, or the POC-to-MVP line, read the compass first. Use it to check scope against Boundaries and Principles, to place work as POC or MVP, and to flag work that contradicts a `[decision]`. A conflict is raised with the user. The plan does not quietly override the compass, and does not edit it: a deliberate change of direction is a compass revision.

## When Direction Becomes Reality

Sync records what the compass led to without editing the compass:

- Built reality goes to Knowledge, for example a new server that now answers requests, in the technical notes. The compass keeps the `[decision]` as the reason and does not restate what was built.
- An experiment's result goes to State, with a prompt to revise the compass through the compass command. Turning a result into a `[fact]` or changing a `[decision]` is a compass revision.
