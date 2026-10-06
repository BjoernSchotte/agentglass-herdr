#!/bin/sh
# agentglass-herdr — the popup panes: tui | open | link (herdr-plugin.toml [[panes]]).
#   tui   the agentglass TUI
#   open  the session of the herdr pane in AGH_TARGET (set by the open-here action), else the TUI with a note
#   link  the agentglass:// link in AGH_URL (set by the open-link action)
# A pane that cannot start agentglass (missing, CLI contract < 1) says why and waits for Enter.
# SPDX-License-Identifier: Apache-2.0
# shellcheck source=bin/ag-env.sh
. "$(dirname "$0")/ag-env.sh"

ag_find
if ! ag_need; then ag_wait_key; exit 1; fi

# a line above the TUI for a moment (the TUI's screen replaces it)
note() { printf 'agentglass: %s\n' "$*" >&2; sleep 1; }

case "${1-}" in
  tui)
    ag_popup ;;
  open)
    target=${AGH_TARGET-}
    if ! ag_valid_pane "$target"; then note "no herdr pane to open — showing all sessions"; ag_popup; fi
    # the session whose live agent runs in that pane (contract 1: --json --live, fields id, harness, mux_pane)
    if ! rows=$(ag_run --json --live --all-projects --fields id,harness,mux_pane --format csv); then
      note "agentglass --json failed — showing all sessions"; ag_popup
    fi
    ref=$(printf '%s\n' "$rows" | ag_csv_select mux_pane harness id |
      while IFS=$US read -r pane h id; do
        [ "$pane" = "$target" ] && [ -n "$h" ] && [ -n "$id" ] && { printf '%s:%s\n' "$h" "$id"; break; }
      done)
    if [ -z "$ref" ]; then note "no agentglass session is linked to herdr pane $target — showing all sessions"; ag_popup; fi
    # --new-instance: a TUI running elsewhere must not take the session; the popup is where the user looks
    ag_popup open "$ref" --new-instance ;;
  link)
    url=${AGH_URL-}
    if ! ag_valid_url "$url"; then echo "agentglass: not an agentglass://open/ link" >&2; ag_wait_key; exit 1; fi
    ag_popup open "$url" --new-instance ;;
  *)
    echo "usage: ag-pane.sh tui|open|link" >&2; exit 2 ;;
esac
