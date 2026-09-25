# Changelog

## [0.2.0] — 2026-09-25

A compliance and correctness pass. The commands that generate traffic now take
their rate, User-Agent and mandated headers from the program's `profile.env`
through one shared loader instead of hardcoding them — closing the gap where a
few of the most-used commands ignored the very policy the toolkit exists to
enforce. Plus the first test harness and CI.

### Added
- `scripts/lib/bb-common.sh` — one shared request-policy path: `load_profile` /
  `require_profile`, `profile_mandates_identity`, `need`, `say`, and a corrected
  `scope_filter`. `bb-scan`, `bb-recon`, `bb-takeover` and `bb-secrets` source
  it, so the safety-sensitive logic can no longer drift per script.
- `tests/` — a local harness, stdlib only, no network. `test_verify.py` proves
  `bb-verify` reports the one real flaw on a soft-404 `vulnserver.py` and rejects
  all five traps a naive status+signature scanner fires on. `test_policy.sh`
  proves the loader parses a profile, that `require_profile` and `bb-scan` refuse
  to run without one, and guards the two fixed bugs below against regression.
- CI runs shellcheck, `py_compile`, and both test suites on every push.

### Fixed
- `bb-scan`: refuses without a `profile.env`, and drives `-rl` / `-c` / UA /
  header from it instead of a hardcoded 100 req/s and the default User-Agent.
- `bb-recon`: HTTP probing honours the profile (rate / UA); the top-1000 `naabu`
  port scan is now OFF by default (`--ports` or `BB_ALLOW_PORTSCAN=1`); and
  out-of-scope filtering is applied to subdomains, resolved hosts and live hosts.
- `bb-takeover`: skips `subzy` when the program mandates an identifying UA or
  header (subzy cannot send one) and covers takeovers via the profile-driven
  nuclei templates instead; nuclei's rate / UA now come from the profile.
- `bb-secrets`: JS fetches carry the program's UA and mandated headers, and the
  run aborts loudly if nothing downloaded instead of reporting success over an
  empty directory.
- `bb-hunt`: exports `BB_UA`, so `bb-verify` and `bb-secrets` send the mandated
  UA and not just bb-hunt's own tool calls; and the INT/TERM trap now exits, so
  Ctrl-C stops a `--loop` hunt instead of removing the lock and continuing to
  send traffic unattended.
- `bb-verify`: standalone runs load the program's `profile.env`, sending the
  mandated UA / header and deriving a politeness delay from the rate cap —
  matching what it already did when launched by `bb-hunt`.

### Verified
- The `bb-verify` assertions were checked by mutation: deleting the soft-404
  length guard produces 6 findings instead of 1 (2 tests fail); making the CORS
  check ignore `Access-Control-Allow-Credentials` produces 2 instead of 1.

## [0.1.0] — 2026-09-15

First public release. Extracted from a private toolkit built over 2026-09-14/15
and used against live HackerOne programs.

### Pipeline
- `bb-hunt` orchestrator: full sweep on cycle 1, new-asset-only delta cycles,
  full re-sweep every *n* cycles, PID locking, `--loop`.
- `bb-verify`: active proof of redirect / CORS / exposed-file / takeover
  candidates, with a soft-404 baseline guard.
- `bb-triage`: normalizes every scanner output into one deduped, severity-scored
  `findings.jsonl`; drops ~40 known-noise template classes.
- `bb-report`: Discord embeds, `sent.db` dedupe, 429 `retry_after` handling.
- `bb-profile`: per-program UA/rate policy, provable against a local listener.
- `bb-brute`: keyless DNS bruteforce + alterx permutations.
- `bb-sevfirst`: severity-first sweep for hard per-host request budgets.
- `bb-keys`: tiered API key management with direct live validation.

### Notes from building it
- `gf` ignores `$GF_PATH` and only reads `~/.gf` — the installer symlinks it.
- `alterx` ignores `-l` whenever stdin is a pipe — it silently discards the file
  when stdin has data, and blocks forever when stdin is open but empty, which is
  what it inherits inside a script. `bb-brute` redirects `</dev/null` so `-l`
  takes effect. Reported upstream as
  [alterx#296](https://github.com/projectdiscovery/alterx/issues/296).
- `subzy` moved from `LukaSikic/subzy` to `PentestPad/subzy`.
- nuclei's `-update-templates` silently no-ops in a relocated install; the
  installer fetches the template tarball directly.
- massdns ships no binary and must be compiled, or puredns is dead weight.
- `git clone` on SecLists fails over flaky links; the installer uses a resumable
  tarball from codeload instead.
