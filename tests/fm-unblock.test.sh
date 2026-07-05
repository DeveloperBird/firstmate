#!/usr/bin/env bash
# Tests for bin/fm-unblock.sh - propagates a completed ticket's id to every
# other ticket/backlog line that named it as a blocker, archives its
# ticket.md, then deletes it. Runs automatically at the end of a normal
# (non --force) bin/fm-teardown.sh; see tests/fm-teardown.test.sh for the
# integration-point coverage (invoked vs. skipped under --force).
#
# Matrix:
#   (a) single blocker, one downstream ticket + matching backlog line -> both
#       clear to Ready / lose the annotation; ticket archived and deleted
#   (b) multiple blockers on one downstream reference -> only the completed
#       id drops, remaining id(s) and reason text untouched
#   (c) no references anywhere -> clean no-op beyond archive+delete
#   (d) missing ticket.md (already deleted, or a scout/secondmate id that
#       never had one) -> silent no-op, exit 0
#   (e) idempotency -> running it twice on the same id is safe
#   (f) archive correctness -> data/ticket-archive.md holds the verbatim
#       original ticket.md content under a dated heading
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

UNBLOCK="$ROOT/bin/fm-unblock.sh"
TMP_ROOT=$(fm_test_tmproot fm-unblock-tests)

# make_case <name>: fresh data/ dir for one test case. Echoes it.
make_case() {
  local name=$1 dir
  dir="$TMP_ROOT/$name/data"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

write_ticket() {
  local dir=$1 id=$2 status=$3 goal=${4:-Do the thing.}
  mkdir -p "$dir/$id"
  printf '%s\n' "# $id" "" "## Status" "$status" "" "## Goal" "$goal" > "$dir/$id/ticket.md"
}

run_unblock() {
  local dir=$1 id=$2
  FM_DATA_OVERRIDE="$dir" "$UNBLOCK" "$id"
}

test_single_blocker_clears() {
  local dir rc
  dir=$(make_case single-blocker)
  write_ticket "$dir" blocker-a Ready
  write_ticket "$dir" downstream-b "Blocked by blocker-a: needs blocker-a"
  printf '%s\n' "## Queued" \
    "- [ ] downstream-b - depends on blocker-a (repo: x) blocked-by: blocker-a - needs blocker-a [ticket](data/downstream-b/ticket.md)" \
    > "$dir/backlog.md"

  set +e
  run_unblock "$dir" blocker-a > "$dir/out" 2>"$dir/err"
  rc=$?
  set -e

  expect_code 0 "$rc" "single-blocker: exit code"
  assert_absent "$dir/blocker-a/ticket.md" "single-blocker: blocker-a's ticket.md should be deleted"
  assert_grep "## blocker-a" "$dir/ticket-archive.md" "single-blocker: archive should have a blocker-a section"
  assert_grep "Ready" "$dir/downstream-b/ticket.md" "single-blocker: downstream-b Status should flip to Ready"
  assert_no_grep "Blocked by" "$dir/downstream-b/ticket.md" "single-blocker: downstream-b should no longer say Blocked by"
  assert_no_grep "blocked-by:" "$dir/backlog.md" "single-blocker: backlog annotation should be gone"
  assert_grep "- [ ] downstream-b - depends on blocker-a (repo: x) [ticket](data/downstream-b/ticket.md)" "$dir/backlog.md" \
    "single-blocker: rest of the backlog line should be untouched"
  pass "single blocker: sibling ticket and backlog line both clear to unblocked"
}

test_multi_blocker_keeps_remaining() {
  local dir rc
  dir=$(make_case multi-blocker)
  write_ticket "$dir" blocker-a Ready
  write_ticket "$dir" downstream-c "Blocked by blocker-a, other-id: needs both"
  printf '%s\n' "## Queued" \
    "- [ ] downstream-c - depends on two (repo: x) blocked-by: blocker-a, other-id - needs both [ticket](data/downstream-c/ticket.md)" \
    > "$dir/backlog.md"

  run_unblock "$dir" blocker-a > "$dir/out" 2>"$dir/err"

  assert_grep "Blocked by other-id: needs both" "$dir/downstream-c/ticket.md" \
    "multi-blocker: downstream-c should still name other-id, with reason intact"
  assert_no_grep "blocker-a" "$dir/downstream-c/ticket.md" "multi-blocker: blocker-a should be gone from downstream-c"
  assert_grep "blocked-by: other-id - needs both" "$dir/backlog.md" \
    "multi-blocker: backlog should still name other-id, with reason intact"
  assert_no_grep "blocker-a" "$dir/backlog.md" "multi-blocker: blocker-a should be gone from backlog"
  pass "multiple blockers: only the completed id drops, remaining blocker and reason untouched"
}

test_no_references_clean_noop() {
  local dir rc
  dir=$(make_case no-refs)
  write_ticket "$dir" lonely-a Ready
  write_ticket "$dir" unrelated-b Ready

  set +e
  run_unblock "$dir" lonely-a > "$dir/out" 2>"$dir/err"
  rc=$?
  set -e

  expect_code 0 "$rc" "no-refs: exit code"
  assert_absent "$dir/lonely-a/ticket.md" "no-refs: lonely-a's ticket.md should be deleted"
  assert_grep "Ready" "$dir/unrelated-b/ticket.md" "no-refs: unrelated-b should be untouched (still Ready)"
  pass "no downstream references: archive+delete happens, nothing else is touched"
}

test_missing_ticket_is_noop() {
  local dir out rc
  dir=$(make_case missing-ticket)

  set +e
  out=$(run_unblock "$dir" never-existed 2>&1)
  rc=$?
  set -e

  expect_code 0 "$rc" "missing-ticket: exit code"
  assert_contains "$out" "nothing to do" "missing-ticket: should report a no-op"
  assert_absent "$dir/ticket-archive.md" "missing-ticket: should not create an archive file"
  pass "missing ticket.md (scout/secondmate id, or already deleted) is a silent no-op"
}

test_idempotent_second_run() {
  local dir rc1 rc2
  dir=$(make_case idempotent)
  write_ticket "$dir" blocker-a Ready

  run_unblock "$dir" blocker-a > /dev/null 2>&1
  rc1=$?
  set +e
  run_unblock "$dir" blocker-a > "$dir/out2" 2>"$dir/err2"
  rc2=$?
  set -e

  expect_code 0 "$rc1" "idempotent: first run exit code"
  expect_code 0 "$rc2" "idempotent: second run exit code"
  assert_contains "$(cat "$dir/out2")" "nothing to do" "idempotent: second run should be a no-op"
  pass "running fm-unblock.sh twice on the same id is safe"
}

test_archive_has_verbatim_content() {
  local dir
  dir=$(make_case archive-verbatim)
  write_ticket "$dir" blocker-a Ready "A very specific goal sentence."

  run_unblock "$dir" blocker-a > /dev/null 2>&1

  assert_grep "A very specific goal sentence." "$dir/ticket-archive.md" \
    "archive-verbatim: archived entry should preserve the original ticket body"
  grep -q "^## blocker-a (archived [0-9-]*)\$" "$dir/ticket-archive.md" \
    || fail "archive-verbatim: archive entry should have a dated heading"
  pass "archived ticket content is verbatim under a dated heading"
}

test_single_blocker_clears
test_multi_blocker_keeps_remaining
test_no_references_clean_noop
test_missing_ticket_is_noop
test_idempotent_second_run
test_archive_has_verbatim_content
