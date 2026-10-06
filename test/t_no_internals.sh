# the plugin uses only agentglass's CLI contract: no reads of its data or cache files (Review Focus 7)
# SPDX-License-Identifier: Apache-2.0
. "$ROOT/test/lib.sh"
hits=$(grep -rn -e '\.agentglass/' -e 'AGENTGLASS_CACHE' -e 'AGENTGLASS_RUN_DIR' "$ROOT/bin" || true)
eq "no agentglass internals in bin/" "$hits" ""
# no jq, no node, no bash-only shebangs (Decision 19)
hits=$(grep -rln -e '\bjq\b' -e '\bnode\b' -e '^#!.*bash' "$ROOT/bin" || true)
eq "no jq/node/bash in bin/" "$hits" ""
done_test
