---
name: ticket-board
description: Print a minimal terminal listing of every open ticket (data/*/ticket.md) — id, status, one-line description, ranked highest to lowest priority. Use when the user wants to see, review, or get an overview of all tickets, or invokes /ticket-board.
user-invocable: true
---

# Ticket Board

Prints a plain-text ticket listing directly in the reply, ordered highest to lowest priority. Regenerate fresh each invocation — ticket state (status, blockers, backlog position) can change between runs, so never reuse a stale render. No artifact, no HTML — this is a cheap terminal glance, not a review surface.

## Step 1 — Gather

- `find data -maxdepth 2 -iname ticket.md` and read each one, but only enough to get `## Status`, `## Delivery Mode`, and the one-line `## Goal` sentence — do not read Design decisions or Acceptance Criteria, they are not shown.
- Read `data/backlog.md` for the In flight / Queued / Done sections and any `blocked-by:` / `needs-details:` annotations on each line.

If a ticket dir exists with no backlog line, or a backlog line points at a missing ticket.md, flag it to the user as a discrepancy rather than silently guessing — don't delete or fabricate anything.

A `Blocked by <id>` naming an id with no `data/<id>/ticket.md` and no backlog line is not automatically a discrepancy: `bin/fm-unblock.sh` (run at teardown) is supposed to have already flipped that reference to `Ready` once `<id>` completed, so a stale one means either it predates that fix or something was missed. Check `data/ticket-archive.md` for a `## <id>` entry before flagging it — if found, the blocker legitimately finished and this ticket's Status just needs a manual update to `Ready`; if not found anywhere, flag it as a genuine discrepancy.

## Step 2 — Reconcile status

Backlog is the source of truth for lifecycle placement (in flight vs queued); `ticket.md`'s `## Status` field is the source of truth for Ready / Blocked by `<id>` / Needs details. If a ticket is listed In flight in the backlog, its board status is **In Progress** regardless of what its `## Status` field says.

## Step 3 — Rank (highest to lowest priority)

No explicit priority field exists, so rank by judgment using this order:

1. **In Progress** — already being worked, always shown first.
2. **Ready** — no blocker, sorted by *unblock count*: count how many other tickets name this ticket's id in their `Blocked by`; higher count ranks higher, since landing it frees the most downstream work. Ties broken by ticket id.
3. **Blocked** — grouped directly beneath the ticket that blocks them, ordered by the blocker's own rank.
4. **Needs details** — last, since nothing can proceed until a human answers the open question.

## Step 4 — Print

Output a plain-text block directly in the chat reply (no file, no Artifact call). One line per ticket, grouped under a short section header per tier from Step 3, in this form:

```
IN PROGRESS
  roster-character-swap-q3 — Swap a Team's characters from the Loadout screen

READY
  potion-treasure-loot-types-v2 — Add Potion/Treasure Floor Loot entry types

BLOCKED
  shop-potions-m2 (by potion-treasure-loot-types-v2, shopkeeper-buysell-k4) — Buy 3 random Potions from the Shop

NEEDS DETAILS
  floor-select-entry-q9 — Let the player pick which floor to enter before a run
```

Keep the description to one short clause derived from the ticket's `## Goal` — trim it, don't quote the whole sentence. Omit empty tiers. Call out any Step 1 discrepancies as plain text after the listing, not inside it.
