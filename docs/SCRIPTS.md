# Script reference

Every script reads its program workspace from `$TARGETS/<program>/`. Run
`bb-new <program> <root-domain...>` first to scaffold one.

Workspace layout:

```
scope/roots.txt          root domains to enumerate      (you fill this)
scope/out-of-scope.txt   exclusion patterns             (you fill this, from the policy)
scope/profile.env        UA + rate policy               (bb-profile init)
recon/                   subdomains, resolved, live hosts, ports, new_* diffs
urls/                    raw, deduped, and bucketed candidate URL lists
scans/                   raw nuclei / subzy output
state/                   findings.jsonl, verified.jsonl, sent.db, hunt.lock
loot/                    js secrets, cloud references
notes/README.md          program notes, scaffolded by bb-new
```

---

## bb-hunt — the orchestrator

```
bb-hunt <program> [options]
```

Runs the whole pipeline. Cycle 1 is a full sweep; later cycles re-enumerate,
diff for new assets, and scan only those — new assets are the least-tested
surface and the best duplicate-free hunting ground — with a full re-sweep every
`--full-every` cycles.

| Option | Default | Meaning |
|---|---|---|
| `--loop` | off | Keep hunting until stopped |
| `--interval <sec>` | 3600 | Sleep between cycles |
| `--full-every <n>` | 6 | Full re-sweep every *n* cycles |
| `--min <sev>` | medium | Minimum severity pushed to Discord |
| `--rate <n>` | 100 | Requests/sec ceiling across the whole pipeline |
| `--threads <n>` | 20 | Concurrency |
| `--ping <text>` | — | Prepended on high/critical, e.g. `'<@1234>'` |
| `--dast` | off | Also run nuclei fuzzing templates against collected params |
| `--brute <mode>` | fast | Keyless DNS bruteforce: `off\|fast\|deep\|max` |
| `--no-discord` | — | Local only |
| `--heartbeat` | off | Post a cycle summary even with zero findings |

**`--rate` is honoured end to end.** `bb-verify` has its own thread pool with no
native rate limiting, so `bb-hunt` converts the ceiling into a per-thread delay
(`threads / rate`) before calling it.

A `scope/profile.env` written by `bb-profile` overrides `--rate` and `--threads`
and injects the mandated User-Agent into every tool. A PID lock at
`state/hunt.lock` prevents two hunts on the same program.

---

## bb-verify — prove it before you report it

```
bb-verify <program> [--checks all] [--threads 20] [--rate 0.0]
```

Checks: `redirect`, `cors`, `files`, `takeover`. Writes
`state/verified.jsonl`, which `bb-triage` picks up. Everything it emits is
`confidence=confirmed`.

The **soft-404 baseline guard** is the important part: before testing for an
exposed file it requests a random path on the same host and compares the
response length. Sites that return `200 OK` for every path — which is most of
them — would otherwise produce a page of fake `.env` and `.git/config` findings.

Redirect checks use a canary host that cannot receive data; it is a marker that
the redirect left the origin, never a live payload pointed at a real server.

`--rate` is a per-request delay in seconds, not a req/s figure.

---

## bb-triage — one deduped findings file

```
bb-triage <program>
```

Reads everything under `scans/`, `loot/`, `urls/` and `recon/`; writes
`state/findings.jsonl`, append-only and deduplicated by a SHA-1 over the
identifying fields. Prints a severity tally.

Drops ~40 noise classes that are on essentially every program's non-qualifying
list: TLS/cipher config, missing security headers, SPF/DKIM/DMARC, clickjacking,
version banners, `*-detect` and `*-fingerprint` templates, open ports without a
PoC. Boosts classes that are almost always real regardless of template severity —
subdomain takeover, exposed `.git`/`.env`, RCE.

Requires nuclei to have been run with `-jsonl`.

---

## bb-report — Discord, without the noise

```
bb-report <program> [--min medium] [--all] [--summary <text>] [--ping <text>] [--test]
```

