#!/usr/bin/env bash
# fm-mode-lib.sh — single source of truth for the three delivery-mode values
# (AGENTS.md section 6: no-mistakes | direct-PR | local-only). Sourced by
# fm-brief.sh, fm-spawn.sh, and fm-project-mode.sh so the valid-mode list
# lives in one place instead of three copies that can drift apart.
#
# fm_valid_mode <mode>  — 0 if <mode> is one of the three values, 1 otherwise.
#                          Callers decide what to do with an invalid mode
#                          (hard error vs. warn-and-default).

fm_valid_mode() {
  case "$1" in
    no-mistakes|direct-PR|local-only) return 0 ;;
    *) return 1 ;;
  esac
}
