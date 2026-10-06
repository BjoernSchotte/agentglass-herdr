#!/bin/sh
# agentglass-herdr — checks an agentglass binary against what the plugin uses of CLI contract 1:
# `--version --json` has contract >= 1; every field the plugin requests is listed in `--help --format json` for its
# command; the plugin's own calls run (exit 0) with a csv header of exactly the requested fields.
# Usage: AGENTGLASS_BIN=/path/to/agentglass sh test/contract.sh   (CI: the newest release; tests: the fake)
# SPDX-License-Identifier: Apache-2.0
set -u
AG=${AGENTGLASS_BIN:-$(command -v agentglass || true)}
if [ -z "$AG" ] || [ ! -x "$AG" ]; then echo "contract: agentglass not found (set AGENTGLASS_BIN)" >&2; exit 1; fi

# what bin/*.sh requests, per command (t_contract.sh checks that bin/ asks for nothing else)
JSON_USED="id harness mux_kind mux_pane costUsd stuck"
COST_USED="key workspaceId costUsd"

failed=0
bad() { echo "contract: $*" >&2; failed=1; }
# an isolated agentglass: its own HOME and data dirs, never the user's sessions or config
W=$(mktemp -d "${TMPDIR:-/tmp}/agh-contract.XXXXXX")
trap 'rm -rf "$W"' EXIT
trap 'exit 130' INT TERM HUP PIPE
mkdir -p "$W/home" "$W/run"; chmod 700 "$W/run"
ag() {
  env HOME="$W/home" AGENTGLASS_AGENT=0 AGENTGLASS_NOTIFY=0 AGENTGLASS_CACHE_DIR="$W/cache" AGENTGLASS_CONFIG="$W/config.json" \
    AGENTGLASS_RULES="$W/rules.json" AGENTGLASS_RUN_DIR="$W/run" "$AG" "$@"
}

v=$(ag --version --json) || bad "agentglass --version --json failed"
n=$(printf '%s\n' "$v" | sed -n 's/.*"contract"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n 1)
ver=$(printf '%s\n' "$v" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
[ "${n:-0}" -ge 1 ] 2>/dev/null || bad "--version --json has no contract >= 1 (agentglass ${ver:-?})"

# the fields of one command in the JSON help: the "fields":[…] array of its {"cmd":"…"} object
help=$(ag --help --format json) || bad "agentglass --help --format json failed"
fields_of() {
  printf '%s\n' "$help" | awk -v cmd="$1" '{
    n = split($0, parts, "{\"cmd\":")
    for (i = 2; i <= n; i++) {
      p = parts[i]
      if (index(p, "\"" cmd "\"") != 1) continue
      s = index(p, "\"fields\":["); if (!s) continue
      f = substr(p, s + 10); f = substr(f, 1, index(f, "]") - 1)
      gsub(/"/, "", f); gsub(/,/, " ", f); print f; exit
    }
  }'
}
# a csv name in the help: flattened names (mux_kind) are listed under their object (mux)
listed() { for x in $2; do [ "$x" = "$1" ] || [ "$x" = "${1%%_*}" ] && return 0; done; return 1; }
check_cmd() {
  have=$(fields_of "$1")
  [ -n "$have" ] || { bad "--help --format json lists no fields for '$1'"; return; }
  for f in $2; do listed "$f" "$have" || bad "'$1' does not list field '$f' (has: $have)"; done
}
check_cmd --json "$JSON_USED"
check_cmd cost "$COST_USED"
printf '%s\n' "$help" | grep -q '{"cmd":"open"' || bad "--help --format json has no 'open' command"

# the plugin's calls, as it makes them: exit 0, and every requested field in the csv header (an empty result may
# print no header at all)
call() {
  what=$1; used=$2; shift 2
  if ! out=$(ag "$@"); then bad "$what failed"; return; fi
  h=$(printf '%s\n' "$out" | head -n 1)
  [ -n "$h" ] || return 0
  for f in $used; do case ",$h," in *",$f,"*) ;; *) bad "$what: csv header '$h' lacks '$f'" ;; esac; done
}
call "--json --live --format csv" "$JSON_USED" --json --live --all-projects --fields "$(printf '%s' "$JSON_USED" | tr ' ' ',')" --format csv
for since in today 7d; do
  call "cost --since $since --by workspace" "$COST_USED" cost --since "$since" --by workspace --format csv --fields "$(printf '%s' "$COST_USED" | tr ' ' ',')"
done

[ "$failed" -eq 0 ] || exit 1
echo "contract: ok (agentglass ${ver:-?}, contract $n)"
