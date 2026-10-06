#!/bin/sh
# agentglass-herdr — actions (herdr-plugin.toml [[actions]]): tui | open-here | open-link | workspace-cost.
# Actions run without a terminal: they open a popup pane (bin/ag-pane.sh) or show a herdr notification. Errors go to
# stderr, which herdr keeps in the plugin log (herdr plugin log list --plugin agentglass).
# SPDX-License-Identifier: Apache-2.0
# shellcheck source=bin/ag-env.sh
. "$(dirname "$0")/ag-env.sh"

ag_find
PLUGIN=${HERDR_PLUGIN_ID:-agentglass}
if [ -z "$HERDR" ]; then echo "agentglass-herdr: herdr not found (HERDR_BIN_PATH unset)" >&2; exit 1; fi

# open_pane ENTRYPOINT [KEY=VALUE] — the popup; the value travels as the pane's environment (no state file, no race)
open_pane() {
  if [ $# -gt 1 ]; then "$HERDR" plugin pane open --plugin "$PLUGIN" --entrypoint "$1" --env "$2"
  else "$HERDR" plugin pane open --plugin "$PLUGIN" --entrypoint "$1"; fi
}
notify() { "$HERDR" notification show agentglass --body "$1"; }

# money for a notification: $12.82, unpriced → ?
usd() { awk -v v="$1" 'BEGIN { if (v ~ /^[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/) printf "$%.2f", v; else printf "?" }'; }

case "${1-}" in
  tui)
    open_pane tui ;;
  open-here)
    target=${HERDR_PANE_ID-}
    if ag_valid_pane "$target"; then open_pane open "AGH_TARGET=$target"
    else open_pane open; fi ;;
  open-link)
    url=${HERDR_PLUGIN_CLICKED_URL-}
    if ! ag_valid_url "$url"; then echo "agentglass-herdr: ignored a link that is not agentglass://open/<ref>" >&2; exit 0; fi
    open_pane link "AGH_URL=$url" ;;
  workspace-cost)
    ws=${HERDR_WORKSPACE_ID-}
    if ! ag_valid_pane "$ws"; then echo "agentglass-herdr: no workspace in this context" >&2; exit 1; fi
    if ! msg=$(ag_need 2>&1); then notify "$msg"; exit 1; fi
    # one row per herdr workspace (contract 1: cost --by workspace, fields key, workspaceId, costUsd)
    row() {
      ag_run cost --since "$1" --by workspace --format csv --fields key,workspaceId,costUsd |
        ag_csv_select workspaceId key costUsd |
        while IFS=$US read -r id key usd; do [ "$id" = "$ws" ] && { printf '%s%s%s\n' "$key" "$US" "$usd"; break; }; done
    }
    today=$(row today) || today=""
    week=$(row 7d) || week=""
    label=${today%%"$US"*}; [ -n "$label" ] || label=${week%%"$US"*}
    # under redact the workspace is named by its id (labels are free text: customer and project names)
    if [ -z "$label" ] || ag_redact; then label=$ws; fi
    if [ -z "$today" ] && [ -z "$week" ]; then notify "$label: no agent cost in the last 7 days"; exit 0; fi
    t=${today#*"$US"}; [ -n "$today" ] || t=0
    w=${week#*"$US"}; [ -n "$week" ] || w=0
    notify "$label: $(usd "$t") today · $(usd "$w") 7 days" ;;
  *)
    echo "usage: ag-action.sh tui|open-here|open-link|workspace-cost" >&2; exit 2 ;;
esac
