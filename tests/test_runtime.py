"""Tests for the opt-in RDC runtime updater; no Docker or network access."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "scripts" / "rdc-runtime.sh"
FAKE_NPM = """#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ['TEST_NPM_LOG'], 'a') as f:
    f.write(json.dumps(args) + '\\n')
if args[0] == 'view':
    if os.environ.get('FAKE_NPM_OFFLINE') == '1':
        sys.exit(1)
    print(os.environ.get('FAKE_NPM_LATEST', '0.3.0'))
elif args[0] == 'install':
    if os.environ.get('FAKE_INSTALL_FAIL') == '1':
        sys.exit(1)
    prefix = Path(args[args.index('--prefix') + 1])
    version = args[-1].rsplit('@', 1)[-1]
    meta = prefix / 'node_modules/@wonderwhy-er/desktop-commander/package.json'
    meta.parent.mkdir(parents=True)
    meta.write_text(json.dumps({'version': version}))
    binary = prefix / 'node_modules/.bin/desktop-commander'
    binary.parent.mkdir(parents=True)
    binary.write_text('#!/bin/sh\\n'
        'if [ "${1:-}" = remote ] && [ "${2:-}" = --help ]; then\\n'
        '  [ "$TEST_FAIL_HELP_VERSION" = "' + version + '" ] && exit 1\\n'
        '  exit 0\\n'
        'fi\\n'
        'echo ' + version + ' >> "$TEST_RUN_LOG"\\n')
    binary.chmod(0o755)
else:
    sys.exit(2)
"""

class RuntimeUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.tmp = Path(self.temporary.name)
        self.tools = self.tmp / "tools"
        self.tools.mkdir()
        (self.tools / "npm").write_text(FAKE_NPM)
        (self.tools / "npm").chmod(0o755)
        self.bundled = self.tmp / "bundled"
        meta = self.bundled / "node_modules/@wonderwhy-er/desktop-commander/package.json"
        meta.parent.mkdir(parents=True)
        meta.write_text(json.dumps({"version": "0.2.52"}))
        binary = self.bundled / "node_modules/.bin/desktop-commander"
        binary.parent.mkdir(parents=True)
        binary.write_text('#!/bin/sh\n'
                          'echo 0.2.52 >> "$TEST_RUN_LOG"\n')
        binary.chmod(0o755)
        self.state = self.tmp / "state"
        self.env = {
            **os.environ,
            "PATH": str(self.tools) + os.pathsep + os.environ["PATH"],
            "RDC_AUTO_UPDATE": "true",
            "RDC_STATE_DIR": str(self.state),
            "RDC_BUNDLED_DIR": str(self.bundled),
            "TEST_NPM_LOG": str(self.tmp / "npm.jsonl"),
            "TEST_RUN_LOG": str(self.tmp / "runtime.log"),
            "TEST_FAIL_HELP_VERSION": "none",
        }

    def run_runtime(self, **settings):
        return subprocess.run(["bash", str(RUNTIME), "remote"],
                              env={**self.env, **settings},
                              text=True, capture_output=True, timeout=30)

    def runs(self):
        p = self.tmp / "runtime.log"
        return p.read_text().splitlines() if p.exists() else []

    def npm_calls(self):
        p = self.tmp / "npm.jsonl"
        return [json.loads(line) for line in p.read_text().splitlines()] if p.exists() else []

    def installed(self):
        return self.state / "runtime/selected-version"

    def test_updates_once_and_uses_versioned_cache(self):
        p = self.run_runtime()
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(self.installed().read_text().strip(), "0.3.0")
        self.assertEqual(self.runs(), ["0.3.0"])
        self.assertEqual(len([a for a in self.npm_calls() if a[0] == "install"]), 1)
        p = self.run_runtime()
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(self.runs(), ["0.3.0", "0.3.0"])
        self.assertEqual(len([a for a in self.npm_calls() if a[0] == "install"]), 1)

    def test_offline_reuses_previous_download(self):
        self.assertEqual(self.run_runtime().returncode, 0)
        p = self.run_runtime(FAKE_NPM_OFFLINE="1")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("registry unavailable", p.stderr)
        self.assertEqual(self.runs(), ["0.3.0", "0.3.0"])

    def test_failed_install_uses_bundled_runtime(self):
        p = self.run_runtime(FAKE_INSTALL_FAIL="1")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(self.runs(), ["0.2.52"])
        self.assertFalse(self.installed().exists())
        self.assertEqual(list((self.state / "runtime/versions").iterdir()), [])

    def test_failed_validation_keeps_previous_cached_runtime(self):
        self.assertEqual(self.run_runtime().returncode, 0)
        p = self.run_runtime(FAKE_NPM_LATEST="0.3.1", TEST_FAIL_HELP_VERSION="0.3.1")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(self.installed().read_text().strip(), "0.3.0")
        self.assertEqual(self.runs(), ["0.3.0", "0.3.0"])

    def test_rejects_prerelease_and_downgrade(self):
        self.assertEqual(self.run_runtime(FAKE_NPM_LATEST="0.3.1-alpha.2").returncode, 0)
        self.assertEqual(self.runs(), ["0.2.52"])
        self.assertFalse(self.installed().exists())
        self.assertEqual(self.run_runtime(FAKE_NPM_LATEST="0.2.1").returncode, 0)
        self.assertEqual(self.runs(), ["0.2.52", "0.2.52"])
        self.assertFalse(any(c[0] == "install" for c in self.npm_calls()))

    def test_off_mode_never_contacts_npm_or_uses_cache(self):
        self.assertEqual(self.run_runtime().returncode, 0)
        calls = len(self.npm_calls())
        p = self.run_runtime(RDC_AUTO_UPDATE="false")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(len(self.npm_calls()), calls)
        self.assertEqual(self.runs(), ["0.3.0", "0.2.52"])

    def test_missing_registry_starts_bundled_runtime(self):
        p = self.run_runtime(FAKE_NPM_OFFLINE="1")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(self.runs(), ["0.2.52"])

if __name__ == "__main__":
    unittest.main()
