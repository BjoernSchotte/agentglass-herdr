# bin/ag-pane.sh: the popup panes tui, open, link
# SPDX-License-Identifier: Apache-2.0
# shellcheck source=test/lib.sh disable=SC2016 # literal $ in expected values is the point
. "$ROOT/test/lib.sh"
pane() { tsh "$ROOT/bin/ag-pane.sh" "$@" < /dev/null 2>"$TMPDIR/err"; }

reset_fakes
pane tui
eq "tui starts the TUI, not in agent mode" "$(cat0 "$FAKE_DIR/open.log")" "tui AGENTGLASS_AGENT=0 AGENTGLASS_REDACT="

reset_fakes
(AGH_TARGET=w7:p1A pane open)
eq "open: the pane's session in a new instance" "$(cat0 "$FAKE_DIR/open.log")" "open claude:S1 --new-instance"
(AGH_TARGET=w7:p2 pane open)
has "open: a row with a quoted comma before the pane column" "$(cat0 "$FAKE_DIR/open.log")" "open codex:S2 --new-instance"

reset_fakes
(AGH_TARGET=w9:p9 pane open)
eq "open: no linked session → the TUI" "$(cat0 "$FAKE_DIR/open.log")" "tui AGENTGLASS_AGENT=0 AGENTGLASS_REDACT="
has "open: says why" "$(cat0 "$TMPDIR/err")" "no agentglass session is linked to herdr pane w9:p9"

reset_fakes
(AGH_TARGET='w7:p1A; rm -rf /' pane open)
eq "open: an invalid pane id is not looked up" "$(cat0 "$FAKE_DIR/ag.count")" ""
eq "open: … and gives the TUI" "$(cat0 "$FAKE_DIR/open.log")" "tui AGENTGLASS_AGENT=0 AGENTGLASS_REDACT="

reset_fakes
(AGH_TARGET=w7:p1A FAKE_AG_RC=1 pane open)
eq "open: --json fails → the TUI" "$(cat0 "$FAKE_DIR/open.log")" "tui AGENTGLASS_AGENT=0 AGENTGLASS_REDACT="

reset_fakes
(AGH_URL='agentglass://open/claude:S1#call=x' pane link)
eq "link: opened as given" "$(cat0 "$FAKE_DIR/open.log")" "open agentglass://open/claude:S1#call=x --new-instance"
for bad in 'agentglass://open/$(rm -rf ~)' 'https://x' 'agentglass://open/' 'agentglass://evil/claude:S1' 'agentglass://open/a b' "agentglass://open/a
b"; do
  reset_fakes
  (AGH_URL=$bad pane link); rc=$?
  eq "link: [$bad] refused" "$(cat0 "$FAKE_DIR/open.log")" ""
  eq "link: [$bad] exit 1" "$rc" "1"
done

# redact from the plugin config
reset_fakes
printf 'AGENTGLASS_REDACT=yes\n' > "$HERDR_PLUGIN_CONFIG_DIR/config"
pane tui
eq "redact reaches agentglass" "$(cat0 "$FAKE_DIR/open.log")" "tui AGENTGLASS_AGENT=0 AGENTGLASS_REDACT=1"

# contract < 1: every pane says so, waits for a key, starts nothing
for m in tui open link; do
  reset_fakes
  cp "$FAKE_DIR/version-old.json" "$FAKE_DIR/version.json"
  (AGH_TARGET=w7:p1A AGH_URL=agentglass://open/claude:S1 pane "$m"); rc=$?
  has "$m: contract message" "$(cat0 "$TMPDIR/err")" "contract 1"
  has "$m: waits for a key" "$(cat0 "$TMPDIR/err")" "press Enter"
  eq "$m: nothing started" "$(cat0 "$FAKE_DIR/open.log")" ""
  eq "$m: exit 1" "$rc" "1"
done

# agentglass missing
reset_fakes
(PATH=/usr/bin:/bin pane tui)
has "missing agentglass is named" "$(cat0 "$TMPDIR/err")" "agentglass not found"
done_test
