# Bug Bounty Methodology

## 0. Before anything — read the policy
- Confirm the asset is **in scope** (wildcards, acquisitions, mobile, API).
- Note **rate limits**, forbidden tests (DoS, social eng., automated scanning bans).
- Note whether they require a **custom User-Agent / header** to identify your traffic.
- Record out-of-scope domains in `scope/out-of-scope.txt` and actually filter against it.

## 1. Recon  (`bb-recon <program>`)
Passive subs (subfinder) → resolve (dnsx) → live probe (httpx) → ports (naabu).
Extras worth running by hand:
- `amass enum -passive -df scope/roots.txt` — deeper passive sources
- `github-subdomains -d target.com -t $GITHUB_TOKEN` — needs a GitHub token
- `alterx -l subdomains.txt | puredns resolve -r $RESOLVERS` — permutation brute force
- `uncover -q 'ssl:"target.com"' -e shodan,fofa` — needs API keys
- `asnmap -d target.com` then `mapcidr` → IP ranges they own

## 2. Attack surface  (`bb-urls <program>`)
gau + katana → uro dedupe → bucketed candidate lists.
- `js.txt` → pull secrets: `cat js.txt | xargs -I@ curl -s @ | grep -oE '(api[_-]?key|token|secret|password)["'"'"']?\s*[:=]\s*["'"'"'][^"'"'"']+'`
- `interesting_files.txt` → .env / .git / backups — highest EV, check them first
- `gowitness scan file -f recon/live.txt` → eyeball screenshots for odd apps

## 3. Triage the buckets (highest signal first)
| Bucket | Test |
|---|---|
| `interesting_files.txt` | direct fetch — exposed `.env`, `.git/config`, backups, `.DS_Store` |
| `idor_candidates.txt` | swap IDs between two accounts — **top payout/effort ratio** |
| `ssrf_candidates.txt` | `interactsh-client` OOB callback |
| `openredirect_candidates.txt` | chain into OAuth token theft, not standalone |
| `xss_candidates.txt` | `dalfox file xss_candidates.txt` |
| `lfi_candidates.txt` | traversal + wrappers |
| `params.txt` | `arjun -i live.txt` to find *hidden* params |

## 4. Vuln scan  (`bb-scan <program>`)
nuclei, rate-limited. Templates are a baseline, not the work — everyone runs them.

## 5. Where the real money is (manual)
Automation finds what everyone else already found. Duplicates come from step 4.
Spend your time on:
- **Business logic** — price manipulation, race conditions, workflow bypass
- **IDOR / broken access control** — 2 accounts, swap every identifier
- **Auth flows** — OAuth redirect_uri, JWT alg confusion, password reset token leaks
- **Race conditions** — Burp Turbo Intruder / repeater single-packet attack
- **New/unlinked functionality** — the `new_*.txt` diffs from bb-recon

## 6. Report
- Clear title, impact in business terms, exact reproduction steps, PoC, remediation.
- Screenshot/video. Minimal payload. State the affected endpoint precisely.
- Do not test beyond proving impact. No pivoting, no data exfil, no persistence.

## Continuous recon
Re-run `bb-recon` on a cron; `new_*.txt` files are freshly-appeared subdomains —
new assets are the least-tested and the best duplicate-free hunting ground.
