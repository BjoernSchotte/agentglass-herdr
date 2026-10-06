# test/contract.sh against the fake agentglass, and: bin/ requests no field contract.sh does not check
# SPDX-License-Identifier: Apache-2.0
# shellcheck source=test/lib.sh disable=SC2016 # literal $ in expected values is the point
. "$ROOT/test/lib.sh"
check() { (AGENTGLASS_BIN=$FAKE_BIN/agentglass tsh "$ROOT/test/contract.sh") > "$TMPDIR/contract.out" 2>&1; }

reset_fakes
check; eq "fake speaks contract 1" "$?" "0"
has "ok line" "$(cat0 "$TMPDIR/contract.out")" "contract: ok (agentglass 2026.10.6, contract 1)"

reset_fakes
cp "$FAKE_DIR/version-old.json" "$FAKE_DIR/version.json"
check; eq "no contract field fails" "$?" "1"
has "says why" "$(cat0 "$TMPDIR/contract.out")" "no contract >= 1"

reset_fakes
sed 's/"workspaceId",//' "$ROOT/test/fixtures/help.json" > "$FAKE_DIR/help.json"
check; eq "a field missing from the help fails" "$?" "1"
has "names it" "$(cat0 "$TMPDIR/contract.out")" "'cost' does not list field 'workspaceId'"

reset_fakes
sed 's/"mux",//' "$ROOT/test/fixtures/help.json" > "$FAKE_DIR/help.json"
check; eq "mux missing fails" "$?" "1"
has "flattened name checked by its object" "$(cat0 "$TMPDIR/contract.out")" "'--json' does not list field 'mux_kind'"

# every --fields list in bin/ is covered by contract.sh's lists
json_used=$(sed -n 's/^JSON_USED="\(.*\)"$/\1/p' "$ROOT/test/contract.sh")
cost_used=$(sed -n 's/^COST_USED="\(.*\)"$/\1/p' "$ROOT/test/contract.sh")
grep -ho -e '--fields [A-Za-z_,]*' "$ROOT"/bin/*.sh | sed 's/--fields //' | tr ',' '\n' | sort -u | while IFS= read -r f; do
  case " $json_used $cost_used " in *" $f "*) ;; *) fail "bin/ requests '$f', which test/contract.sh does not check" ;; esac
done
done_test
