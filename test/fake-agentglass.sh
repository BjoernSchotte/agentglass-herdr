#!/bin/sh
# agentglass-herdr tests — a fake agentglass that speaks CLI contract 1 (docs/cli-contract.md in the agentglass repo):
# answers --version --json, --json … --format csv, cost … --format csv and --help --format json from fixtures, records
# `open` and the bare TUI start. A field outside contract 1, or a missing --format csv, is an error (exit 2): the plugin
# must not ask for anything the contract does not promise.
# SPDX-License-Identifier: Apache-2.0
: "${FAKE_DIR:?fake agentglass: FAKE_DIR not set}"
JSON_FIELDS=" id harness title cwd live pid status costUsd attention stuck alerts mux mux_kind mux_pane mux_workspace mux_tab mux_status "
COST_FIELDS=" key workspaceId costUsd "
bad() { echo "fake agentglass: $*" >&2; exit 2; }
# --fields a,b and --format csv, checked against the allowed list in $1
check_args() {
  allowed=$1; shift; fmt=""; fields=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --format) fmt=${2-}; shift ;;
      --fields) fields=${2-}; shift ;;
    esac
    shift
  done
  [ "$fmt" = csv ] || bad "expected --format csv, got '$fmt'"
  [ -n "$fields" ] || bad "expected --fields"
  old_ifs=$IFS; IFS=,
  for f in $fields; do
    case "$allowed" in *" $f "*) ;; *) IFS=$old_ifs; bad "field '$f' is not in contract 1" ;; esac
  done
  IFS=$old_ifs
}
log_tui() { printf 'tui AGENTGLASS_AGENT=%s AGENTGLASS_REDACT=%s\n' "${AGENTGLASS_AGENT-}" "${AGENTGLASS_REDACT-}" >> "$FAKE_DIR/open.log"; }
if [ $# -eq 0 ]; then log_tui; exit 0; fi
case "$1" in
  --version)
    [ "${2-}" = --json ] || bad "--version without --json"
    [ -f "$FAKE_DIR/version.json" ] || exit 1
    cat "$FAKE_DIR/version.json" ;;
  --help)
    cat "$FAKE_DIR/help.json" ;;
  --json)
    shift; check_args "$JSON_FIELDS" "$@"
    n=$(cat "$FAKE_DIR/ag.count" 2>/dev/null || echo 0); echo $((n + 1)) > "$FAKE_DIR/ag.count"
    printf '%s\n' "${AGENTGLASS_HERDR-<unset>}" >> "$FAKE_DIR/ag.herdr"
    [ "${FAKE_AG_SLEEP:-0}" = 0 ] || sleep "$FAKE_AG_SLEEP"
    [ "${FAKE_AG_RC:-0}" = 0 ] || exit "$FAKE_AG_RC"
    cat "$FAKE_DIR/live.csv" ;;
  cost)
    shift; since=""; a="$*"
    while [ $# -gt 0 ]; do case "$1" in --since) since=${2-}; shift ;; esac; shift; done
    # shellcheck disable=SC2086 # the recorded argv, split again on purpose
    check_args "$COST_FIELDS" $a
    case "$a" in *"--by workspace"*) ;; *) bad "cost without --by workspace" ;; esac
    case "$since" in today|7d) cat "$FAKE_DIR/cost-$since.csv" ;; *) bad "cost --since '$since'" ;; esac ;;
  open)
    printf '%s\n' "$*" >> "$FAKE_DIR/open.log" ;;
  *)
    bad "unexpected call: $*" ;;
esac
