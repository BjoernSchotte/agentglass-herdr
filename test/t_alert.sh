# bin/ag-alert.sh: the rules.json notify recipe
# SPDX-License-Identifier: Apache-2.0
# shellcheck source=test/lib.sh disable=SC2016 # literal $ in expected values is the point
. "$ROOT/test/lib.sh"
B=$(printf '\342\240\200'); W=$(printf '\342\232\240')
CFG=$HERDR_PLUGIN_CONFIG_DIR
# as agentglass runs it: no herdr plugin environment, a stripped one
alert() {
  (unset HERDR_PLUGIN_STATE_DIR HERDR_PLUGIN_CONFIG_DIR HERDR_BIN_PATH HERDR_SOCKET_PATH
   tsh "$ROOT/bin/ag-alert.sh" "$@" 2>"$TMPDIR/err")
}
# the fixture alert with other values
mk() { sed "s/\"rule\":\"stalled\"/\"rule\":\"$1\"/; s/\"severity\":\"degraded\"/\"severity\":\"$2\"/; s/\"state\":\"fire\"/\"state\":\"$3\"/; s/\"session\":\"S1\"/\"session\":\"$4\"/" "$FAKE_DIR/alert-stalled.json"; }

for r in approval waiting; do
  reset_fakes
  mk "$r" degraded fire S1 | alert "$CFG"
  eq "$r: nothing (herdr rings itself)" "$(cat0 "$FAKE_DIR/herdr.log")" ""
  eq "$r: agentglass not even asked" "$(cat0 "$FAKE_DIR/ag.count")" ""
done
for s in resolve deescalate; do
  reset_fakes
  mk stalled critical "$s" S1 | alert "$CFG"
  eq "state $s: nothing" "$(cat0 "$FAKE_DIR/herdr.log")" ""
done

reset_fakes
mk stalled degraded fire S1 | alert "$CFG"; rc=$?
eq "stalled degraded: the token, 10 minutes, no notification" "$(cat0 "$FAKE_DIR/herdr.log")" "pane report-metadata w7:p1A --source plugin:agentglass --token ag_alert=$W stalled$B --ttl-ms 600000"
eq "exit 0" "$rc" "0"

reset_fakes
mk loop critical escalate S1 | alert "$CFG"
eq "loop critical: token and notification" "$(cat0 "$FAKE_DIR/herdr.log")" "pane report-metadata w7:p1A --source plugin:agentglass --token ag_alert=$W loop$B$B$B$B --ttl-ms 600000
notification show agentglass --body loop · claude --sound request"

reset_fakes
mk long-cmd critical fire S5 | sed 's/"harness":"claude"/"harness":"gemini"/' | alert "$CFG"
has "long-cmd on the gemini pane" "$(cat0 "$FAKE_DIR/herdr.log")" "pane report-metadata w2:p1 --source plugin:agentglass --token ag_alert=$W long-cmd --ttl-ms 600000"
has "… notification" "$(cat0 "$FAKE_DIR/herdr.log")" "--body long-cmd · gemini --sound request"

for s in S3 S4 S9; do
  reset_fakes
  mk stalled critical fire "$s" | alert "$CFG"; rc=$?
  eq "session $s not in a herdr pane: nothing" "$(cat0 "$FAKE_DIR/herdr.log")" ""
  eq "session $s: exit 0" "$rc" "0"
done

# the harness must match too (the same id under another harness is another session)
reset_fakes
mk stalled critical fire S1 | sed 's/"harness":"claude"/"harness":"codex"/' | alert "$CFG"
eq "id matches, harness does not: nothing" "$(cat0 "$FAKE_DIR/herdr.log")" ""

# privacy: title, project and message never reach herdr
reset_fakes
mk stalled critical fire S1 | alert "$CFG"
for s in SECRET-TITLE secret-project /secret/path "no log activity"; do hasnt "no [$s]" "$(cat0 "$FAKE_DIR/herdr.log")" "$s"; done
# a title that pretends to be a field does not steer the script
reset_fakes
sed 's/"title":"SECRET-TITLE"/"title":"x\\",\\"rule\\":\\"approval"/' "$FAKE_DIR/alert-stalled.json" | alert "$CFG"
has "an injected rule in the title is ignored" "$(cat0 "$FAKE_DIR/herdr.log")" "--token ag_alert=$W stalled$B"

# the herdr server from the plugin config
reset_fakes
printf 'HERDR_SOCKET_PATH=/run/user/1/herdr-test.sock\n' > "$CFG/config"
mk stalled degraded fire S1 | alert "$CFG"
eq "HERDR_SOCKET_PATH from the config" "$(sort -u "$FAKE_DIR/herdr.env")" "/run/user/1/herdr-test.sock"
# herdr by path from the config (PATH without the fakes)
reset_fakes
printf 'HERDR_BIN=%s\nAGENTGLASS_BIN=%s\n' "$FAKE_BIN/herdr" "$FAKE_BIN/agentglass" > "$CFG/config"
mk stalled degraded fire S1 | (PATH=/usr/bin:/bin alert "$CFG")
has "binaries from the config" "$(cat0 "$FAKE_DIR/herdr.log")" "pane report-metadata w7:p1A"

# without the config dir argument: herdr plugin config-dir agentglass
reset_fakes
mkdir -p "$FAKE_DIR/pc"; printf 'HERDR_SOCKET_PATH=/from/config-dir.sock\n' > "$FAKE_DIR/pc/config"
mk stalled degraded fire S1 | (FAKE_HERDR_CONFIG_DIR="$FAKE_DIR/pc" alert)
has "config dir asked from herdr" "$(cat0 "$FAKE_DIR/herdr.log")" "plugin config-dir agentglass"
eq "… and used" "$(tail -n 1 "$FAKE_DIR/herdr.env")" "/from/config-dir.sock"

# agentglass too old: nothing sent
reset_fakes
cp "$FAKE_DIR/version-old.json" "$FAKE_DIR/version.json"
mk stalled critical fire S1 | alert "$CFG"; rc=$?
hasnt "old agentglass: no report" "$(cat0 "$FAKE_DIR/herdr.log")" "report-metadata"
eq "old agentglass: exit 1" "$rc" "1"
done_test
