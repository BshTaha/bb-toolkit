#!/usr/bin/env python3
"""Proves bb-verify reports the real flaws on vulnserver and none of the traps.

    python3 tests/test_verify.py           # or: python3 -m unittest discover tests

Stdlib only — no pytest, no virtualenv, matching the rest of the project.
Each test builds a throwaway $BB workspace in a temp dir and runs the real
bb-verify as a subprocess, so what is under test is the shipped script, not a
reimplementation of it.

Not covered here: the takeover check, which needs live DNS (it shells out to
`dig` and resolves CNAME targets). Testing it properly needs a DNS fixture;
until then it is exercised only in the field.
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vulnserver  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BB_VERIFY = os.path.join(REPO, "scripts", "bb-verify")


class VerifyTestCase(unittest.TestCase):
    """Shared fixture: one vulnserver for the whole class, fresh workspace per test."""

    @classmethod
    def setUpClass(cls):
        cls.srv, cls.port = vulnserver.serve(0)
        cls.base = f"http://127.0.0.1:{cls.port}"

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.bb = self.tmp.name
        self.prog = "testprog"
        for sub in ("scope", "recon", "urls", "scans", "state"):
            os.makedirs(f"{self.bb}/targets/{self.prog}/{sub}", exist_ok=True)
        self.addCleanup(self.tmp.cleanup)

    def write(self, rel, lines):
        with open(f"{self.bb}/targets/{self.prog}/{rel}", "w") as fh:
            fh.write("\n".join(lines) + "\n")

    def run_verify(self, checks):
        env = dict(os.environ, BB=self.bb, TARGETS=f"{self.bb}/targets")
        r = subprocess.run(
            [sys.executable, BB_VERIFY, self.prog, "--checks", checks, "--threads", "4"],
            capture_output=True, text=True, env=env, timeout=120)
        self.assertEqual(r.returncode, 0, f"bb-verify failed:\n{r.stdout}\n{r.stderr}")
        path = f"{self.bb}/targets/{self.prog}/state/verified.jsonl"
        if not os.path.exists(path):
            return []
        with open(path) as fh:
            return [json.loads(l) for l in fh if l.strip()]

    @staticmethod
    def targets(findings, cls=None):
        return {f["target"] for f in findings if cls is None or f["cls"] == cls}


class TestSoftFourOhFourGuard(VerifyTestCase):
    """The core claim: a server that 200s everything must not produce findings."""

    def test_trap_is_actually_a_trap(self):
        """Sanity-check the fixture: a naive status+signature scanner WOULD fire.

        If this ever fails, the other tests in this class are proving nothing,
        because the trap stopped being a trap.
        """
        naive_hits = []
        for path, sig in (("/.git/config", b"[core]"),
                          ("/.git/HEAD", b"ref:"),
                          ("/.aws/credentials", b"aws_access_key"),
                          ("/phpinfo.php", b"phpinfo()"),
                          ("/actuator/heapdump", b"")):
            with urllib.request.urlopen(self.base + path, timeout=10) as r:
                body, status = r.read(), r.status
            if status == 200 and (not sig or sig.lower() in body.lower()):
                naive_hits.append(path)
        self.assertEqual(len(naive_hits), 5,
                         "fixture is broken — the soft-404 no longer fools a naive scanner")

    def test_verify_rejects_every_soft_404(self):
        """bb-verify must report none of the five the naive scanner found."""
        self.write("recon/live.txt", [self.base])
        found = self.targets(self.run_verify("files"), "exposed-file")
        for path in ("/.git/config", "/.git/HEAD", "/.aws/credentials",
                     "/phpinfo.php", "/actuator/heapdump", "/server-status"):
            self.assertNotIn(self.base + path, found,
                             f"false positive: {path} is a soft-404, not an exposure")

    def test_verify_still_finds_the_real_file(self):
        """Rejecting soft-404s must not cost it the genuine exposure."""
        self.write("recon/live.txt", [self.base])
        findings = self.run_verify("files")
        found = self.targets(findings, "exposed-file")
        self.assertIn(self.base + "/.env", found,
                      "missed the real exposed .env — the guard is too aggressive")
        self.assertEqual(len(found), 1, f"expected exactly one finding, got {found}")

        env_finding = next(f for f in findings if f["target"].endswith("/.env"))
        self.assertEqual(env_finding["severity"], "critical")
        self.assertEqual(env_finding["confidence"], "confirmed")
        self.assertIn("DB_PASSWORD", env_finding["evidence"])


class TestRedirect(VerifyTestCase):
    def test_confirms_real_and_rejects_same_origin(self):
        self.write("urls/openredirect_candidates.txt", [
            f"{self.base}/login?next=/dashboard",    # real: honours any destination
            f"{self.base}/logout?next=/dashboard",   # trap: always same-origin
        ])
        findings = self.run_verify("redirect")
        redirects = [f for f in findings if f["cls"] == "open-redirect"]
        self.assertEqual(len(redirects), 1, f"expected 1 open redirect, got {redirects}")
        self.assertIn("/login", redirects[0]["target"])
        self.assertEqual(redirects[0]["confidence"], "confirmed")
        self.assertNotIn("/logout", " ".join(f["target"] for f in redirects),
                         "false positive: /logout only ever redirects same-origin")


class TestCors(VerifyTestCase):
    def test_confirms_reflected_with_credentials_only(self):
        self.write("recon/live.txt", [
            f"{self.base}/api/me",        # real: reflects origin + credentials
            f"{self.base}/api/public",    # trap: wildcard, no credentials
            f"{self.base}/api/partner",   # trap: fixed allowlist
        ])
        findings = self.run_verify("cors")
        cors = [f for f in findings if f["cls"] == "cors"]
        self.assertEqual(len(cors), 1, f"expected 1 CORS finding, got {cors}")
        self.assertTrue(cors[0]["target"].endswith("/api/me"))
        self.assertEqual(cors[0]["severity"], "high",
                         "reflected origin WITH credentials should be high")
        for trap in ("/api/public", "/api/partner"):
            self.assertNotIn(trap, " ".join(f["target"] for f in cors))


class TestDeduplication(VerifyTestCase):
    def test_second_run_adds_nothing(self):
        """verified.jsonl is append-only and deduped by id — a re-run is a no-op."""
        self.write("recon/live.txt", [self.base])
        first = self.run_verify("files")
        second = self.run_verify("files")
        self.assertEqual(len(first), len(second),
                         "re-running bb-verify duplicated findings")
        self.assertEqual({f["id"] for f in first}, {f["id"] for f in second})


if __name__ == "__main__":
    unittest.main(verbosity=2)
