#!/usr/bin/env bash
# Scripted demo for the README recording. Every command shown is really run,
# against tests/vulnserver.py on localhost — no real target, no network.
#
#   asciinema rec -c "bash tests/demo.sh" demo.cast
set -uo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
export BB="$(mktemp -d)"; export TARGETS="$BB/targets"
export PATH="$REPO/scripts:$PATH"
trap 'rm -rf "$BB"; kill %1 2>/dev/null' EXIT

G=$'\033[1;32m'; D=$'\033[2m'; C=$'\033[1;36m'; Y=$'\033[1;33m'; X=$'\033[0m'

say()  { printf '%s%s%s\n' "$D" "$1" "$X"; sleep 1.1; }
cmd()  { printf '%s$%s ' "$G" "$X"
         for ((i=0; i<${#1}; i++)); do printf '%s' "${1:i:1}"; sleep 0.018; done
         printf '\n'; sleep 0.35; }
pause(){ sleep "${1:-1.2}"; }

clear
say "# A server that returns HTTP 200 for every path — a SPA fallback, say."
cmd "python3 tests/vulnserver.py --port 8000 &"
python3 -u "$REPO/tests/vulnserver.py" --port 8000 >"$BB/vs.log" 2>&1 &
sleep 1.2; head -4 "$BB/vs.log"
pause 1.0

printf '\n'
say "# These files do not exist. Watch what a scanner sees anyway:"
cmd "curl -s -o /dev/null -w '%{http_code}  %{size_download}B\\n' localhost:8000/.git/config"
curl -s -o /dev/null -w '%{http_code}  %{size_download}B\n' localhost:8000/.git/config
pause 0.8
cmd "curl -s localhost:8000/.git/config | grep -o '\\[core\\]'"
curl -s localhost:8000/.git/config | grep -o '\[core\]'
pause 1.0

printf '\n'
say "# HTTP 200 and the signature matches. Same for .git/HEAD, .aws/credentials,"
say "# phpinfo.php, actuator/heapdump. Five 'critical exposures'. All fiction."
pause 1.4

printf '\n'
say "# bb-verify checks length against a random-path baseline first:"
bb-new demo >/dev/null 2>&1
echo "http://127.0.0.1:8000" > "$TARGETS/demo/recon/live.txt"
cmd "bb-verify demo --checks files"
bb-verify demo --checks files --threads 4
pause 1.6

printf '\n'
say "# One finding, not six. The five soft-404s were rejected —"
say "# and the one genuinely exposed file was still caught:"
cmd "bb-triage demo && bb-findings demo --full"
bb-triage demo >/dev/null 2>&1
bb-findings demo --full
pause 3.0
