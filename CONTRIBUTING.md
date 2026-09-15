# Contributing

Issues and pull requests are welcome.

## Before you open a PR

Run what CI runs:

```bash
shellcheck -e SC1090,SC1091,SC2086 -S warning \
  $(grep -rlE '^#!/usr/bin/env bash' scripts install.sh env.sh)

for f in $(grep -rlE '^#!/usr/bin/env python3' scripts); do
  python3 -m py_compile "$f"
done
```

CI runs those plus a functional smoke test (scaffold a workspace, confirm the
scripts refuse to run without a scope file, check `--help` exits cleanly).

## What this project wants

**Correctness over coverage.** The value here isn't the number of tools wrapped —
it's that a result you get at 3am is real. A PR that adds a check should say how
it avoids false positives, the way `bb-verify` uses a soft-404 baseline before
reporting an exposed file.

**Rate limits that actually hold.** Anything issuing requests must respect the
program profile (`scope/profile.env`) and the `--rate` ceiling. If a tool has no
native rate limiting, convert the ceiling into a per-thread delay rather than
ignoring it.

**No new noise.** If a check fires on things programs don't pay for — TLS config,
missing headers, SPF/DKIM/DMARC, version banners — it belongs in `bb-triage`'s
NOISE set, not in an alert.

**Keep state inside `$BB`.** Tool config, caches and credentials go in the folder,
never scattered through `$HOME`. The one exception is the `~/.gf` symlink, because
`gf` reads no other path.

## Don't commit

`targets/`, `loot/` and `logs/` are gitignored for a reason: they hold live recon
output and session data for real engagements. Check `git status` before you push.

Never commit an API key, webhook or token. `data/configs/` is gitignored wholesale.

## Style

Bash: `set -uo pipefail`, quote expansions, guard every `cd`. Python: standard
library only where practical — the scripts should run without a virtualenv.

## Reporting a bug in the toolkit

Include the command you ran, what happened, and what you expected. If a tool it
wraps is involved, include that tool's version — several of the sharp edges
documented in `CHANGELOG.md` were version-specific behaviour changes upstream.
