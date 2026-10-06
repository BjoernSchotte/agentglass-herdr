# numbers are formatted and parsed with a "." under any locale (the user's de_DE/fr_FR LC_NUMERIC used to give
# "$  5,79", and a workspace sum "$     ?")
# SPDX-License-Identifier: Apache-2.0
# shellcheck source=test/lib.sh disable=SC2016 # literal $ in expected values is the point
. "$ROOT/test/lib.sh"
# the decimal-comma locales installed here (whether this platform's awk honors them or not: the result must be "." either way)
avail=$(locale -a 2>/dev/null)
locs=""
for loc in de_DE.UTF-8 de_DE.utf8 fr_FR.UTF-8 fr_FR.utf8; do
  printf '%s\n' "$avail" | grep -qx "$loc" && locs="$locs $loc"
done
if [ -z "$locs" ]; then
  # CI installs de_DE and fr_FR; a developer machine without them says so instead of failing
  [ -n "${AGH_REQUIRE_LOCALES-}" ] && fail "no decimal-comma locale installed (de_DE.UTF-8, fr_FR.UTF-8)"
  echo "skip: no decimal-comma locale installed" >&2
  done_test
fi
for loc in $locs; do
  # shellcheck source=bin/ag-env.sh
  out=$(LC_ALL=$loc; export LC_ALL; . "$ROOT/bin/ag-env.sh"; printf '%s|%s|%s|%s' "$(ag_fmt_cost 5.79)" "$(ag_fmt_cost 12.82)" "$(ag_fmt_cost 1234)" "$(ag_fmt_cost 123.45)")
  eq "$loc: ag_fmt_cost" "$out" '$  5.79|$ 12.82|$  1.2k|$ 123.5'

  reset_fakes
  printf 'TOKENS_MIN_INTERVAL=0\n' > "$HERDR_PLUGIN_CONFIG_DIR/config"
  (LC_ALL=$loc; export LC_ALL; tsh "$ROOT/bin/ag-tokens.sh" on) 2>/dev/null
  r=$(grep report-metadata "$FAKE_DIR/herdr.log" || true)
  has "$loc: pane cost" "$r" 'pane report-metadata w7:p1A --source plugin:agentglass --token ag_cost=$  0.42'
  has "$loc: workspace sum" "$r" 'workspace report-metadata w7 --source plugin:agentglass --token ag_cost=$ 12.82'
  hasnt "$loc: no decimal comma" "$r" ','

  reset_fakes
  (LC_ALL=$loc; export LC_ALL; HERDR_WORKSPACE_ID=w7 tsh "$ROOT/bin/ag-action.sh" workspace-cost) 2>/dev/null
  eq "$loc: workspace cost notification" "$(cat0 "$FAKE_DIR/herdr.log")" 'notification show agentglass --body feat-x: $12.82 today · $80.50 7 days'
done
done_test
