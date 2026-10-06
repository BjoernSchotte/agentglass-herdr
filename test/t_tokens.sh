# bin/ag-tokens.sh + bin/ag-event.sh: opt-in, fixed widths, only on change, lock + dirty coalescing, workspace sums,
# redact, privacy, off clears
# SPDX-License-Identifier: Apache-2.0
# shellcheck source=test/lib.sh disable=SC2016 # literal $ in expected values is the point
. "$ROOT/test/lib.sh"
tok() { tsh "$ROOT/bin/ag-tokens.sh" "$@" 2>>"$TMPDIR/err"; }
event() { tsh "$ROOT/bin/ag-event.sh" "$@" 2>>"$TMPDIR/err"; }
reports() { grep 'report-metadata' "$FAKE_DIR/herdr.log" 2>/dev/null || true; }
B=$(printf '\342\240\200'); W=$(printf '\342\232\240')

# off by default: an event does nothing, not even run agentglass
reset_fakes
event; event startup
eq "flag off: agentglass not run" "$(cat0 "$FAKE_DIR/ag.count")" ""
eq "flag off: herdr not called" "$(cat0 "$FAKE_DIR/herdr.log")" ""

# on: one run, a report per herdr pane and workspace, fixed widths
reset_fakes
tok on
eq "on: one agentglass run" "$(cat0 "$FAKE_DIR/ag.count")" "1"
r=$(reports)
has "pane w7:p1A" "$r" "pane report-metadata w7:p1A --source plugin:agentglass --token ag_cost=\$  0.42 --token ag_alert=$W stalled$B --seq "
has "pane w7:p2 (no alert: 10 blanks)" "$r" "pane report-metadata w7:p2 --source plugin:agentglass --token ag_cost=\$ 12.40 --token ag_alert=$B$B$B$B$B$B$B$B$B$B --seq "
has "pane w2:p1 (unpriced, long cmd)" "$r" "pane report-metadata w2:p1 --source plugin:agentglass --token ag_cost=\$     ? --token ag_alert=$W long-cmd --seq "
has "workspace w7 = sum of its panes" "$r" "workspace report-metadata w7 --source plugin:agentglass --token ag_cost=\$ 12.82 --seq "
has "workspace w2 unpriced" "$r" "workspace report-metadata w2 --source plugin:agentglass --token ag_cost=\$     ? --seq "
hasnt "no tmux pane" "$r" "work:1.0"
eq "5 reports (3 panes, 2 workspaces)" "$(printf '%s\n' "$r" | grep -c .)" "5"
has "on: a notification with the setup hint" "$(cat0 "$FAKE_DIR/herdr.log")" "notification show agentglass --body sidebar tokens on"
# every value has its fixed width
printf '%s\n' "$r" | sed -n 's/.*--token ag_cost=\(.*\) --token ag_alert=.*/\1/p; s/^workspace.*--token ag_cost=\(.*\) --seq.*/\1/p' | while IFS= read -r v; do
  eq "ag_cost [$v] is 7 columns" "$(cols "$v")" 7
done
printf '%s\n' "$r" | sed -n 's/.*--token ag_alert=\(.*\) --seq.*/\1/p' | while IFS= read -r v; do
  eq "ag_alert [$v] is 10 columns" "$(cols "$v")" 10
done
# privacy: titles and paths from the csv never reach herdr
hasnt "no title" "$(cat0 "$FAKE_DIR/herdr.log")" "SECRET-TITLE"
hasnt "no path" "$(cat0 "$FAKE_DIR/herdr.log")" "/secret/path"
hasnt "no project text" "$(cat0 "$FAKE_DIR/herdr.log")" "shop"

# the same csv again: no report
: > "$FAKE_DIR/herdr.log"
event
eq "unchanged: agentglass ran" "$(cat0 "$FAKE_DIR/ag.count")" "2"
eq "unchanged: no report" "$(reports)" ""

# one value changes: only that pane (and its workspace sum) is reported, with a larger --seq
seq1=$(cat "$HERDR_PLUGIN_STATE_DIR/seq")
sed 's/^S1,claude,Fix the login form,\/home\/dev\/shop,true,101,busy,0.42,false,stalled/S1,claude,Fix the login form,\/home\/dev\/shop,true,101,busy,0.52,false,/' "$ROOT/test/fixtures/live.csv" > "$FAKE_DIR/live.csv"
event
r=$(reports)
has "changed pane, both tokens changed" "$r" "pane report-metadata w7:p1A --source plugin:agentglass --token ag_cost=\$  0.52 --token ag_alert=$B$B$B$B$B$B$B$B$B$B --seq"
has "its workspace" "$r" "workspace report-metadata w7 --source plugin:agentglass --token ag_cost=\$ 12.92"
eq "only the changed ones" "$(printf '%s\n' "$r" | grep -c .)" "2"
seq2=$(cat "$HERDR_PLUGIN_STATE_DIR/seq")
[ "$seq2" -gt "$seq1" ] || fail "--seq increases ($seq1 → $seq2)"

# an agent leaves its herdr pane: its tokens are cleared, its workspace too when it was the last one
: > "$FAKE_DIR/herdr.log"
grep -v '^S5,' "$FAKE_DIR/live.csv" > "$FAKE_DIR/live2.csv"; mv "$FAKE_DIR/live2.csv" "$FAKE_DIR/live.csv"
event
r=$(reports)
has "gone pane cleared" "$r" "pane report-metadata w2:p1 --source plugin:agentglass --clear-token ag_cost --clear-token ag_alert"
has "empty workspace cleared" "$r" "workspace report-metadata w2 --source plugin:agentglass --clear-token ag_cost --clear-token ag_alert"

