# agentglass-herdr — shared helpers, sourced by every entrypoint: find agentglass and herdr, check agentglass's CLI
# contract, plugin config, run lock, csv columns, fixed-width token values, the plugin log.
# agentglass is called only through its CLI contract (docs/cli-contract.md in the agentglass repo); herdr only through
# its documented CLI. POSIX sh, no jq.
# SPDX-License-Identifier: Apache-2.0
# shellcheck shell=sh disable=SC2034 # AG, HERDR, US, BLANK, WARN are used by the scripts that source this file

AGH_STATE=${HERDR_PLUGIN_STATE_DIR:-}
AGH_CONFIG=${HERDR_PLUGIN_CONFIG_DIR:-}
# the first agentglass release with CLI contract 1 (named at the plugin's first release; "" = not named)
AG_MIN_RELEASE=""
AG_CONTRACT_MIN=1
US=$(printf '\037')            # field separator of ag_csv_select (never in a value: control characters are dropped)
BLANK=$(printf '\342\240\200') # U+2800: blank, one column, and not trimmed by herdr (it trims Unicode whitespace)
WARN=$(printf '\342\232\240')  # U+26A0 ⚠

# the upgrade line (spec §13)
ag_upgrade_msg() {
  # shellcheck disable=SC2016 # the backticks are literal: a command for the user to run
  printf 'agentglass with CLI contract %s needed%s: run `agentglass update` or `brew upgrade agentglass`\n' \
    "$AG_CONTRACT_MIN" "${AG_MIN_RELEASE:+ (agentglass $AG_MIN_RELEASE or newer)}"
}

# ag_cfg KEY — the value of KEY=value in $HERDR_PLUGIN_CONFIG_DIR/config (last one wins, surrounding quotes dropped,
# never evaluated); empty when unset
ag_cfg() {
  if [ -z "$AGH_CONFIG" ] || [ ! -f "$AGH_CONFIG/config" ]; then return 0; fi
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$AGH_CONFIG/config" | tail -n 1 |
    sed "s/[[:space:]]*\$//; s/^\"\\(.*\\)\"\$/\\1/; s/^'\\(.*\\)'\$/\\1/"
}
ag_config_file() { printf '%s\n' "${AGH_CONFIG:-<plugin config dir>}/config"; }

# a truthy setting: 1, true, yes, on
ag_true() { case "$1" in 1|true|TRUE|True|yes|YES|on|ON) return 0 ;; *) return 1 ;; esac; }

# redact mode: AGENTGLASS_REDACT in the plugin config, or set (not 0) in the environment
ag_redact() {
  ag_true "$(ag_cfg AGENTGLASS_REDACT)" && return 0
  [ -n "${AGENTGLASS_REDACT-}" ] && [ "$AGENTGLASS_REDACT" != 0 ]
}

