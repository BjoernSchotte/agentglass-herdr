#!/bin/sh
# agentglass-herdr — the event and startup hooks (pane.agent_status_changed, pane.agent_detected, startup): refresh the
# sidebar tokens when they are on; nothing at all otherwise. On startup (a new herdr server: pane metadata is gone) the
# last reported values are forgotten, so everything is reported again.
# SPDX-License-Identifier: Apache-2.0
[ -n "${HERDR_PLUGIN_STATE_DIR-}" ] && [ -f "$HERDR_PLUGIN_STATE_DIR/tokens.on" ] || exit 0
if [ "${1-}" = startup ] || [ "${HERDR_PLUGIN_EVENT-}" = startup ]; then exec /bin/sh "$(dirname "$0")/ag-tokens.sh" run --fresh; fi
exec /bin/sh "$(dirname "$0")/ag-tokens.sh" run
