#!/bin/sh
# agentglass-herdr — sidebar tokens $ag_cost / $ag_alert: on | off | run [--fresh]
#   on    enable (a flag file in the state dir) and report once      (action tokens-on)
#   off   disable and clear every token this plugin set              (action tokens-off)
#   run   one report, from the event and startup hooks (bin/ag-event.sh); --fresh sends every value again
# One run = one `agentglass --json --live --all-projects` (contract 1 fields mux_kind, mux_pane, costUsd, stuck) → for each
# agent in a herdr pane `herdr pane report-metadata` with ag_cost (7 characters) and ag_alert (10 columns), and per
# workspace the sum of its panes' cost. A value is sent only when it changed. Runs never overlap: an event during a run
# marks it dirty and the running one goes again (at most 3 rounds). Only numbers and rule ids go to herdr.
# SPDX-License-Identifier: Apache-2.0
# shellcheck source=bin/ag-env.sh
. "$(dirname "$0")/ag-env.sh"

SOURCE=plugin:agentglass
FLAG=$AGH_STATE/tokens.on
DIRTY=$AGH_STATE/dirty
LAST=$AGH_STATE/tokens # last reported values: p.<pane> / w.<workspace>, two lines (ag_cost, ag_alert)

if [ -z "$AGH_STATE" ]; then echo "agentglass-herdr: HERDR_PLUGIN_STATE_DIR not set" >&2; exit 1; fi
ag_find
notify() { [ -n "$HERDR" ] && "$HERDR" notification show agentglass --body "$1" >/dev/null; }

# report KIND ID COST ALERT — send the tokens that changed against the last values (KIND pane | workspace); an empty
# value clears a token that was set. The last values move only when herdr took the report.
report() {
  kind=$1; id=$2; c=$3; a=$4
  f=$LAST/$(printf '%s' "$kind" | cut -c 1).$id
  old_c=$(sed -n 1p "$f" 2>/dev/null); old_a=$(sed -n 2p "$f" 2>/dev/null)
  [ "$c" = "$old_c" ] && [ "$a" = "$old_a" ] && return 0
  set -- "$kind" report-metadata "$id" --source "$SOURCE"
  # only the token that changed (herdr keeps the ones a report does not name)
  if [ "$c" != "$old_c" ]; then
    if [ -n "$c" ]; then set -- "$@" --token "ag_cost=$c"; else set -- "$@" --clear-token ag_cost; fi
  fi
  if [ "$a" != "$old_a" ]; then
    if [ -n "$a" ]; then set -- "$@" --token "ag_alert=$a"; else set -- "$@" --clear-token ag_alert; fi
  fi
  set -- "$@" --seq "$SEQ"
  if "$HERDR" "$@" >/dev/null 2>"$AGH_STATE/herdr.err"; then
    printf '%s\n%s\n' "$c" "$a" > "$f"
  else
    ag_log "herdr $kind report-metadata $id failed: $(head -c 300 "$AGH_STATE/herdr.err" | tr '\n' ' ')"
  fi
}

# clear KIND ID — remove both tokens where this plugin set them (a closed pane fails: forgotten all the same)
clear_tokens() {
  if [ "$1" = pane ]; then "$HERDR" pane report-metadata "$2" --source "$SOURCE" --clear-token ag_cost --clear-token ag_alert --seq "$SEQ"
  else "$HERDR" workspace report-metadata "$2" --source "$SOURCE" --clear-token ag_cost --clear-token ag_alert --seq "$SEQ"; fi \
    >/dev/null 2>&1 || true
}