# ag_which NAME — the first executable NAME on PATH, else in the fallback dirs (a herdr server's PATH may lack them)
ag_which() {
  p=$(command -v "$1" 2>/dev/null || true)
  case "$p" in /*) [ -x "$p" ] && { printf '%s\n' "$p"; return 0; } ;; esac
  for d in ${AGH_SEARCH_DIRS-"$HOME/.local/bin" /opt/homebrew/bin /usr/local/bin /home/linuxbrew/.linuxbrew/bin}; do
    [ -x "$d/$1" ] && { printf '%s\n' "$d/$1"; return 0; }
  done
  return 1
}

# ag_find — sets AG (agentglass) and HERDR (herdr), each "" when not found.
# agentglass: AGENTGLASS_BIN in the plugin config, else PATH, else the fallback dirs. herdr: HERDR_BIN_PATH (herdr sets
# it for plugin commands), else PATH, else the fallback dirs.
ag_find() {
  AG=$(ag_cfg AGENTGLASS_BIN)
  [ -n "$AG" ] || AG=$(ag_which agentglass) || AG=""
  if [ -n "${HERDR_BIN_PATH-}" ] && [ -x "$HERDR_BIN_PATH" ]; then HERDR=$HERDR_BIN_PATH
  else HERDR=$(ag_which herdr) || HERDR=""; fi
}

# ag_socket — the herdr server for a command herdr did not start (the notify recipe): HERDR_SOCKET_PATH from the plugin
# config when the environment has none; else herdr's default socket
ag_socket() {
  [ -n "${HERDR_SOCKET_PATH-}" ] && return 0
  s=$(ag_cfg HERDR_SOCKET_PATH)
  if [ -n "$s" ]; then HERDR_SOCKET_PATH=$s; export HERDR_SOCKET_PATH; fi
  return 0
}

# ag_contract — agentglass's CLI contract number (0 when missing, or agentglass cannot run). Cached in the state dir by
# binary path + `ls -l` (size, mtime): an updated agentglass is asked again.
ag_contract() {
  if [ -z "$AG" ] || [ ! -x "$AG" ]; then echo 0; return 0; fi
  key="$AG|$(ls -lL "$AG" 2>/dev/null)"
  cache=${AGH_STATE:+$AGH_STATE/contract}
  if [ -n "$cache" ] && [ -f "$cache" ] && [ "$(sed -n 1p "$cache")" = "$key" ]; then
    sed -n 2p "$cache"; return 0
  fi
  if out=$(AGENTGLASS_AGENT=0 "$AG" --version --json 2>/dev/null); then
    n=$(printf '%s\n' "$out" | sed -n 's/.*"contract"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n 1)
    n=${n:-0}
    # only an answer is cached; a failed run is asked again next time
    if [ -n "$cache" ]; then printf '%s\n%s\n' "$key" "$n" > "$cache.$$" && mv -f "$cache.$$" "$cache"; fi
  else
    n=0
  fi
  echo "$n"
}

# ag_need — 0 when agentglass is there and speaks contract >= 1; else the reason on stderr and 1
ag_need() {
  if [ -z "$AG" ]; then
    echo "agentglass not found (PATH, ~/.local/bin, Homebrew): install it, or set AGENTGLASS_BIN in $(ag_config_file)" >&2
    ag_upgrade_msg >&2
    return 1
  fi
  if [ ! -x "$AG" ]; then echo "agentglass at $AG is not executable (AGENTGLASS_BIN in $(ag_config_file))" >&2; return 1; fi
  n=$(ag_contract)
  [ "$n" -ge "$AG_CONTRACT_MIN" ] 2>/dev/null && return 0
  ag_upgrade_msg >&2
  return 1
}

# ag_run ARGS — agentglass as the plugin runs it: never in agent mode (a popup is a human terminal; machine calls name
# --format), redacted when the plugin config says so
ag_run() {
  if ag_redact; then AGENTGLASS_AGENT=0 AGENTGLASS_REDACT=1 "$AG" "$@"
  else AGENTGLASS_AGENT=0 "$AG" "$@"; fi
}

# ag_popup ARGS — agentglass in a popup, then exit with its status. A failure (a link to a session that is gone: exit
# 3) keeps the popup open until Enter, so its message can be read; herdr closes the popup when this script exits.
ag_popup() {
  ag_run "$@"
  rc=$?
  if [ "$rc" -ne 0 ]; then ag_wait_key; fi
  exit "$rc"
}

# a herdr pane id (w7:p1A): letters, digits, colon, underscore, hyphen
ag_valid_pane() {
  [ -n "$1" ] || return 1
  case "$1" in *[!A-Za-z0-9:_-]*) return 1 ;; esac
}
# an agentglass deep link the plugin passes on: agentglass://open/ + [A-Za-z0-9._:%/#=&?-]+ (spec B3), nothing else
ag_valid_url() {
  case "$1" in agentglass://open/?*) ;; *) return 1 ;; esac
  case "${1#agentglass://open/}" in *[!A-Za-z0-9._:%/#=\&?-]*) return 1 ;; esac
}

# ag_log MSG — one line in the state dir's plugin.log (trimmed to the last 200 lines past 400)
ag_log() {
  [ -n "$AGH_STATE" ] || return 0
  f=$AGH_STATE/plugin.log
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >> "$f"
  if [ "$(wc -l < "$f")" -gt 400 ]; then tail -n 200 "$f" > "$f.$$" && mv -f "$f.$$" "$f"; fi
}
# ag_log_once KEY MSG — MSG only the first time for KEY (hooks say a missing agentglass once, not on every event)
ag_log_once() {
  [ -n "$AGH_STATE" ] || return 0
  [ -f "$AGH_STATE/said.$1" ] && return 0
  : > "$AGH_STATE/said.$1"
  ag_log "$2"
}

# ag_lock / ag_unlock — the run lock (mkdir is atomic). A lock 120 s old (a crashed run) is taken over; its age is the
# epoch second written into it (the dir's mtime when the stamp is missing).
ag_lock() {
  l=$AGH_STATE/run.lock
  if mkdir "$l" 2>/dev/null; then date +%s > "$l/at"; return 0; fi
  at=$(cat "$l/at" 2>/dev/null || true)
  case "$at" in
    ''|*[!0-9]*) [ -n "$(find "$l" -prune -mmin +2 2>/dev/null)" ] || return 1 ;;
    *) [ $(($(date +%s) - at)) -ge 120 ] || return 1 ;;
  esac
  rm -rf "$l"
  if mkdir "$l" 2>/dev/null; then date +%s > "$l/at"; ag_log "took over a stale run lock"; return 0; fi
  return 1
}
ag_unlock() { rm -rf "$AGH_STATE/run.lock"; }

# ag_csv_select NAME... — csv with a header line on stdin (RFC 4180: quoted fields, "" escapes, newlines inside quotes)
# → one line per row, the named columns joined by $US (a missing column is empty). agentglass's spreadsheet guard (a '
# before a leading = + - @) is undone; control characters become spaces.
ag_csv_select() {
  awk -v want="$*" -v sep="$US" -v q="'" '
    function parse(s, F,   i, c, n, v, inq, L) {
      n = 0; v = ""; inq = 0; L = length(s)
      for (i = 1; i <= L; i++) {
        c = substr(s, i, 1)
        if (inq) { if (c == "\"") { if (substr(s, i + 1, 1) == "\"") { v = v "\""; i++ } else inq = 0 } else v = v c }
        else if (c == "\"") inq = 1
        else if (c == ",") { F[++n] = v; v = "" }
        else v = v c
      }
      F[++n] = v
      return n
    }
    function clean(v) {
      if (substr(v, 1, 1) == q && index("=+-@", substr(v, 2, 1)) > 0) v = substr(v, 2)
      gsub(/[[:cntrl:]]/, " ", v)
      return v
    }
    BEGIN { nw = split(want, W, " ") }
    {
      sub(/\r$/, "")
      rec = (pend != "") ? pend "\n" $0 : $0
      t = rec
      if (gsub(/"/, "", t) % 2) { pend = rec; next }
      pend = ""
      nf = parse(rec, F)
      if (!hdr) { for (i = 1; i <= nf; i++) H[F[i]] = i; hdr = 1; next }
      out = ""
      for (j = 1; j <= nw; j++) out = out (j > 1 ? sep : "") ((W[j] in H) ? clean(F[H[W[j]]]) : "")
      print out
    }'
}

# ag_csv_field HEADER ROW NAME — one column of one csv row
ag_csv_field() { printf '%s\n%s\n' "$1" "$2" | ag_csv_select "$3"; }

# ag_fmt_cost USD — "$" + 6 columns, right-aligned: $  0.42, $ 12.40, $ 123.5, $  1.2k, $  1.5M; not a number
# (unpriced) → $     ?. Always 7 characters.
ag_fmt_cost() {
  awk -v v="$1" 'BEGIN {
    if (v !~ /^[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/) { printf "$%6s", "?"; exit }
    v += 0
    if (v < 99.995) s = sprintf("%.2f", v)
    else if (v < 999.95) s = sprintf("%.1f", v)
    else if (v < 99950) s = sprintf("%.1fk", v / 1e3)
    else if (v < 999500) s = sprintf("%.0fk", v / 1e3)
    else if (v < 99950000) s = sprintf("%.1fM", v / 1e6)
    else if (v < 999500000) s = sprintf("%.0fM", v / 1e6)
    else s = ">999M"
    printf "$%6s", s
  }'
}

# ag_fmt_alert REASON — 10 display columns: "⚠ " + the alert's rule id (lowercase [a-z0-9_-], at most 8; agentglass's
# "long cmd" → long-cmd) padded with U+2800; no reason → 10 × U+2800. Only a rule id, never free text.
ag_fmt_alert() {
  id=$(printf '%s' "$1" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ ' 'abcdefghijklmnopqrstuvwxyz-' | tr -cd 'a-z0-9_-' | cut -c 1-8)
  if [ -z "$id" ]; then out=""; n=10; else out="$WARN $id"; n=$((8 - ${#id})); fi
  while [ "$n" -gt 0 ]; do out="$out$BLANK"; n=$((n - 1)); done
  printf '%s' "$out"
}

# ag_seq — a strictly increasing number for herdr's --seq (epoch ms, or the last one + 1); call it under the run lock
ag_seq() {
  f=$AGH_STATE/seq
  now=$(($(date +%s) * 1000))
  last=$(cat "$f" 2>/dev/null || echo 0)
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  [ "$now" -gt "$last" ] || now=$((last + 1))
  echo "$now" > "$f"
  echo "$now"
}

# ag_wait_key — a popup that cannot start agentglass shows why, then waits for Enter (else it would close at once)
ag_wait_key() { printf '\npress Enter to close\n' >&2; read -r _ || true; }
