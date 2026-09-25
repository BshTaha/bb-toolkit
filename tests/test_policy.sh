#!/usr/bin/env bash
# Proves the request-policy layer added in 0.2.0. No network — pure logic:
#   - lib/bb-common.sh load_profile parses a profile and flags identity mandates
#   - require_profile and bb-scan REFUSE to send traffic without a policy
#   - the two fixed bugs stay fixed (regression guards)
set -uo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." || exit 1
chmod +x scripts/* 2>/dev/null || true
# shellcheck disable=SC1091
source ./env.sh >/dev/null 2>&1 || { echo "!! env.sh failed to source"; exit 1; }
# shellcheck disable=SC1091
. scripts/lib/bb-common.sh

pass=0; fail=0
ok(){ echo "  ok  : $1"; pass=$((pass+1)); }
no(){ echo "  FAIL: $1"; fail=$((fail+1)); }

# 1) load_profile parses rate/threads/UA and detects an identity mandate
tp="$TARGETS/_policytest"; mkdir -p "$tp/scope" "$tp/recon"
cat > "$tp/scope/profile.env" <<EOF
BB_UA="ua-marker -public-yeswehack"
BB_HEADER="HackerOne: handle"
BB_RATE=5
BB_THREADS=3
EOF
load_profile _policytest
[ "${RATE:-}" = 5 ]      && ok "load_profile RATE=5"            || no "RATE=${RATE:-unset}"
[ "${THREADS:-}" = 3 ]   && ok "load_profile THREADS=3"         || no "THREADS=${THREADS:-unset}"
[ "${#UA_ARGS[@]}" -eq 4 ] && ok "UA_ARGS carries UA + header"  || no "UA_ARGS count=${#UA_ARGS[@]}"
profile_mandates_identity && ok "identity mandate detected"     || no "identity mandate missed"

# 2) require_profile refuses when no profile exists
mkdir -p "$TARGETS/_noprof/scope" "$TARGETS/_noprof/recon"
if ( require_profile _noprof ) >/dev/null 2>&1; then no "require_profile accepted a missing policy"; else ok "require_profile refuses a missing policy"; fi

# 3) bb-scan refuses to scan without a profile (the compliance gate)
echo "https://example.com" > "$TARGETS/_noprof/recon/live.txt"
if bb-scan _noprof >/dev/null 2>&1; then no "bb-scan ran without a profile"; else ok "bb-scan refuses without a profile"; fi

# 4) regression: bb-secrets uses the fixed `bash -c` fetch and has no \${@:3} in CODE
if grep -qE 'xargs .*-n 1 bash -c' scripts/bb-secrets \
   && ! grep -vE '^[[:space:]]*#' scripts/bb-secrets | grep -q '{@:3}'; then
  ok "bb-secrets uses the fixed bash -c fetch (no \${@:3} in code)"
else
  no "bb-secrets fetch is not the fixed form"
fi

# 5) regression: bb-hunt INT/TERM trap must exit, not just clean the lock
if grep -qE "exit 130' INT TERM" scripts/bb-hunt; then ok "bb-hunt INT/TERM trap exits (130)"; else no "bb-hunt INT/TERM trap does not exit"; fi

rm -rf "$tp" "$TARGETS/_noprof"
echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
