---
name: ticket-board
description: Render every open ticket (data/*/ticket.md) as a single prioritized HTML artifact — full goal, status/blockers, design decisions, and acceptance criteria per ticket. Use when the user wants to see, review, or get an overview of all tickets, or invokes /ticket-board.
user-invocable: true
---

# Ticket Board

Generates a one-shot HTML artifact showing every ticket in full detail, ordered highest to lowest priority. Regenerate fresh each invocation — ticket state (status, blockers, backlog position) can change between runs, so never reuse a stale render.

## Step 1 — Gather

- `find data -maxdepth 2 -iname ticket.md` and read each one in full (Goal, Status, Delivery Mode, Design decisions, Acceptance Criteria).
- Read `data/backlog.md` for the In flight / Queued / Done sections and any `blocked-by:` / `needs-details:` annotations on each line.

If a ticket dir exists with no backlog line, or a backlog line points at a missing ticket.md, flag it to the user as a discrepancy rather than silently guessing — don't delete or fabricate anything.

A `Blocked by <id>` naming an id with no `data/<id>/ticket.md` and no backlog line is not automatically a discrepancy: `bin/fm-unblock.sh` (run at teardown) is supposed to have already flipped that reference to `Ready` once `<id>` completed, so a stale one means either it predates that fix or something was missed. Check `data/ticket-archive.md` for a `## <id>` entry before flagging it — if found, the blocker legitimately finished and this ticket's Status just needs a manual update to `Ready`; if not found anywhere, flag it as a genuine discrepancy.

## Step 2 — Reconcile status

Backlog is the source of truth for lifecycle placement (in flight vs queued); `ticket.md`'s `## Status` field is the source of truth for Ready / Blocked by `<id>` / Needs details. If a ticket is listed In flight in the backlog, its board status is **In Progress** regardless of what its `## Status` field says.

## Step 3 — Rank (highest to lowest priority)

No explicit priority field exists, so rank by judgment using this order:

1. **In Progress** — already being worked, always shown first.
2. **Ready** — no blocker, sorted by *unblock count*: count how many other tickets name this ticket's id in their `Blocked by`; higher count ranks higher, since landing it frees the most downstream work. Ties broken by ticket id.
3. **Blocked** — grouped directly beneath the ticket that blocks them (visually nest or badge-link them to their blocker), ordered by the blocker's own rank.
4. **Needs details** — last, since nothing can proceed until a human answers the open question. Surface the missing-detail note prominently — this tier is the one most likely to need the user's attention.

## Step 4 — Build the artifact

Load the `artifact-design` skill before writing any HTML.

Write the file to the scratchpad directory (e.g. `ticket-board.html`). One column or a responsive card grid — pick based on ticket count (a handful of tickets reads fine as generous full-width cards; a dozen-plus wants a tighter grid). For each ticket, a card containing:

- Ticket id + one-line goal as the header
- A status badge: In Progress / Ready / Blocked by `<id>` / Needs details — color-coded distinctly (e.g. in-progress = active/blue, ready = success/green, blocked = warning/amber, needs details = danger/red) since this is the fastest scan signal on the page
- Repo/project name if known
- Delivery mode (no-mistakes / direct-PR / local-only) as a small badge if the ticket has a `## Delivery Mode` field
- Full acceptance criteria as a checklist (checked boxes rendered checked, unchecked rendered unchecked — this is real state, not decoration)
- Design decisions section if present, collapsible if long
- If blocked: a visible link/reference to the blocking ticket's card (anchor link is enough, no need for a full dependency graph unless the chain is deep enough to warrant one)

Order cards top-to-bottom (or reading-order in the grid) per the Step 3 ranking. A short section label per tier (In Progress / Ready / Blocked / Needs Details) helps orientation more than pure flat ranking does.

## Step 5 — Publish

Call the `Artifact` tool on the file with a favicon (e.g. 🎫). Tell the user in one line that the board is ready, and call out anything from Step 1's discrepancy check.
