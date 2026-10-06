# bin/ag-action.sh: actions tui, open-here, open-link, workspace-cost
# SPDX-License-Identifier: Apache-2.0
# shellcheck source=test/lib.sh disable=SC2016 # literal $ in expected values is the point
. "$ROOT/test/lib.sh"
act() { "$TEST_SH" "$ROOT/bin/ag-action.sh" "$@" 2>"$TMPDIR/err"; }

reset_fakes
act tui
eq "tui opens the popup" "$(cat0 "$FAKE_DIR/herdr.log")" "plugin pane open --plugin agentglass --entrypoint tui"

reset_fakes
HERDR_PANE_ID=w7:p1A act open-here
eq "open-here passes the focused pane" "$(cat0 "$FAKE_DIR/herdr.log")" "plugin pane open --plugin agentglass --entrypoint open --env AGH_TARGET=w7:p1A"
# end to end: the pane gets that environment
AGH_TARGET=w7:p1A "$TEST_SH" "$ROOT/bin/ag-pane.sh" open < /dev/null 2>/dev/null
eq "… and the pane opens its session" "$(cat0 "$FAKE_DIR/open.log")" "open claude:S1 --new-instance"
eq "open-here leaves no state file (only the contract cache)" "$(ls "$HERDR_PLUGIN_STATE_DIR")" "contract"

reset_fakes
HERDR_PANE_ID='' act open-here
eq "open-here without a pane: the popup without a target" "$(cat0 "$FAKE_DIR/herdr.log")" "plugin pane open --plugin agentglass --entrypoint open"

reset_fakes
HERDR_PLUGIN_CLICKED_URL='agentglass://open/claude:S1#call=x' act open-link
eq "open-link passes the url" "$(cat0 "$FAKE_DIR/herdr.log")" "plugin pane open --plugin agentglass --entrypoint link --env AGH_URL=agentglass://open/claude:S1#call=x"
for bad in 'agentglass://open/$(rm -rf ~)' 'https://x' ''; do
  reset_fakes
  HERDR_PLUGIN_CLICKED_URL=$bad act open-link; rc=$?
  eq "open-link [$bad] opens no pane" "$(cat0 "$FAKE_DIR/herdr.log")" ""
  eq "open-link [$bad] exit 0" "$rc" "0"
done

reset_fakes
FAKE_HERDR_PANE_RC=1 act tui; rc=$?
eq "a refused popup (ui_busy) fails the action" "$rc" "1"

reset_fakes
HERDR_WORKSPACE_ID=w7 act workspace-cost
eq "workspace cost notification" "$(cat0 "$FAKE_DIR/herdr.log")" 'notification show agentglass --body feat-x: $12.82 today · $80.50 7 days'
reset_fakes
HERDR_WORKSPACE_ID=w2 act workspace-cost
eq "unpriced today" "$(cat0 "$FAKE_DIR/herdr.log")" 'notification show agentglass --body feat-y: ? today · $4.00 7 days'
reset_fakes
HERDR_WORKSPACE_ID=w5 act workspace-cost
eq "a workspace without cost" "$(cat0 "$FAKE_DIR/herdr.log")" 'notification show agentglass --body w5: no agent cost in the last 7 days'
reset_fakes
printf 'AGENTGLASS_REDACT=1\n' > "$HERDR_PLUGIN_CONFIG_DIR/config"
HERDR_WORKSPACE_ID=w7 act workspace-cost
eq "redact: the workspace by id" "$(cat0 "$FAKE_DIR/herdr.log")" 'notification show agentglass --body w7: $12.82 today · $80.50 7 days'
reset_fakes
cp "$FAKE_DIR/version-old.json" "$FAKE_DIR/version.json"
HERDR_WORKSPACE_ID=w7 act workspace-cost
has "contract < 1: said in a notification" "$(cat0 "$FAKE_DIR/herdr.log")" "notification show agentglass --body agentglass with CLI contract 1 needed"
done_test
