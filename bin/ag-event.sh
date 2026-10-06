#!/bin/sh
# agentglass-herdr — the event and startup hooks (pane.agent_status_changed, pane.agent_detected, startup): refresh the
# sidebar tokens when they are on; nothing at all otherwise. On startup (a new herdr server: pane metadata is gone) the
# last reported values are forgotten, so everything is reported again.
# SPDX-License-Identifier: Apache-2.0
if [ -z "${HERDR_PLUGIN_STATE_DIR-}" ] || [ ! -f "$HERDR_PLUGIN_STATE_DIR/tokens.on" ]; then exit 0; fi
# a run is going (a fresh lock): mark it dirty and leave without starting a shell and agentglass checks for nothing.
# dirty before the look at the lock — the holder checks dirty after its unlock (see bin/ag-tokens.sh run)
S=$HERDR_PLUGIN_STATE_DIR
if [ "${1-}" != startup ] && [ -d "$S/run.lock" ]; then
  : > "$S/dirty"
  at=$(cat "$S/run.lock/at" 2>/dev/null || echo 0)
  case "$at" in ''|*[!0-9]*) at=0 ;; esac
  if [ -d "$S/run.lock" ] && [ $(($(date +%s) - at)) -lt 120 ]; then exit 0; fi
fi
if [ "${1-}" = startup ] || [ "${HERDR_PLUGIN_EVENT-}" = startup ]; then exec /bin/sh "$(dirname "$0")/ag-tokens.sh" run --fresh; fi
exec /bin/sh "$(dirname "$0")/ag-tokens.sh" run
