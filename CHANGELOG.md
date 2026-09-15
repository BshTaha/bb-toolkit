# Changelog

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
- `alterx -limit 0` (its default) hangs forever; `bb-brute` always passes an
  explicit limit plus a 300s timeout guard.
- `subzy` moved from `LukaSikic/subzy` to `PentestPad/subzy`.
- nuclei's `-update-templates` silently no-ops in a relocated install; the
  installer fetches the template tarball directly.
- massdns ships no binary and must be compiled, or puredns is dead weight.
- `git clone` on SecLists fails over flaky links; the installer uses a resumable
  tarball from codeload instead.
