#!/bin/sh
# agentglass-herdr tests — a fake herdr: records every call, answers from fixtures, never talks to a server.
# $FAKE_DIR/herdr.log gets one line per call (the argv, space-joined); $FAKE_DIR/herdr.env the HERDR_SOCKET_PATH it saw.
# SPDX-License-Identifier: Apache-2.0
: "${FAKE_DIR:?fake herdr: FAKE_DIR not set}"
printf '%s\n' "$*" >> "$FAKE_DIR/herdr.log"
printf '%s\n' "${HERDR_SOCKET_PATH-<unset>}" >> "$FAKE_DIR/herdr.env"
case "$1 ${2-}" in
  "plugin pane") exit "${FAKE_HERDR_PANE_RC:-0}" ;;
  "plugin config-dir") printf '%s\n' "${FAKE_HERDR_CONFIG_DIR:-$FAKE_DIR/plugin-config}"; exit 0 ;;
  "notification show") exit 0 ;;
  "pane report-metadata"|"workspace report-metadata") exit "${FAKE_HERDR_REPORT_RC:-0}" ;;
  "workspace list") cat "$FAKE_DIR/workspaces.json"; exit 0 ;;
esac
echo "fake herdr: unexpected call: $*" >&2
exit 2
