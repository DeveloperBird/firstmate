#!/usr/bin/env bash
# bin/fm-unblock.sh - propagate a completed ticket's id to every other ticket
# and backlog line that named it as a blocker, archive its ticket.md, then
# delete it.
#
# Usage: fm-unblock.sh <completed-id>
#
# Called automatically by bin/fm-teardown.sh at the end of a normal (non
# --force) teardown, right before the backlog-refresh reminder. Without this,
# deleting a completed ticket's ticket.md (the old prose-only instruction)
# left every ticket/backlog line that named it as a blocker dangling forever,
# with no way to tell "blocker finished" from "something is wrong".
#
# Idempotent and best-effort:
#   - a missing ticket.md is a silent no-op (covers scout/secondmate tasks,
#     which never have one, and a second run on the same id)
#   - a single malformed reference is skipped with a stderr warning, never
#     fatal - teardown must never fail because of this step
#
# Reference formats rewritten:
#   ticket.md `## Status` body:  Blocked by <id1>[, <id2>...]: <reason>
#   data/backlog.md annotation:  blocked-by: <id1>[, <id2>...][ - <reason>]
# The backlog reason suffix is optional and the clause need not end the
# line - real backlog lines commonly run the ids straight into trailing
# `(repo: ...)`/`(kind: ...)`/`[ticket](...)` metadata with no reason text.
# When the completed id is the only blocker, the ticket.md Status flips to
# `Ready` and the backlog annotation is dropped entirely. When other blockers
# remain, only this id is removed from the list; the reason text is left
# as-is (it may still mention the cleared id in free-form prose - that is a
# manual touch-up, not something this script text-surgeries).
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
DATA="${FM_DATA_OVERRIDE:-$FM_HOME/data}"

ID=${1:?usage: fm-unblock.sh <completed-id>}
TICKET="$DATA/$ID/ticket.md"
BACKLOG="$DATA/backlog.md"
ARCHIVE="$DATA/ticket-archive.md"

if [ ! -f "$TICKET" ]; then
  echo "unblock: no ticket.md for $ID, nothing to do"
  exit 0
fi

cleared_tickets=""
cleared_backlog=0

# Pass 1: every other ticket's `## Status` field.
for other in "$DATA"/*/ticket.md; do
  [ -e "$other" ] || continue
  [ "$other" != "$TICKET" ] || continue
  before=$(cat "$other")
  FM_UNBLOCK_ID="$ID" perl -0777 -pi -e '
    my $target = $ENV{FM_UNBLOCK_ID};
    s{^## Status\n(Blocked by ([^\n:]+)(:.*))$}{
      my ($full, $idsraw, $rest) = ($1, $2, $3);
      my @ids = split(/,\s*/, $idsraw);
      if (grep { $_ eq $target } @ids) {
        my @remaining = grep { $_ ne $target } @ids;
        @remaining
          ? "## Status\nBlocked by " . join(", ", @remaining) . $rest
          : "## Status\nReady";
      } else {
        "## Status\n$full";
      }
    }me;
  ' "$other" 2>/dev/null || echo "unblock: warning: could not parse Status field in $other" >&2
  after=$(cat "$other")
  if [ "$before" != "$after" ]; then
    cleared_tickets="$cleared_tickets $(dirname "$other" | xargs -I{} basename {})"
  fi
done

# Pass 2: data/backlog.md `blocked-by:` annotations.
if [ -f "$BACKLOG" ]; then
  before=$(cat "$BACKLOG")
  FM_UNBLOCK_ID="$ID" perl -i -pe '
    my $target = $ENV{FM_UNBLOCK_ID};
    if (/( blocked-by: ([\w-]+(?:,\s*[\w-]+)*)(?: - (?:(?!\s*[\[(]).)*)?)/) {
      my ($fullmatch, $idsraw) = ($1, $2);
      my @ids = split(/,\s*/, $idsraw);
      if (grep { $_ eq $target } @ids) {
        my @remaining = grep { $_ ne $target } @ids;
        if (@remaining) {
          my $newids = join(", ", @remaining);
          (my $replacement = $fullmatch) =~ s/\Q$idsraw\E/$newids/;
          s/\Q$fullmatch\E/$replacement/;
        } else {
          s/\Q$fullmatch\E//;
        }
      }
    }
  ' "$BACKLOG" 2>/dev/null || echo "unblock: warning: could not parse blocked-by annotations in $BACKLOG" >&2
  after=$(cat "$BACKLOG")
  if [ "$before" != "$after" ]; then
    cleared_backlog=1
  fi
fi

# Archive the ticket's full content, then delete it. Only the file is
# removed, never the data/<id>/ directory - it may hold a sibling brief.md
# or report.md.
[ -f "$ARCHIVE" ] || printf '# Ticket Archive\n\nCompleted tickets whose ticket.md was deleted at teardown. Kept here (not\nunder the `ticket.md` filename ticket-board scans for) so a stale-looking\n"Blocked by <id>" reference can still be resolved by hand.\n\n' > "$ARCHIVE"
{
  printf '## %s (archived %s)\n\n' "$ID" "$(date +%Y-%m-%d)"
  cat "$TICKET"
  printf '\n---\n\n'
} >> "$ARCHIVE"
rm -f "$TICKET"

summary="unblock: archived $DATA/$ID/ticket.md -> $ARCHIVE"
[ -z "$cleared_tickets" ] || summary="$summary; cleared blocker in:$cleared_tickets"
[ "$cleared_backlog" -eq 0 ] || summary="$summary; cleared blocked-by in $BACKLOG"
printf '%s\n' "$summary"