one_run() {
  if ! csv=$(ag_run --json --live --all-projects --fields mux_kind,mux_pane,costUsd,stuck --format csv 2>"$AGH_STATE/ag.err"); then
    ag_log "agentglass --json failed: $(head -c 300 "$AGH_STATE/ag.err" | tr '\n' ' ')"
    return 1 # the old values stay (no flapping)
  fi
  SEQ=$(ag_seq)
  mkdir -p "$LAST"
  redact=""; ag_redact && redact=1
  # one line per herdr pane (the first row = the newest session wins): pane, cost, stuck; then per workspace (the pane
  # id's part before ":" is herdr's workspace id) the sum of the priced panes
  rows=$(printf '%s\n' "$csv" | ag_csv_select mux_kind mux_pane costUsd stuck |
    awk -F "$US" -v OFS="$US" '$1 == "herdr" && $2 != "" && !seen[$2]++ { print "p", $2, $3, $4 }')
  sums=$(printf '%s\n' "$rows" | awk -F "$US" -v OFS="$US" '
    $1 == "p" { w = $2; sub(/:.*/, "", w); if (!(w in has)) { has[w] = 0; order[++n] = w }
                if ($3 ~ /^[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/) { sum[w] += $3; has[w] = 1 } }
    END { for (i = 1; i <= n; i++) { w = order[i]; print "w", w, (has[w] ? sprintf("%.6f", sum[w]) : "") } }')
  : > "$AGH_STATE/seen"
  printf '%s\n%s\n' "$rows" "$sums" | while IFS=$US read -r k id usd stuck; do
    if [ -z "$k" ] || ! ag_valid_pane "$id"; then continue; fi
    c=""; [ -n "$redact" ] || c=$(ag_fmt_cost "$usd")
    if [ "$k" = p ]; then report pane "$id" "$c" "$(ag_fmt_alert "$stuck")"; else report workspace "$id" "$c" ""; fi
    echo "$k.$id" >> "$AGH_STATE/seen"
  done
  # panes and workspaces that no longer host an agent: clear what was set there
  for f in "$LAST"/p.* "$LAST"/w.*; do
    [ -f "$f" ] || continue
    name=${f##*/}
    grep -qxF "$name" "$AGH_STATE/seen" && continue
    case "$name" in p.*) clear_tokens pane "${name#p.}" ;; *) clear_tokens workspace "${name#w.}" ;; esac
    rm -f "$f"
  done
}

run() {
  [ -f "$FLAG" ] || return 0
  if ! ag_need 2>"$AGH_STATE/need.err"; then ag_log_once contract "$(cat "$AGH_STATE/need.err")"; return 0; fi
  [ -n "$HERDR" ] || { ag_log_once herdr "herdr not found"; return 0; }
  rounds=0
  while [ "$rounds" -lt 3 ]; do
    if ! ag_lock; then : > "$DIRTY"; return 0; fi # a run is going: it goes again for us
    trap 'ag_unlock' EXIT
    trap 'ag_unlock; exit 1' INT TERM HUP
    while [ "$rounds" -lt 3 ] && [ -f "$FLAG" ]; do
      rm -f "$DIRTY"
      one_run
      rounds=$((rounds + 1))
      [ -f "$DIRTY" ] || break
    done
    ag_unlock
    trap - EXIT INT TERM HUP
    # an event that came between the last check and the unlock left the flag: take the lock again
    if [ ! -f "$DIRTY" ] || [ ! -f "$FLAG" ]; then break; fi
  done
}

# forget the last values, but keep which panes and workspaces have tokens (so the next run sends every value again
# and still clears the ones that no longer host an agent)
forget() {
  for f in "$LAST"/p.* "$LAST"/w.*; do [ -f "$f" ] && printf '%s\n%s\n' "?" "?" > "$f"; done
  return 0
}

# wait for a running run (at most ~10 s), so it cannot report after we clear
wait_lock() {
  n=0
  while ! ag_lock; do n=$((n + 1)); [ "$n" -le 20 ] || return 1; sleep 0.5 2>/dev/null || sleep 1; done
}

case "${1-}" in
  on)
    if ! msg=$(ag_need 2>&1); then notify "$msg"; exit 1; fi
    : > "$FLAG"
    forget
    run
    notify "sidebar tokens on: add \$ag_cost / \$ag_alert to ui.sidebar.agents.rows (see the plugin README)" ;;
  off)
    rm -f "$FLAG"
    wait_lock || ag_log "tokens off: a run held the lock for 10 s; clearing anyway"
    if [ -n "$HERDR" ]; then
      SEQ=$(ag_seq)
      for f in "$LAST"/p.* "$LAST"/w.*; do
        [ -f "$f" ] || continue
        name=${f##*/}
        case "$name" in p.*) clear_tokens pane "${name#p.}" ;; *) clear_tokens workspace "${name#w.}" ;; esac
      done
    fi
    rm -rf "$LAST" "$DIRTY"
    ag_unlock
    notify "sidebar tokens off" ;;
  run)
    [ "${2-}" = --fresh ] && forget
    run ;;
  *)
    echo "usage: ag-tokens.sh on|off|run [--fresh]" >&2; exit 2 ;;
esac
exit 0
