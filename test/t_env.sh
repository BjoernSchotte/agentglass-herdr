# bin/ag-env.sh: finding binaries, the contract check and its cache, config, lock, csv, fixed-width values
# SPDX-License-Identifier: Apache-2.0
# shellcheck source=test/lib.sh disable=SC2016 # literal $ in expected values is the point
. "$ROOT/test/lib.sh"
# shellcheck source=bin/ag-env.sh
. "$ROOT/bin/ag-env.sh"

# ── finding binaries ──
ag_find
eq "agentglass from PATH" "$AG" "$FAKE_BIN/agentglass"
eq "herdr from HERDR_BIN_PATH" "$HERDR" "$FAKE_BIN/herdr"
printf 'AGENTGLASS_BIN=x\n' > "$HERDR_PLUGIN_CONFIG_DIR/config"
ag_find
eq "AGENTGLASS_BIN from the config" "$AG" "x"
printf '# a comment\nAGENTGLASS_BIN = "/opt/ag/agentglass"  \nHERDR_SOCKET_PATH=/s/herdr.sock\n' > "$HERDR_PLUGIN_CONFIG_DIR/config"
eq "quoted, spaced config value" "$(ag_cfg AGENTGLASS_BIN)" "/opt/ag/agentglass"
eq "unset config key" "$(ag_cfg NOPE)" ""
# shellcheck disable=SC2016 # the $(...) is the point: it must stay text
printf 'AGENTGLASS_BIN=$(touch %s/pwned)\n' "$FAKE_DIR" > "$HERDR_PLUGIN_CONFIG_DIR/config"
ag_find
[ -e "$FAKE_DIR/pwned" ] && fail "config values must never be evaluated"
rm -f "$HERDR_PLUGIN_CONFIG_DIR/config"
# missing everywhere: PATH without the fakes, empty fallback dirs
(PATH=/usr/bin:/bin; HERDR_BIN_PATH=""; ag_find; eq "no agentglass" "$AG" ""; eq "no herdr" "$HERDR" "")
# fallback dirs when PATH lacks agentglass
mkdir -p "$TMPDIR/fallback"; ln -s "$FAKE_BIN/agentglass" "$TMPDIR/fallback/agentglass"
(PATH=/usr/bin:/bin; AGH_SEARCH_DIRS="$TMPDIR/nothing $TMPDIR/fallback"; ag_find; eq "agentglass from a fallback dir" "$AG" "$TMPDIR/fallback/agentglass")

# ── contract ──
ag_find
eq "contract 1" "$(ag_contract)" "1"
ag_need 2>"$TMPDIR/err"; eq "ag_need with contract 1" "$?" "0"
eq "ag_need says nothing" "$(cat0 "$TMPDIR/err")" ""
# cached: the fake is not asked again (it fails now; the cache answers)
mv "$FAKE_DIR/version.json" "$FAKE_DIR/version.away"
eq "cached contract" "$(ag_contract)" "1"
mv "$FAKE_DIR/version.away" "$FAKE_DIR/version.json"
# an older agentglass (no contract field), at another path → asked, 0, upgrade line
reset_fakes
cp "$FAKE_DIR/version-old.json" "$FAKE_DIR/version.json"
mkdir -p "$TMPDIR/old"; cp "$ROOT/test/fake-agentglass.sh" "$TMPDIR/old/agentglass"; AG=$TMPDIR/old/agentglass
eq "no contract field → 0" "$(ag_contract)" "0"
ag_need 2>"$TMPDIR/err"; eq "ag_need without contract" "$?" "1"
has "upgrade line" "$(cat0 "$TMPDIR/err")" "contract 1"
has "upgrade hint" "$(cat0 "$TMPDIR/err")" "agentglass update"
has "names the first release with contract 1" "$(cat0 "$TMPDIR/err")" "(agentglass 2026.10.6 or newer)"
# the binary changes (update in place) → asked again
cp "$ROOT/test/fixtures/version.json" "$FAKE_DIR/version.json"; printf '\n# updated\n' >> "$AG"
eq "an updated binary is checked again" "$(ag_contract)" "1"
# missing agentglass
AG=""; ag_need 2>"$TMPDIR/err"; eq "ag_need without agentglass" "$?" "1"
has "not found" "$(cat0 "$TMPDIR/err")" "agentglass not found"
# agentglass that cannot answer: 0, not cached
reset_fakes; rm -f "$FAKE_DIR/version.json"; ag_find
eq "failing --version → 0" "$(ag_contract)" "0"
[ -f "$HERDR_PLUGIN_STATE_DIR/contract" ] && fail "a failed contract check must not be cached"

# ── redact, run ──
reset_fakes
ag_redact && fail "redact off by default"
printf 'AGENTGLASS_REDACT=1\n' > "$HERDR_PLUGIN_CONFIG_DIR/config"
ag_redact || fail "redact from the config"
ag_find
# shellcheck disable=SC2119 # the bare TUI start: no arguments
ag_run
has "ag_run passes AGENTGLASS_REDACT=1, AGENTGLASS_AGENT=0" "$(cat0 "$FAKE_DIR/open.log")" "tui AGENTGLASS_AGENT=0 AGENTGLASS_REDACT=1"
rm -f "$HERDR_PLUGIN_CONFIG_DIR/config"
(AGENTGLASS_REDACT=1; ag_redact) || fail "redact from the environment"
(AGENTGLASS_REDACT=0; ag_redact) && fail "AGENTGLASS_REDACT=0 is off"

