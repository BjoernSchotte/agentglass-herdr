# Security policy

## Supported versions

Only the latest release gets security fixes; see
[Releases](https://github.com/BjoernSchotte/agentglass-herdr/releases/latest). Update before you report.

## Report a vulnerability

Do not open a public issue. Report privately through GitHub:
[Report a vulnerability](https://github.com/BjoernSchotte/agentglass-herdr/security/advisories/new).

Include:

- the plugin version (`version` in `herdr-plugin.toml`), the herdr and agentglass versions, and the OS;
- what you did, what happened, and what an attacker gains;
- a minimal reproduction, if you have one.

You get a reply within 7 days. A confirmed issue is fixed in a new release, then the advisory is published with credit,
unless you ask to stay anonymous.

## Scope

In scope: the plugin manifest and the scripts in `bin/`. Examples: shell injection through pane titles, session ids or
`agentglass://` links, and writes outside the plugin's own state.

Out of scope: vulnerabilities in herdr or agentglass themselves. Report agentglass issues at
[agentglass](https://github.com/BjoernSchotte/agentglass/security/advisories/new) and herdr issues upstream.
