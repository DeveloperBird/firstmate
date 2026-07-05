---
name: grill-with-claude
description: A relentless interview to sharpen a plan or design, rendered as a shareable claude.ai Artifact overview with answers collected through structured question prompts. All questions are shown at once on the artifact; each is answered via a recommended-first multiple-choice prompt with room for a custom answer.
user-invocable: true
---

# Grill With Claude

A relentless interview to sharpen a plan or design. The full interview is published as a claude.ai Artifact so it can be read end-to-end or shared, and answers are collected through structured question prompts, one small batch at a time. Output is a ticket file with a goal and acceptance criteria.

## Step 1 — Orient

If the user has not already stated a plan or design to stress-test, ask for it in one line before proceeding. Also confirm which project this work is for (needed for the backlog entry) — if it's unambiguous from context, state it and proceed without asking.

## Step 2 — Generate all questions

Take the perspective of the developer who will actually implement this — not an interviewer sampling a few interesting angles, but the person who has to write the code and cannot ask anyone anything once the ticket is handed off. Ask every question whose answer would otherwise force that developer to guess.

Apply `/grilling` discipline, with no fixed target count — ask as many questions as it takes to close every gap, not a token 6–8:
- Walk the design tree from the most foundational decision outward
- Resolve dependencies in order (don't ask about caching strategy before the data model is settled)
- For each decision point, ask: "if I sat down to write this right now, what would I have to invent or assume?" Every assumption becomes a question — data shapes, error/edge-case behavior, boundaries and limits, naming, integration points, what's explicitly out of scope
- Don't stop at the first pass over the design tree — an answer often exposes a new sub-decision underneath it (e.g. "yes, paginate" implies a page-size default and a cursor-vs-offset choice). Keep drilling into each branch until answers bottom out in concrete, implementable detail with nothing left to infer
- For each question, produce exactly 3 suggested answers (concrete, meaningfully distinct options), with your recommended one first
- Stop only when you can picture writing the ticket's acceptance criteria without inventing a single behavior

Hold all questions in memory — they feed both the artifact (Step 3) and the question prompts (Step 4). Don't self-censor the count to keep the artifact short; a thin interview that leaves room for guessing has failed the point of this skill.

## Step 3 — Publish the overview artifact

Load the `artifact-design` skill, then write the full interview as a single HTML file (scratchpad directory) and publish it with the `Artifact` tool. This is a read-only overview — it gives the user something to skim or share, it does not collect answers itself.

Content: one card per question, in question order —
- The question text as the card header
- The 3 suggested answers as a plain list, with the recommended one visually marked (e.g. a small "recommended" tag) — not a form, no inputs, no submit button
- Leave a visible "answered" placeholder area empty for now; Step 4 does not edit this artifact after the fact, so don't build interactivity expecting a later update

Give it a distinct favicon (e.g. 🔥) and a title naming the plan being grilled. Tell the user in one line that the interview overview is published, then move straight to Step 4 — don't wait for a reaction to the artifact.

## Step 4 — Collect answers

Use the `AskUserQuestion` tool to actually gather answers. It accepts at most 4 questions per call, so batch the full interview into as many calls of 4 as needed (a 10-question interview is 3 calls: 4 + 4 + 2). Keep question order identical to the artifact.

Per question:
- `question`: the full question text
- `header`: a short label (max 12 chars)
- `options`: the 3 suggested answers, recommended one first with " (Recommended)" appended to its label
- Do not add a 4th option — the tool always offers "Other" for a custom answer, which covers open-ended free-text input

Fire each batch as a single `AskUserQuestion` call (all questions in that batch as parallel entries within the one call, not sequential calls). Wait for each batch to return before sending the next.

If an answer exposes a new sub-decision that Step 2 didn't already cover (a follow-up gap, not a rephrase), add that question now rather than letting it slide into "Needs details" — append it to the queue and ask it in the next batch, applying the same 3-option format. Keep going until no answer leaves a gap a developer would have to guess through.

## Step 5 — Generate tickets

Synthesize all answers into one or more ticket files. Split on natural seams — each ticket should be executable by an agent in one focused session without needing to hold the full design in context.

**Splitting rules:**
- One ticket per independently deployable change (a system, a feature, a data layer)
- Split when two pieces of work touch different files or different concerns with no shared state
- Don't split just to split — if the work is cohesive and small, one ticket is correct
- Never split a ticket such that ticket B requires ticket A's code but A isn't landed yet; instead mark B `blocked-by: <A-id>`

**For each ticket:**

Generate a task id: kebab-slug from the topic + 2-char random suffix (e.g. `add-dash-k9`).

Write `data/<id>/ticket.md`:

```markdown
# <id>

## Status
<Ready | Blocked by <other-id>: <reason> | Needs details: <what's missing and from whom>>

## Delivery Mode
<no-mistakes | direct-PR | local-only> - <one-line reason>

## Goal
<one or two sentences: what is being built and why>

## Acceptance Criteria
- [ ] <concrete, testable criterion>
- [ ] <concrete, testable criterion>
- [ ] ...
```

Rules for acceptance criteria:
- Each item must be independently verifiable — a validator agent can check it without asking the user
- Favour behaviour over implementation ("dash moves player 3 units" not "use a coroutine")
- Include at least one test coverage criterion when the project has a test suite
- Fewer, sharper criteria beat a long exhaustive list

Rules for Delivery Mode (AGENTS.md §6 per-ticket mode override):
- No tests involved and non-critical (cosmetic, docs, tooling, low-risk isolated change) → `direct-PR`, even if the project's registered default is `no-mistakes`
- Tests involved and touches core functionality (data models, gameplay systems, save/persistence, anything an acceptance criterion calls out a test for) → `no-mistakes`, even if the project's registered default is `direct-PR`
- Anything else → the project's registered default mode (state that explicitly, e.g. "direct-PR - project default, no override criteria met")
- This decision is passed to `bin/fm-brief.sh`/`bin/fm-spawn.sh` via `--mode <mode>` at dispatch time; yolo is unaffected and always comes from the project registry

Rules for Status:
- Default is `Ready` — no unresolved dependency or open question
- If ticket B needs ticket A's code first, set `Blocked by <A-id>: <reason>` — never split work such that B is written without this
- If the interview surfaced a question the answers didn't resolve (missing spec, unavailable stakeholder input, ambiguous scope), set `Needs details: <what's missing>` instead of guessing — don't invent acceptance criteria to paper over a real gap
- Update this line in place if the blocker or missing detail is resolved later; don't leave stale blocked status alongside new work

Add to the backlog as a Queued item, mirroring the ticket's Status line. If `tasks-axi` is available:
```sh
tasks-axi add <id> "<goal one-liner>" --kind ship --repo <project> [--blocked-by <other-id>]
```
Otherwise hand-edit `data/backlog.md`, appending under `## Queued`:
```
- [ ] <id> - <goal one-liner> (repo: <project>) [ticket](data/<id>/ticket.md)
```
If Status is `Blocked by <A-id>`, append `blocked-by: <A-id> - <reason>` to that line (or pass `--blocked-by`). If Status is `Needs details`, append `needs-details: <what's missing>` instead — this ticket is not dispatchable until a human resolves it, even though nothing blocks it structurally.

Tell the user in plain chat: tickets written (list ids), blocked-by relationships if any.
