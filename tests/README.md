# Tests

```bash
python3 tests/test_verify.py           # or: python3 -m unittest discover tests
```

Stdlib only. No pytest, no virtualenv, no network — everything runs against a
local server on an ephemeral port.

## What these prove

The README claims bb-toolkit *"proves findings instead of reporting candidates."*
These tests are what makes that claim checkable rather than a promise.

`vulnserver.py` is a deliberately misbehaving target. Its central trap is the
**soft-404**: every unknown path returns HTTP 200, with a body that contains the
exact byte signatures bb-verify matches on — `=`, `[core]`, `ref:`,
`aws_access_key`, `phpinfo()`.

This is not a contrived scenario. Plenty of real sites answer 200 for everything,
usually a SPA fallback route or a catch-all CMS handler.

A scanner checking only status code and signature reports **five critical
exposures** against it. All five are fiction. One file on the server is genuinely
exposed, and the only thing distinguishing it is response length measured against
a random-path baseline.

| | Real | Trap |
|---|---|---|
| Files | `/.env` | `/.git/config`, `/.git/HEAD`, `/.aws/credentials`, `/phpinfo.php`, `/actuator/heapdump` |
| Redirect | `/login?next=` honours any destination | `/logout?next=` always redirects same-origin |
| CORS | `/api/me` reflects any Origin with credentials | `/api/public` wildcard without credentials; `/api/partner` fixed allowlist |

The suite asserts both directions: every trap is rejected, **and** every real flaw
is still caught. A guard that suppresses everything would pass one half and fail
the other.

`test_trap_is_actually_a_trap` guards the fixture itself. It asserts a naive
scanner *would* fire on all five traps — so if someone weakens the soft-404 and
the traps stop being traps, that test fails rather than letting the rest of the
suite pass while proving nothing.

## Verified by mutation

These assertions were checked by breaking bb-verify on purpose:

| Mutation | Result |
|---|---|
| Delete the soft-404 length guard | 6 findings instead of 1 — 2 tests fail |
| Make the CORS check ignore `Access-Control-Allow-Credentials` | 2 findings instead of 1 — 1 test fails |

## Not covered

The **takeover** check needs live DNS — it shells out to `dig` and resolves CNAME
targets to decide whether one is dangling. Testing it honestly needs a DNS
fixture; until that exists it is exercised only in the field, not here.

## The recording

`demo.sh` is the scripted demo used for the README GIF. Every command in it is
really run against vulnserver on localhost:

```bash
bash tests/demo.sh
```

To re-record it:

```bash
asciinema rec --cols 98 --rows 40 -c "bash tests/demo.sh" demo.cast
agg --theme asciinema --font-family "DejaVu Sans Mono" --font-size 15 \
    --fps-cap 10 --idle-time-limit 1.5 --line-height 1.35 \
    demo.cast docs/img/demo.gif
```

Use a font without programming ligatures — Fira Code renders `&&` as a single
glyph that reads as mojibake in the GIF.

## Poking at the server by hand

```bash
python3 tests/vulnserver.py --port 8000
curl -s localhost:8000/.env                       # real
curl -s localhost:8000/.git/config                # 200, contains [core], not real
curl -sI 'localhost:8000/login?next=https://example.com' | grep -i location
curl -sI -H 'Origin: https://evil.example' localhost:8000/api/me | grep -i access-control
```
