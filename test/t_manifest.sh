# the manifest declares what spec B2 lists, its version is the newest CHANGELOG version, and it binds no keys
# SPDX-License-Identifier: Apache-2.0
# shellcheck source=test/lib.sh disable=SC2016 # literal $ in expected values is the point
. "$ROOT/test/lib.sh"
m=$(grep -v '^#' "$ROOT/herdr-plugin.toml")
has "plugin id" "$m" 'id = "agentglass"'
has "min herdr" "$m" 'min_herdr_version = "0.7.5"'
has "platforms" "$m" 'platforms = ["linux", "macos"]'
for p in tui open link; do
  has "pane $p" "$m" "command = [\"/bin/sh\", \"bin/ag-pane.sh\", \"$p\"]"
done
for a in tui open-here workspace-cost open-link; do
  has "action $a" "$m" "command = [\"/bin/sh\", \"bin/ag-action.sh\", \"$a\"]"
done
for a in on off; do has "tokens-$a" "$m" "command = [\"/bin/sh\", \"bin/ag-tokens.sh\", \"$a\"]"; done
has "popup" "$m" 'placement = "popup"'
has "link handler" "$m" 'pattern = "^agentglass://open/"'
has "link action" "$m" 'action = "open-link"'
has "status event" "$m" 'on = "pane.agent_status_changed"'
has "detected event" "$m" 'on = "pane.agent_detected"'
has "startup" "$m" 'command = ["/bin/sh", "bin/ag-event.sh", "startup"]'
hasnt "no key bindings (Decision 30)" "$m" '[[keys'
# every command names a script that exists
missing=$(sed -n 's/^command = \["\/bin\/sh", "\(bin\/[a-z-]*\.sh\)".*/\1/p' "$ROOT/herdr-plugin.toml" | sort -u |
  while IFS= read -r f; do [ -f "$ROOT/$f" ] || echo "$f"; done)
eq "every script the manifest names exists" "$missing" ""
v=$(sed -n 's/^version = "\(.*\)"$/\1/p' "$ROOT/herdr-plugin.toml")
c=$(sed -n 's/^## \([0-9][0-9.]*\).*/\1/p' "$ROOT/CHANGELOG.md" | head -n 1)
eq "manifest version = newest CHANGELOG version" "$v" "$c"
done_test
