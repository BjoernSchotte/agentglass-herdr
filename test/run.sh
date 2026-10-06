#!/bin/sh
# agentglass-herdr tests — runs every test/t_*.sh under each POSIX shell found (dash, bash, sh) with the fakes on PATH:
# never a real herdr or agentglass. Usage: sh test/run.sh [t_name ...]
# SPDX-License-Identifier: Apache-2.0
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/agh-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM
FAKE_BIN=$WORK/bin
mkdir -p "$FAKE_BIN"
ln -s "$ROOT/test/fake-herdr.sh" "$FAKE_BIN/herdr"
ln -s "$ROOT/test/fake-agentglass.sh" "$FAKE_BIN/agentglass"
# bash-posix = bash --posix (closer to macOS /bin/sh, which is bash 3.2 in POSIX mode)
shells=""
for s in dash bash sh; do command -v "$s" >/dev/null 2>&1 && shells="$shells $s"; done
command -v bash >/dev/null 2>&1 && shells="$shells bash-posix"
if [ $# -gt 0 ]; then tests=""; for t in "$@"; do tests="$tests $ROOT/test/${t%.sh}.sh"; done
else tests=$(ls "$ROOT"/test/t_*.sh); fi
failed=0
for t in $tests; do
  name=$(basename "$t" .sh)
  for s in $shells; do
    d=$WORK/$name-$s
    mkdir -p "$d/fake" "$d/state" "$d/config" "$d/home" "$d/empty"
    cp "$ROOT"/test/fixtures/* "$d/fake/"
    sh_cmd=$s; [ "$s" = bash-posix ] && sh_cmd="bash --posix"
    # shellcheck disable=SC2086 # sh_cmd is "bash --posix" on purpose
    if env -i PATH="$FAKE_BIN:/usr/bin:/bin" HOME="$d/home" TMPDIR="$d" LC_ALL=C \
         ROOT="$ROOT" TEST_SH="$sh_cmd" FAKE_DIR="$d/fake" FAKE_BIN="$FAKE_BIN" \
         HERDR_PLUGIN_STATE_DIR="$d/state" HERDR_PLUGIN_CONFIG_DIR="$d/config" HERDR_BIN_PATH="$FAKE_BIN/herdr" \
         AGH_SEARCH_DIRS="$d/empty" \
         $sh_cmd "$t" > "$d/out" 2>&1; then
      echo "ok   $name ($s)"
    else
      echo "FAIL $name ($s)"; sed 's/^/    /' "$d/out"; failed=1
    fi
  done
done
exit $failed
