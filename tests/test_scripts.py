"""Unprivileged unit tests; Docker is mocked, so these cannot change a host."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MOCK = r"""#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ['FAKE_DOCKER_LOG'], 'a') as f:
    f.write(json.dumps(args) + '\n')
if args[0] == 'info':
    print(os.environ.get('FAKE_INFO', 'linux|Ubuntu|["name=seccomp"]'))
elif args[:2] == ['context', 'inspect']:
    print(os.environ.get('FAKE_ENDPOINT', 'unix:///var/run/docker.sock'))
elif args[:2] == ['image', 'inspect']:
    if os.environ.get('FAKE_IMAGE_MISSING') == '1': sys.exit(1)
    print(os.environ.get('FAKE_ROLE', 'host-admin') if '--format' in args else '[]')
elif args[:2] == ['container', 'inspect']:
    if os.environ.get('FAKE_EXISTING') != '1': sys.exit(1)
    print(os.environ.get('FAKE_OWNER', 'rdc-host-admin'))
elif args[:2] == ['volume', 'inspect']:
    if os.environ.get('FAKE_VOLUME') != '1': sys.exit(1)
    print(os.environ.get('FAKE_VOLUME_OWNER', 'rdc-host-admin'))
elif args[:2] == ['volume', 'create']:
    print(args[-1])
elif args[0] in ('create', 'start', 'pull'):
    print('mock-id')
else:
    print('Unexpected mocked Docker operation: ' + repr(args), file=sys.stderr)
    sys.exit(90)
