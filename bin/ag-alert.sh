#!/bin/sh
# agentglass-herdr — the notify recipe: agentglass runs this as rules.json "notify.command" with the alert JSON on stdin
# (contract 1). Usage: ag-alert.sh [PLUGIN_CONFIG_DIR]  (the README's setup passes the dir `herdr plugin config-dir
# agentglass` prints).
# It forwards only what herdr cannot see: never `waiting` or `approval` (herdr rings for done/blocked itself), only the
# states fire and escalate. The session's herdr pane gets $ag_alert for 10 minutes; a critical alert also becomes a herdr
# notification "<rule> · <harness>". Titles, messages and projects are never read or forwarded.
# agentglass strips the environment of notify commands: herdr is found by path, its server by HERDR_SOCKET_PATH in the
# plugin config (else herdr's default socket).
# SPDX-License-Identifier: Apache-2.0
# shellcheck source=bin/ag-env.sh
. "$(dirname "$0")/ag-env.sh"

json=$(head -c 65536)
# a string field of the alert JSON by its key (agentglass writes compact JSON; the keys are fixed by the contract)
field() { printf '%s\n' "$json" | sed -n "s/^.*\"$1\"[[:space:]]*:[[:space:]]*\"\\([^\"\\\\]*\\)\".*\$/\\1/p" | head -n 1; }
rule=$(field rule); severity=$(field severity); state=$(field state); session=$(field session); harness=$(field harness)

case "$rule" in ''|waiting|approval) exit 0 ;; esac
case "$state" in fire|escalate) ;; *) exit 0 ;; esac
[ -n "$session" ] || exit 0

ag_find
if [ -n "${1-}" ]; then AGH_CONFIG=$1
elif [ -z "$AGH_CONFIG" ] && [ -n "$HERDR" ]; then AGH_CONFIG=$("$HERDR" plugin config-dir agentglass 2>/dev/null) || AGH_CONFIG=""
fi
ag_find # again: the config can name AGENTGLASS_BIN
h=$(ag_cfg HERDR_BIN); [ -n "$h" ] && HERDR=$h
if [ -z "$HERDR" ]; then echo "agentglass-herdr: herdr not found (set HERDR_BIN in $(ag_config_file))" >&2; exit 1; fi
ag_socket
ag_need || exit 1

# the session's herdr pane (contract 1: --json --live, fields id, harness, mux_kind, mux_pane)
pane=$(ag_run --json --live --all-projects --fields id,harness,mux_kind,mux_pane --format csv | ag_csv_select id harness mux_kind mux_pane |
  while IFS=$US read -r id h kind p; do
    [ "$id" = "$session" ] && [ "$kind" = herdr ] && { [ -z "$harness" ] || [ "$h" = "$harness" ]; } && { printf '%s\n' "$p"; break; }
  done)
ag_valid_pane "$pane" || exit 0 # not in a herdr pane: nothing to show there

"$HERDR" pane report-metadata "$pane" --source plugin:agentglass --token "ag_alert=$(ag_fmt_alert "$rule")" --ttl-ms 600000 >/dev/null
if [ "$severity" = critical ]; then
  r=$(printf '%s' "$rule" | tr -cd 'A-Za-z0-9_.-' | cut -c 1-32)
  hn=$(printf '%s' "$harness" | tr -cd 'A-Za-z0-9_.-' | cut -c 1-32)
  "$HERDR" notification show agentglass --body "$r · ${hn:-agent}" --sound request >/dev/null
fi
exit 0
