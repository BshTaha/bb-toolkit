# bb-toolkit

[![ci](https://github.com/BshTaha/bb-toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/BshTaha/bb-toolkit/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A self-contained, policy-aware recon and hunting pipeline for bug bounty. It runs
unattended all night, **proves** what it finds before alerting you, and pushes only
verified findings to Discord.

No sudo. Nothing installed system-wide. Delete the folder and the environment is gone.

```
recon → scope-filter → urls → js secrets → VERIFY → nuclei → triage → Discord
                         ↑                                              │
                         └──────── new-asset diff, every cycle ─────────┘
```

---

## Quickstart

```bash
git clone https://github.com/BshTaha/bb-toolkit ~/bugbounty
cd ~/bugbounty && ./install.sh          # --minimal to skip the 1GB wordlists
source env.sh

bb-new acme acme.com api.acme.com       # scaffold a program workspace
$EDITOR $TARGETS/acme/scope/out-of-scope.txt   # fill this from the policy FIRST
bb-hunt acme --no-discord               # one full cycle, local only
```

Then, once the scope file is right and you have a webhook:

```bash
bb-hunt acme --loop --rate 5 --min medium --ping '<@YOUR_DISCORD_ID>'
```

---

## Why not just a file of aliases

Anyone can pipe subfinder into httpx into nuclei. What takes a pipeline from
"noise generator" to something you'll actually act on at 3am is the unglamorous
correctness work, and that's most of what's in here:

**It proves findings instead of reporting candidates.** `bb-verify` actively
confirms open redirects, CORS misconfigurations, exposed files and subdomain
takeovers before any of them reach your phone. Exposed-file checks run against a
**soft-404 baseline** — it requests a random path first and compares the response
length, so a site that returns `200 OK` for everything doesn't generate fifty fake
`.env` findings. Everything it emits is marked `confidence=confirmed`.

**It never pages you twice for the same bug.** `bb-report` keeps a `sent.db`;
findings are deduplicated by SHA-1 over their identifying fields. It also honours
Discord's `429 retry_after` instead of hammering and silently dropping alerts.

**It respects the program's request budget.** `bb-profile` holds the mandated
User-Agent and rate limit for a program in one place and emits ready-to-paste
flags for every tool — because getting the UA wrong on one tool out of six is a
policy violation. `bb-profile verify` **proves** the header actually reaches the
wire by running curl, httpx, katana, nuclei and ffuf against a throwaway local
listener, so the proof costs the target zero requests.

**The rate limit is real, not decorative.** `bb-verify` has its own thread pool
with no native rate limiting, so `bb-hunt` converts your `--rate` into a
per-thread delay (`threads / rate`) before calling it. A `--rate 5` cap stays 5
req/s across the whole pipeline, not per tool.

**It budgets your API quota.** SecurityTrails gives 50 queries/month, Censys 250,
BeVigil 50. At one query per hourly cycle those are gone in two days, so low-quota
providers are excluded from delta cycles and spent only on full sweeps.

**It drops what programs don't pay for.** `bb-triage` filters ~40 known-noise
template classes — TLS config, missing headers, SPF/DKIM/DMARC, clickjacking,
version banners, open ports without a PoC — because those are on the
non-qualifying list of essentially every program, and filing one burns a report
for nothing.

**It only scans what's in scope.** Every host list passes through
`scope/out-of-scope.txt` before any tool touches it — after enumeration, after
bruteforce, and again after probing.

---

## Tests

```bash
python3 tests/test_verify.py
```

The claim above — that it proves findings rather than reporting candidates — is
checkable. `tests/vulnserver.py` is a server that returns HTTP 200 for every
path, with a body containing the exact signatures bb-verify matches on. A scanner
checking status and signature alone reports **five critical exposures** against
it; all five are fiction, and exactly one file is genuinely exposed.

The suite asserts both directions: every trap rejected, every real flaw still
caught. Details, including the mutation testing used to confirm the assertions
have teeth, are in [`tests/README.md`](tests/README.md).

---

## The scripts

| Script | What it does |
|---|---|
| `bb-hunt` | The orchestrator. Full sweep on cycle 1, then new-asset-only deltas with a full re-sweep every *n* cycles. Locking, scope filtering, profile loading, `--loop`. |
| `bb-verify` | Actively proves redirect / CORS / exposed-file / takeover candidates. Soft-404 guard. Emits `confidence=confirmed`. |
| `bb-triage` | Normalizes nuclei JSONL, subzy, JS secrets and recon diffs into one deduped, severity-scored `findings.jsonl`. |
| `bb-report` | Discord webhook, rich embeds coloured by severity, `sent.db` guarantees no duplicate alert, handles 429. |
| `bb-profile` | Per-program User-Agent and rate policy, with `verify` proving the UA reaches the wire against a local listener. |
| `bb-keys` | Manage and **live-validate** subfinder/uncover API keys. Tiered by value with free-tier notes and signup links. |
| `bb-brute` | Keyless DNS bruteforce (puredns/massdns) + alterx permutations. Finds hosts no passive source can know about. |
| `bb-sevfirst` | Rate-capped, severity-first sweep for programs with a hard per-host request budget. |
| `bb-recon` | Passive subs → resolve → live probe → ports, with a new-since-last-run diff. |
| `bb-urls` | gau + katana → uro dedupe → bucketed candidate lists (IDOR, SSRF, LFI, XSS, open redirect). |
| `bb-secrets` | Downloads every JS file, mines secrets, cloud references and endpoints. |
| `bb-findings` | Colourised CLI review of the night's haul. `--min`, `--cls`, `--full`. |
| `bb-gf` / `bb-takeover` / `bb-scan` | gf patterns over collected URLs; subzy + nuclei takeover templates; rate-limited nuclei. |
| `bb-new` / `bb-update` | Scaffold a program workspace; update every tool, template and wordlist. |

Full reference: [`docs/SCRIPTS.md`](docs/SCRIPTS.md). Methodology:
[`docs/METHODOLOGY.md`](docs/METHODOLOGY.md).

---

## What a cycle looks like

```
[02:14:07] cycle 7 (delta) — acme
[02:14:07] recon: subdomain enum + resolve + probe
    scope filter: dropped 12 out-of-scope entries
    subdomains: 3841  (new this cycle: 6)
    live hosts: 402
[02:31:55] verify: proving candidates (redirect / cors / files / takeover)
    verified: 1 confirmed, 23 rejected (soft-404 baseline)
[02:33:10] nuclei: 6 hosts
[02:36:02] triage
    critical 0  high 1  medium 3  low 11
[02:36:04] report
    pushed 1 finding (3 suppressed as already-sent)
acme · cycle 7 (delta) done in 1317s — 3841 subs, 6 new, 402 live · totals: 🔴 0 / 🟠 1 / 🟡 3
```

---

## Layout

```
scripts/     the bb-* pipeline, put on $PATH by env.sh
install.sh   builds everything below into this folder
bin/         tool binaries (Go + Python), first on $PATH
opt/         go toolchain, GOPATH/module cache, pipx venvs
tools/       git-cloned tools (massdns is compiled here)
wordlists/   SecLists + the trickest bug-bounty inventory
data/        nuclei templates, resolvers, per-tool config
targets/     one workspace per program  ($TARGETS)  — gitignored
loot/        confirmed findings         ($LOOT)     — gitignored
```

`env.sh` derives `$BB` from its own location, so the checkout is relocatable.
Every tool's config and state is redirected into `$BB` — `GOPATH`, `PIPX_HOME`,
`PDCP_HOME`, `NUCLEI_TEMPLATES`, `GF_PATH` — rather than scattered through `$HOME`.

---

## API keys

Optional, but a real uplift in coverage. `bb-keys` ranks providers by value and
validates them against the live API — **don't trust subfinder to validate a key**,
it swallows 401s and shows a bad key as "0 results".

```bash
bb-keys links 1          # tier-1 providers: signup URLs + free-tier limits
bb-keys set github ghp_xxx
bb-keys test             # probe each vendor API directly
```

The toolkit works fully without any keys — `bb-brute` exists precisely because
keyless discovery finds hosts that never got a certificate, never got crawled and
never leaked, which no passive source can see.

---

## Requirements

Linux, `curl`, `git`, `python3` ≥ 3.8, `tar`. `gcc` and `make` if you want
`bb-brute` (massdns ships no binary and has to be compiled). The installer fetches
its own Go toolchain — a system Go is not required.

---

## Scope and authorization

**Only test assets you are explicitly authorized to test.** These scripts generate
real traffic against real systems. Before running anything here:

- Confirm the asset is in scope, and fill `scope/out-of-scope.txt` from the policy.
- Check whether the program permits automated scanning **at all** — most do not.
  Read the clause verbatim; "do not use automated scanners" means this toolkit.
- Set the mandated User-Agent and rate limit with `bb-profile init`, and confirm
  it with `bb-profile verify`.
- Default `--rate` is 100 req/s. That is too high for most programs. Set it down.

Running an unattended scanner against a target that forbids it gets your account
banned and can be unlawful. That is your responsibility, not the toolkit's.

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