"""


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.tmp = Path(self.temp.name)
        (self.tmp / 'docker').write_text(MOCK)
        (self.tmp / 'docker').chmod(0o755)
        self.log = self.tmp / 'calls.jsonl'
        self.env = {
            **os.environ,
            'PATH': str(self.tmp) + os.pathsep + os.environ['PATH'],
            'FAKE_DOCKER_LOG': str(self.log),
            'RDC_ALLOW_HOST_ADMIN': 'true',
            'RDC_DEVICE_NAME': 'unit-test-admin',
            'CONTAINER_NAME': 'rdc-host-admin-test',
            'STATE_VOLUME': 'rdc-host-admin-test-state',
            'START_NOW': 'n',
        }
        for key in ('DOCKER_HOST', 'DOCKER_CONTEXT'):
            self.env.pop(key, None)

    def run_script(self, name='install.sh', args=(), **updates):
        env = {**self.env, **updates}
        return subprocess.run(['bash', str(ROOT / name), *args], env=env,
                              stdin=subprocess.DEVNULL, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def assert_no_create(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(any(c[0] == 'create' for c in self.calls()))

    def test_requires_explicit_acknowledgement(self):
        self.assert_no_create(self.run_script(RDC_ALLOW_HOST_ADMIN='false'))
        self.assertEqual(self.calls(), [])

    def test_default_install_is_stopped_and_explicitly_privileged(self):
        p = self.run_script()
        self.assertEqual(p.returncode, 0, p.stderr)
        args = next(c for c in self.calls() if c[0] == 'create')
        for flag in ('--privileged', '--pid=host', '--network=host', '--ipc=host'):
            self.assertIn(flag, args)
        self.assertIn('type=bind,src=/,dst=/host,bind-propagation=rslave', args)
        self.assertIn('type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock', args)
        self.assertIn('RDC_ALLOW_HOST_ADMIN=true', args)
        self.assertEqual(args[args.index('--restart') + 1], 'no')
        self.assertEqual(args[args.index('--memory') + 1], '1024m')
        self.assertNotIn('--uts=host', args)
        self.assertFalse(any(c[0] == 'start' for c in self.calls()))
        self.assertNotIn('--publish', args)

    def test_explicit_start(self):
        self.assertEqual(self.run_script(START_NOW='y').returncode, 0)
        self.assertTrue(any(c[0] == 'start' for c in self.calls()))

    def test_existing_container_is_not_replaced(self):
        self.assert_no_create(self.run_script(FAKE_EXISTING='1'))
        self.assertFalse(any(c[0] in ('rm', 'stop') for c in self.calls()))

    def test_unrelated_volume_is_not_reused(self):
        self.assert_no_create(self.run_script(FAKE_VOLUME='1', FAKE_VOLUME_OWNER='other'))

    def test_owned_volume_is_reused(self):
        self.assertEqual(self.run_script(FAKE_VOLUME='1').returncode, 0)
        self.assertFalse(any(c[:2] == ['volume', 'create'] for c in self.calls()))

    def test_rejects_wrong_image_role(self):
        self.assert_no_create(self.run_script(FAKE_ROLE='restricted'))

    def test_rejects_remote_context(self):
        self.assert_no_create(self.run_script(FAKE_ENDPOINT='ssh://someone@example.test'))

    def test_rejects_nondefault_local_socket(self):
        self.assert_no_create(self.run_script(FAKE_ENDPOINT='unix:///tmp/other-docker.sock'))

    def test_explicit_context_takes_precedence_over_docker_host(self):
        self.assert_no_create(self.run_script(DOCKER_CONTEXT='remote', DOCKER_HOST='unix:///var/run/docker.sock',
                                             FAKE_ENDPOINT='ssh://someone@example.test'))

    def test_rejects_rootless_engine(self):
        self.assert_no_create(self.run_script(FAKE_INFO='linux|Ubuntu|["name=rootless"]'))

    def test_rejects_userns_remapping(self):
        self.assert_no_create(self.run_script(FAKE_INFO='linux|Ubuntu|["name=userns"]'))

    def test_rejects_docker_desktop(self):
        self.assert_no_create(self.run_script(FAKE_INFO='linux|Docker Desktop|[]'))

    def test_rejects_invalid_hostname(self):
        self.assert_no_create(self.run_script(RDC_DEVICE_NAME='wrong name; echo injected'))

    def test_rejects_invalid_volume(self):
        self.assert_no_create(self.run_script(STATE_VOLUME='foo,dst=/oops'))

    def test_rejects_unsupported_restart_policy(self):
        self.assert_no_create(self.run_script(RDC_RESTART_POLICY='always'))

    def test_resource_overrides_are_passed_as_arguments(self):
        p = self.run_script(RDC_CPUS='2.0', RDC_MEMORY='2048m', RDC_PIDS_LIMIT='900')
        self.assertEqual(p.returncode, 0, p.stderr)
        args = next(c for c in self.calls() if c[0] == 'create')
        self.assertEqual(args[args.index('--cpus') + 1], '2.0')
        self.assertEqual(args[args.index('--memory') + 1], '2048m')
        self.assertEqual(args[args.index('--pids-limit') + 1], '900')

    def test_uninstall_refuses_unmanaged_container(self):
        p = self.run_script('uninstall.sh', FAKE_EXISTING='1', FAKE_OWNER='unrelated')
        self.assertNotEqual(p.returncode, 0)
        self.assertFalse(any(c[0] == 'rm' for c in self.calls()))

    def test_update_requires_target_image(self):
        self.assertNotEqual(self.run_script('update.sh').returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_entrypoint_requires_ack_before_inspecting_host(self):
        p = self.run_script('docker-entrypoint.sh', RDC_ALLOW_HOST_ADMIN='false')
        self.assertEqual(p.returncode, 64)

    def test_hostsh_requires_ack(self):
        p = self.run_script('scripts/hostsh', args=('echo', 'test'), RDC_ALLOW_HOST_ADMIN='false')
        self.assertEqual(p.returncode, 64)

    def test_hostsh_preserves_argv_and_uses_clean_environment(self):
        (self.tmp / 'nsenter').write_text('#!/usr/bin/env python3\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n')
        (self.tmp / 'nsenter').chmod(0o755)
        value = 'two words; $(touch never-execute)'
        p = self.run_script('scripts/hostsh', args=('printf', '%s', value))
        self.assertEqual(p.returncode, 0, p.stderr)
        args = json.loads(p.stdout)
        self.assertEqual(args[-3:], ['printf', '%s', value])
        self.assertIn('--root', args)
        self.assertIn('--wd', args)
        self.assertIn('-i', args)

    def test_all_shell_files_parse(self):
        for path in list(ROOT.rglob('*.sh')) + [ROOT / 'scripts/hostsh']:
            p = subprocess.run(['bash', '-n', str(path)], capture_output=True, text=True)
            self.assertEqual(p.returncode, 0, p.stderr)


if __name__ == '__main__':
    unittest.main()