Rich embeds coloured by severity. `state/sent.db` guarantees a finding is never
pushed twice, so you can run it on every cycle. Honours Discord's `429
retry_after` rather than dropping alerts.

Webhook is read from `$DISCORD_WEBHOOK`, else
`$BB/data/configs/discord-webhook.txt`.

---

## bb-profile — per-program request policy

```
bb-profile <program> init|show|verify
```

Some programs mandate an identifying User-Agent (YesWeHack appends
`-public-yeswehack` to yours). Getting it wrong on one tool out of six is a
policy violation, so the UA and rate live in one file, `scope/profile.env`,
which every `bb-*` script sources.

`verify` **proves** the header reaches the wire by running curl, httpx, katana,
nuclei and ffuf against a throwaway local listener — the proof costs the target
zero requests.

---

## bb-brute — keyless discovery

```
bb-brute <program> [--depth fast|deep|max] [--perms] [--rate N] [--roots <file>]
```

DNS bruteforce via puredns/massdns, wildcard-filtered, then optional `alterx`
permutations over already-known hosts. Results are `anew`'d into
`recon/subdomains.txt` so `bb-hunt` picks them up.

| Depth | Wordlist | Size |
|---|---|---|
| `fast` | `subdomains-top1million-110000` | 110k |
| `deep` | `combined_subdomains` | 654k |
| `max` | trickest bug-bounty inventory | 1.6M |

This exists because passive sources structurally cannot see a host that never
got a certificate, never got crawled and never leaked. `--rate` is DNS queries
per second against public resolvers, not HTTP requests against the target;
5000 is fine on a good link, but it will saturate a home connection — drop it to
a few hundred if your network suffers.

Requires massdns on `$PATH`; puredns is inert without it.

---

## bb-sevfirst — for hard request budgets

```
bb-sevfirst <program> <host-list> [severity]
```

When a program caps you at a few requests per second, running all ~13,000
nuclei templates is the wrong use of the budget. Resolves over DNS first (free —
never touches the target's HTTP surface), probes, then runs high+critical
templates only. Sources the program's profile for UA and rate, re-applies scope
exclusions after probing, then triages and reports.

---

## Recon layer

| Command | Does |
|---|---|
| `bb-new <prog> [domain...]` | Scaffold the workspace and a notes template |
| `bb-recon <prog> [--ports]` | subfinder → dnsx → httpx (profile rate/UA) → new-since-last-run diff. The `naabu` port scan is opt-in via `--ports` (or `BB_ALLOW_PORTSCAN=1`); out-of-scope filtering is applied throughout |
| `bb-urls <prog>` | gau + katana → uro dedupe → buckets: `params`, `js`, `interesting_files`, and `idor`/`ssrf`/`lfi`/`xss`/`openredirect` candidates |
| `bb-secrets <prog>` | Download every JS file (profile UA + mandated headers); mine secrets, cloud refs, endpoints |
| `bb-gf <prog>` | Run every gf pattern over the collected URLs |
| `bb-takeover <prog>` | nuclei takeover templates (profile-driven) + subzy; subzy is skipped when the program mandates an identifying UA/header |
| `bb-scan <prog> [sev]` | nuclei over live hosts at the program's rate/UA; refuses to run without a `scope/profile.env` |
| `bb-findings [prog]` | Colourised review. `--min`, `--cls`, `--full` |
| `bb-update` | Update every tool, template, wordlist and the resolver list |

---

## bb-keys — API keys

```
bb-keys list | links [tier] | set <provider> <key> | test [provider] | rm <provider>
```

Providers are tiered by value with free-tier limits and signup URLs. `test`
probes each vendor's API **directly** — subfinder swallows 401s and reports a
dead key as "0 results", so it cannot be trusted to validate anything.

Keys shared with `uncover` (shodan, censys, fofa, quake, netlas, …) are mirrored
into both config files automatically.

---

## Mobile

`mobile-setup.sh` builds an Android static-analysis toolchain (apkeep, apkleaks,
androguard, jadx) into `$BB/opt/mobile`; `env-mobile.sh` puts it on `$PATH`.
