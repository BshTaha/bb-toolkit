#!/usr/bin/env python3
"""A deliberately misbehaving HTTP server, for testing bb-verify locally.

It exists to answer one question: does bb-verify report only what is really
there? So it serves a mix of genuine flaws and traps that look identical to a
scanner that doesn't verify.

The central trap is the soft-404: EVERY unknown path returns HTTP 200 with the
same body, and that body deliberately contains the byte signatures bb-verify
looks for (`=`, `[core]`, `ref:`, `aws_access_key`, `phpinfo()`). A scanner that
checks status and signature alone reports five critical exposures here. All five
are fiction. Only /.env is real, and the only thing that separates it is
response length against a random-path baseline.

Run standalone to poke at it by hand:
    python3 tests/vulnserver.py --port 8000
"""
import argparse
import http.server
import socketserver
import threading
import urllib.parse

# Served for every unknown path, with HTTP 200. Fixed length, so a random-path
# baseline and a guessed-filename request are byte-identical in size.
# Contains every signature bb-verify matches on — that is the point.
SOFT_404 = (
    b"<!doctype html><html><head><title>Page not found</title></head><body>"
    b"<h1>Sorry, we couldn't find that page</h1>"
    b"<p>The link may be broken, or the page may have been removed.</p>"
    b"<div class=search><form action=/search method=get>"
    b"<input name=q placeholder='Search the site'><button>Search</button></form></div>"
    b"<!-- debug: build=2026.09.1 ref: main [core] aws_access_key=none phpinfo() -->"
    b"<footer><a href=/>Home</a> &middot; <a href=/help>Help</a>"
    b" &middot; <a href=/contact>Contact</a></footer>"
    b"<script>window.APP_CONFIG={env:'production',region:'eu-west-1'};</script>"
    b"</body></html>"
)

# The one genuinely exposed file. Different length from SOFT_404 by well over
# the 48-byte threshold, which is what makes it distinguishable.
REAL_ENV = (
    b"APP_ENV=production\n"
    b"DB_HOST=db.internal\n"
    b"DB_PASSWORD=hunter2\n"
)

CANARY_SAFE_DEST = "/home"


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    # -- plumbing ----------------------------------------------------------
    def log_message(self, *_a):
        pass  # keep test output readable

    def _send(self, code, body=b"", headers=None):
        self.send_response(code)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body and self.command != "HEAD":
            self.wfile.write(body)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        p = urllib.parse.urlsplit(self.path)
        path, qs = p.path, urllib.parse.parse_qs(p.query, keep_blank_values=True)
        origin = self.headers.get("Origin", "")

        # -- REAL: an actually exposed .env ---------------------------------
        if path == "/.env":
            return self._send(200, REAL_ENV)

        # -- REAL: open redirect, sends the user wherever `next` says --------
        if path == "/login":
            dest = (qs.get("next") or [""])[0]
            if dest:
                return self._send(302, b"", {"Location": dest})
            return self._send(200, SOFT_404)

        # -- TRAP: looks like a redirect, but only ever goes same-origin -----
        if path == "/logout":
            return self._send(302, b"", {"Location": CANARY_SAFE_DEST})

        # -- REAL: reflects any Origin and allows credentials ---------------
        if path == "/api/me":
            h = {"Vary": "Origin"}
            if origin:
                h["Access-Control-Allow-Origin"] = origin
                h["Access-Control-Allow-Credentials"] = "true"
            return self._send(200, b'{"user":"demo"}', h)

        # -- TRAP: wildcard, but no credentials. Not a finding. -------------
        if path == "/api/public":
            return self._send(200, b'{"ok":true}', {"Access-Control-Allow-Origin": "*"})

        # -- TRAP: a fixed allowlist. Correct behaviour, not a finding. ------
        if path == "/api/partner":
            return self._send(200, b'{"ok":true}', {
                "Access-Control-Allow-Origin": "https://partner.example.org",
                "Access-Control-Allow-Credentials": "true",
            })

        # -- TRAP: everything else is a soft 404 with a 200 status ----------
        # /.git/config, /.git/HEAD, /.aws/credentials, /phpinfo.php,
        # /actuator/heapdump and friends all land here. None of them exist.
        return self._send(200, SOFT_404)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def serve(port=0):
    """Start in a background thread. Returns (server, port)."""
    srv = Server(("127.0.0.1", port), Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, srv.server_address[1]


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=8000)
    args = ap.parse_args()
    srv, port = serve(args.port)
    print(f"vulnserver on http://127.0.0.1:{port}")
    print(f"  REAL  /.env                 exposed file")
    print(f"  REAL  /login?next=          open redirect")
    print(f"  REAL  /api/me               CORS reflects origin + credentials")
    print(f"  TRAP  /logout?next=         redirect, but same-origin only")
    print(f"  TRAP  /api/public           wildcard CORS, no credentials")
    print(f"  TRAP  /api/partner          fixed allowlist")
    print(f"  TRAP  everything else       HTTP 200 soft-404 containing every signature")
    try:
        threading.Event().wait()
    except KeyboardInterrupt:
        srv.shutdown()
