# the plugin uses only agentglass's CLI contract: no reads of its data or cache files (Review Focus 7)
# SPDX-License-Identifier: Apache-2.0
# shellcheck source=test/lib.sh disable=SC2016 # literal $ in expected values is the point
. "$ROOT/test/lib.sh"
hits=$(grep -rn -e '\.agentglass/' -e 'AGENTGLASS_CACHE' -e 'AGENTGLASS_RUN_DIR' "$ROOT/bin" || true)
eq "no agentglass internals in bin/" "$hits" ""
# no jq, no node, no bash-only shebangs (Decision 19)
for f in "$ROOT"/bin/*.sh; do
  code=$(grep -v '^[[:space:]]*#' "$f")
  case "$(head -n 1 "$f")" in '#!'*bash*) fail "$f: bash shebang" ;; esac
  printf '%s\n' "$code" | grep -qw -e jq -e node -e python3 && fail "$f uses jq, node or python3"
done
done_test