# ── socket ──
(unset HERDR_SOCKET_PATH; printf 'HERDR_SOCKET_PATH=/cfg/herdr.sock\n' > "$HERDR_PLUGIN_CONFIG_DIR/config"; ag_socket; eq "socket from the config" "$HERDR_SOCKET_PATH" "/cfg/herdr.sock")
(HERDR_SOCKET_PATH=/env/herdr.sock; printf 'HERDR_SOCKET_PATH=/cfg/herdr.sock\n' > "$HERDR_PLUGIN_CONFIG_DIR/config"; ag_socket; eq "herdr's own socket wins" "$HERDR_SOCKET_PATH" "/env/herdr.sock")
rm -f "$HERDR_PLUGIN_CONFIG_DIR/config"

# ── lock ──
ag_lock || fail "first lock"
ag_lock && fail "second lock must fail"
echo $(($(date +%s) - 119)) > "$HERDR_PLUGIN_STATE_DIR/run.lock/at"
ag_lock && fail "a 119 s old lock is not taken"
echo $(($(date +%s) - 121)) > "$HERDR_PLUGIN_STATE_DIR/run.lock/at"
ag_lock || fail "a 121 s old lock is taken over"
has "takeover logged" "$(cat0 "$HERDR_PLUGIN_STATE_DIR/plugin.log")" "took over a stale run lock"
ag_unlock; [ -d "$HERDR_PLUGIN_STATE_DIR/run.lock" ] && fail "unlock removes the lock"
ag_lock || fail "lock after unlock"; ag_unlock

# ── csv ──
eq "plain field" "$(ag_csv_field 'a,b,c' '1,2,3' b)" "2"
eq "quoted comma" "$(ag_csv_field 'id,title,x' 'S1,"a,b",z' title)" "a,b"
eq "after a quoted comma" "$(ag_csv_field 'id,title,x' 'S1,"a,b",z' x)" "z"
eq "escaped quote" "$(ag_csv_field 'id,title' 'S1,"say ""hi"""' title)" 'say "hi"'
eq "missing column" "$(ag_csv_field 'a,b' '1,2' nope)" ""
eq "empty last field" "$(ag_csv_field 'a,b' '1,' b)" ""
eq "spreadsheet guard undone" "$(ag_csv_field 'a,b' "1,'-feat" b)" "-feat"
sel=$(printf 'id,title,pane\nS1,"two\nlines",w1:p1\nS2,x,\n' | ag_csv_select pane id title)
eq "multi-line quoted field, columns in asked order" "$sel" "w1:p1${US}S1${US}two lines
${US}S2${US}x"
sel=$(ag_csv_select mux_pane harness id < "$FAKE_DIR/live.csv" | sed -n 2p)
eq "fixture row 2" "$sel" "w7:p2${US}codex${US}S2"
# empty fields survive read with the separator as IFS
printf 'a,b,c\n,,z\n' | ag_csv_select a b c | { IFS=$US read -r a b c; eq "empty fields kept" "$a|$b|$c" "||z"; }

# ── fixed-width values ──
eq "cost 0.4" "$(ag_fmt_cost 0.4)" '$  0.40'
eq "cost 0.42" "$(ag_fmt_cost 0.42)" '$  0.42'
eq "cost 12.4" "$(ag_fmt_cost 12.4)" '$ 12.40'
eq "cost 99.994" "$(ag_fmt_cost 99.994)" '$ 99.99'
eq "cost 99.996" "$(ag_fmt_cost 99.996)" '$ 100.0'
eq "cost 123.45" "$(ag_fmt_cost 123.45)" '$ 123.5'
eq "cost 999.96" "$(ag_fmt_cost 999.96)" '$  1.0k'
eq "cost 1234" "$(ag_fmt_cost 1234)" '$  1.2k'
eq "cost 99949" "$(ag_fmt_cost 99949)" '$ 99.9k'
eq "cost 99950" "$(ag_fmt_cost 99950)" '$  100k'
eq "cost 1.5e6" "$(ag_fmt_cost 1500000)" '$  1.5M'
eq "cost 2e9" "$(ag_fmt_cost 2000000000)" '$ >999M'
eq "cost 0" "$(ag_fmt_cost 0)" '$  0.00'
eq "unpriced (-)" "$(ag_fmt_cost -)" '$     ?'
eq "unpriced (empty)" "$(ag_fmt_cost '')" '$     ?'
eq "negative" "$(ag_fmt_cost -3)" '$     ?'
for v in 0 0.004 9.999 10 99.99 100 999.9 1000 54321 123456 9999999 123456789 1e12 x ''; do
  eq "cost $v is 7 characters" "$(cols "$(ag_fmt_cost "$v")")" 7
done
B=$(printf '\342\240\200'); W=$(printf '\342\232\240')
eq "alert stalled" "$(ag_fmt_alert stalled)" "$W stalled$B"
eq "alert long cmd" "$(ag_fmt_alert 'long cmd')" "$W long-cmd"
eq "alert none" "$(ag_fmt_alert '')" "$B$B$B$B$B$B$B$B$B$B"
eq "alert free text is cut to an id" "$(ag_fmt_alert 'Acme Corp: secret!')" "$W acme-cor"
for r in stalled loop 'long cmd' spinning cost '' 'a very long custom rule'; do
  eq "alert '$r' is 10 columns" "$(cols "$(ag_fmt_alert "$r")")" 10
done

# ── seq ──
s1=$(ag_seq); s2=$(ag_seq)
[ "$s2" -gt "$s1" ] || fail "seq increases ($s1, $s2)"
done_test