# herdr refuses a report: the old values stay, so the next run tries again
reset_fakes
tok on
cp "$ROOT/test/fixtures/live.csv" "$FAKE_DIR/live.csv"
sed 's/,0.42,/,0.62,/' "$ROOT/test/fixtures/live.csv" > "$FAKE_DIR/live.csv"
: > "$FAKE_DIR/herdr.log"
(FAKE_HERDR_REPORT_RC=1 event)
has "failure logged" "$(cat0 "$HERDR_PLUGIN_STATE_DIR/plugin.log")" "report-metadata w7:p1A failed"
: > "$FAKE_DIR/herdr.log"
event
has "retried after a failure" "$(reports)" "w7:p1A --source plugin:agentglass --token ag_cost=\$  0.62 --seq"

# agentglass fails: nothing is reported or cleared
: > "$FAKE_DIR/herdr.log"
(FAKE_AG_RC=1 event)
eq "agentglass failure: no herdr call" "$(cat0 "$FAKE_DIR/herdr.log")" ""

# startup forgets the last values (a new herdr server has no metadata): everything again
: > "$FAKE_DIR/herdr.log"
event startup
eq "startup reports all again" "$(reports | grep -c .)" "5"

# startup after an agent left: its pane is still cleared (forgetting keeps which panes have tokens)
: > "$FAKE_DIR/herdr.log"
grep -v '^S2,' "$FAKE_DIR/live.csv" > "$FAKE_DIR/live2.csv"; mv "$FAKE_DIR/live2.csv" "$FAKE_DIR/live.csv"
event startup
r=$(reports)
has "startup: a pane left meanwhile is cleared" "$r" "pane report-metadata w7:p2 --source plugin:agentglass --clear-token ag_cost --clear-token ag_alert"
has "startup: the others are sent again" "$r" "pane report-metadata w7:p1A --source plugin:agentglass --token ag_cost="

# coalescing: two events during a run → exactly one more run
reset_fakes
tok on
n0=$(cat "$FAKE_DIR/ag.count")
(FAKE_AG_SLEEP=2 event) & p1=$!
sleep 1
(FAKE_AG_SLEEP=2 event) & p2=$!
(FAKE_AG_SLEEP=2 event) & p3=$!
wait "$p1" "$p2" "$p3"
eq "two events during a run → 2 runs in total" "$(($(cat "$FAKE_DIR/ag.count") - n0))" "2"
[ -d "$HERDR_PLUGIN_STATE_DIR/run.lock" ] && fail "the lock is released"
[ -f "$HERDR_PLUGIN_STATE_DIR/dirty" ] && fail "dirty is consumed"

# a stale lock (crashed run) is taken over
reset_fakes
tok on
mkdir "$HERDR_PLUGIN_STATE_DIR/run.lock"; echo $(($(date +%s) - 300)) > "$HERDR_PLUGIN_STATE_DIR/run.lock/at"
event startup
eq "stale lock taken over" "$(cat "$FAKE_DIR/ag.count")" "2"

# redact: no ag_cost anywhere; switching redact on clears the ag_cost already set
reset_fakes
printf 'AGENTGLASS_REDACT=1\n' > "$HERDR_PLUGIN_CONFIG_DIR/config"
tok on
r=$(reports)
hasnt "redact: no ag_cost" "$r" "ag_cost="
has "redact: alerts still" "$r" "pane report-metadata w7:p1A --source plugin:agentglass --token ag_alert=$W stalled$B"
hasnt "redact: no workspace report" "$r" "workspace report-metadata"
reset_fakes
tok on
printf 'AGENTGLASS_REDACT=1\n' > "$HERDR_PLUGIN_CONFIG_DIR/config"
: > "$FAKE_DIR/herdr.log"
event
r=$(reports)
has "redact switched on: pane ag_cost cleared" "$r" "pane report-metadata w7:p1A --source plugin:agentglass --clear-token ag_cost --seq"
has "redact switched on: workspace ag_cost cleared" "$r" "workspace report-metadata w7 --source plugin:agentglass --clear-token ag_cost --seq"

# off: clears every token set, removes the flag; events do nothing afterwards
reset_fakes
tok on
: > "$FAKE_DIR/herdr.log"
tok off
r=$(reports)
for id in "pane report-metadata w7:p1A" "pane report-metadata w7:p2" "pane report-metadata w2:p1" "workspace report-metadata w7" "workspace report-metadata w2"; do
  has "off clears $id" "$r" "$id --source plugin:agentglass --clear-token ag_cost --clear-token ag_alert"
done
[ -f "$HERDR_PLUGIN_STATE_DIR/tokens.on" ] && fail "off removes the flag"
n=$(cat "$FAKE_DIR/ag.count"); event
eq "after off: no run" "$(cat "$FAKE_DIR/ag.count")" "$n"

# on with agentglass < contract 1: refused with a notification, flag stays off
reset_fakes
cp "$FAKE_DIR/version-old.json" "$FAKE_DIR/version.json"
tok on
has "on refused" "$(cat0 "$FAKE_DIR/herdr.log")" "notification show agentglass --body agentglass with CLI contract 1 needed"
[ -f "$HERDR_PLUGIN_STATE_DIR/tokens.on" ] && fail "flag stays off"
# hooks with an old agentglass (upgraded away later): silent, logged once
reset_fakes
: > "$HERDR_PLUGIN_STATE_DIR/tokens.on"
cp "$FAKE_DIR/version-old.json" "$FAKE_DIR/version.json"
event; event
eq "old agentglass: no herdr call" "$(reports)" ""
eq "said once" "$(grep -c 'contract 1' "$HERDR_PLUGIN_STATE_DIR/plugin.log")" "1"
done_test
