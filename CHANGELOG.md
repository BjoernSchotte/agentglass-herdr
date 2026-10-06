# Changelog

All notable changes to agentglass-herdr. Versions follow semver. The plugin needs agentglass with CLI contract 1.

## 0.1.0 — unreleased

### Features

- `agentglass.tui`: the agentglass TUI in a popup (90 % × 90 %), never in agent mode, redacted when the plugin config
  says so.
- `agentglass.open-here`: the focused pane's agent session in agentglass (`agentglass open <harness>:<id>
  --new-instance`), found through `--json --live` `mux_pane`; the session list with a note when none is linked.
- `agentglass://open/…` link handler: Ctrl-click opens the link in the popup; links are checked against a strict
  pattern twice.
- `agentglass.workspace-cost`: a herdr notification with the workspace's cost today and over 7 days.
- Opt-in sidebar tokens `$ag_cost` (7 characters) and `$ag_alert` (10 columns) per agent pane, `$ag_cost` per
  workspace: sent only when changed, coalesced under a lock, cleared when an agent leaves, re-sent after a herdr
  restart, no cost under redact.
- `bin/ag-alert.sh`: the `rules.json` notify recipe. It forwards only alerts herdr cannot see (`$ag_alert` for 10
  minutes; critical alerts become a herdr notification).
- A runtime check for CLI contract ≥ 1 (cached per agentglass binary), with an upgrade message in popups and
  notifications.

### Tests and CI

- Fakes for herdr and agentglass (the fake rejects fields outside CLI contract 1); tests under dash, bash, sh and
  bash --posix; shellcheck; a manifest check; `test/contract.sh` for a real agentglass; a release workflow that
  checks the manifest version against the tag.
