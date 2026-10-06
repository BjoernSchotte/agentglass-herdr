# agentglass-herdr tests — assertions, sourced by every test/t_*.sh (run.sh sets ROOT, FAKE_DIR, TEST_SH, the state dirs)
# SPDX-License-Identifier: Apache-2.0
# failures are counted in a file, so a check inside a subshell or a pipeline counts too
FAILS_FILE=$TMPDIR/fails.$$
: > "$FAILS_FILE"
fail() { printf '    not ok: %s\n' "$*" >&2; echo x >> "$FAILS_FILE"; }
eq() { [ "$2" = "$3" ] || fail "$1: expected [$3], got [$2]"; }
# the haystack in a message: one line, at most 300 characters
short() { printf '%s' "$1" | tr '\n' '|' | cut -c 1-300; }
has() { case "$2" in *"$3"*) ;; *) fail "$1: [$3] not in [$(short "$2")]" ;; esac; }
hasnt() { case "$2" in *"$3"*) fail "$1: [$3] must not be in [$(short "$2")]" ;; esac; }
# the contents of a file, "" when it does not exist
cat0() { cat "$1" 2>/dev/null || true; }
lines() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
# a fresh fake world between cases of one test file
reset_fakes() {
  rm -rf "$FAKE_DIR" "$HERDR_PLUGIN_STATE_DIR" "$HERDR_PLUGIN_CONFIG_DIR"
  mkdir -p "$FAKE_DIR" "$HERDR_PLUGIN_STATE_DIR" "$HERDR_PLUGIN_CONFIG_DIR"
  cp "$ROOT"/test/fixtures/* "$FAKE_DIR"/
}
# display columns of a token value: ⚠ (U+26A0) and the braille blank (U+2800) are one column each, the rest is ASCII
cols() { printf '%s' "$1" | sed "s/$(printf '\342\232\240')/W/g; s/$(printf '\342\240\200')/_/g" | wc -c | tr -d ' '; }
done_test() { [ ! -s "$FAILS_FILE" ]; exit $?; }
