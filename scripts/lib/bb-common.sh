#!/usr/bin/env bash
# bb-common.sh — shared helpers for the bb-* toolkit.
#
#   . "$(dirname "${BASH_SOURCE[0]}")/lib/bb-common.sh"
#
# The point of this file is a SINGLE canonical request-policy path. Before it,
# the profile.env-sourcing + UA_ARGS block was copy-pasted into some scripts and
# missing from others (bb-scan, bb-recon, bb-takeover, bb-secrets), which is how
# those commands ended up sending traffic that ignored the program's rate/UA/
# header policy. Everything that speaks to a target should load its policy here.

: "${BB:=$HOME/bugbounty}"
: "${TARGETS:=$BB/targets}"

# say <msg> — timestamped status line (matches bb-hunt/bb-sevfirst style).
say() { printf '\n\033[1;36m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }

# need <tool>...  — abort unless every named binary is on PATH.
need() {
  local miss=() t
  for t in "$@"; do command -v "$t" >/dev/null 2>&1 || miss+=("$t"); done
  if [ "${#miss[@]}" -gt 0 ]; then
    echo "!! missing required tool(s): ${miss[*]}" >&2
    echo "   run 'source ~/bugbounty/env.sh' (or install them) and retry." >&2
    return 1
  fi
}

# load_profile <program>
# Reads targets/<program>/scope/profile.env and publishes the request policy as
# globals in the CALLING shell (this file is sourced, so they persist):
#   RATE, THREADS, DNS_RATE   — numeric caps (profile wins, else the caller's
#                               pre-set value, else a conservative default)
#   UA_ARGS                   — array of -H flags for any tool that speaks -H
#   BB_UA, BB_HEADER, BB_HEADER2 — exported for child processes
#   PROFILE_FOUND             — 1 if a profile.env existed, else 0
# Callers may pre-seed RATE/THREADS/DNS_RATE before calling to set their own
# fallback; anything the profile specifies overrides it.
load_profile() {
  local prog="$1" pf _h
  pf="$TARGETS/$prog/scope/profile.env"
  UA_ARGS=()
  PROFILE_FOUND=0
  RATE="${RATE:-100}"; THREADS="${THREADS:-15}"; DNS_RATE="${DNS_RATE:-120}"
  if [ -s "$pf" ]; then
    PROFILE_FOUND=1
    # shellcheck disable=SC1090
    . "$pf"
    [ -n "${BB_RATE:-}" ]     && RATE="$BB_RATE"
    [ -n "${BB_THREADS:-}" ]  && THREADS="$BB_THREADS"
    [ -n "${BB_DNS_RATE:-}" ] && DNS_RATE="$BB_DNS_RATE"
    [ -n "${BB_UA:-}" ]       && UA_ARGS+=(-H "User-Agent: $BB_UA")
    for _h in "${BB_HEADER:-}" "${BB_HEADER2:-}"; do
      [ -n "$_h" ] && UA_ARGS+=(-H "$_h")
    done
    export BB_UA BB_HEADER BB_HEADER2
  fi
  return 0
}

# require_profile <program> — load_profile, but REFUSE to continue when no
# profile exists. Use this for tools that generate real HTTP traffic against the
# target (nuclei, active fuzzers), where "we don't know the program's cap" must
# mean "don't send traffic", not "guess a rate".
require_profile() {
  load_profile "$1"
  if [ "$PROFILE_FOUND" != 1 ]; then
    echo "!! no request policy for '$1'." >&2
    echo "   $TARGETS/$1/scope/profile.env is missing." >&2
    echo "   Create it from the program page first:  bb-profile $1 init" >&2
    echo "   Refusing to send traffic without a rate/UA policy." >&2
    return 1
  fi
  return 0
}

# has_marker — 1 if the profile mandates an identifying UA or header. Tools that
# cannot send a custom UA/header (e.g. subzy) should skip when this is true.
profile_mandates_identity() {
  [ -n "${BB_UA:-}" ] || [ -n "${BB_HEADER:-}" ] || [ -n "${BB_HEADER2:-}" ]
}

# scope_filter <program> <file> — drop out-of-scope entries from <file> in place.
# Fixes the old "grep exit 1 when everything matches leaves the file unfiltered"
# bug by distinguishing grep's rc=1 (nothing kept, valid) from rc>=2 (real error).
scope_filter() {
  local prog="$1" f="$2" oos before after rc
  oos="$TARGETS/$prog/scope/out-of-scope.txt"
  [ -s "$f" ]   || return 0
  [ -s "$oos" ] || return 0
  before=$(wc -l < "$f")
  grep -vEf <(grep -vE '^[[:space:]]*(#|$)' "$oos") "$f" > "$f.tmp" 2>/dev/null
  rc=$?
  if [ "$rc" -le 1 ]; then
    mv "$f.tmp" "$f"                      # rc 0 = some kept, rc 1 = all were OOS
  else
    rm -f "$f.tmp"                        # rc >=2 = grep error: leave file intact
    echo "    [scope] filter error (rc=$rc) on $(basename "$f") — left unchanged" >&2
    return 0
  fi
  after=$(wc -l < "$f")
  [ "$before" -ne "$after" ] && echo "    scope filter: dropped $((before-after)) out-of-scope entries"
  return 0
}
