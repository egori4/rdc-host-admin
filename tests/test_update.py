"""Mocked update.sh lifecycle tests: no host Docker calls."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DOCKER = """#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args=sys.argv[1:]
statefile=Path(os.environ['FAKE_STATE'])
state=json.loads(statefile.read_text())
with open(os.environ['FAKE_LOG'], 'a') as f:
    f.write(json.dumps(args)+'\\n')

def save():
    statefile.write_text(json.dumps(state))

if args[0] == 'info':
    print('linux|Ubuntu|["name=seccomp"]')
elif args[:2] == ['context','inspect']:
    print('unix:///var/run/docker.sock')
elif args[:2] == ['image','inspect']:
    print('host-admin')
elif args[:2] == ['container','inspect']:
    name=args[2]
    if name not in state['containers']:
        sys.exit(1)
    print('rdc-host-admin')
elif args[:2] == ['volume','inspect']:
    print('rdc-host-admin')
elif args[0] == 'inspect':
    name=args[1]
    c=state['containers'][name]
    fmt=args[args.index('--format')+1]
    fields={
        'io.egori4.state-volume': 'rdc-host-admin-test-state',
        'Config.Hostname': 'unit-host-admin',
        'HostConfig.NanoCpus': '1000000000',
        'HostConfig.Memory': '1073741824',
        'HostConfig.PidsLimit': '512',
        'HostConfig.RestartPolicy.Name': 'no',
        'State.Running': 'true' if c['running'] else 'false',
    }
    if 'range .Config.Env' in fmt:
        if c['auto'] is not None: print('RDC_AUTO_UPDATE='+c['auto'])
    else:
        for key,value in fields.items():
            if key in fmt:
                print(value)
                break
        else:
            raise RuntimeError('Unknown inspect format: ' + fmt)
elif args[0] == 'stop':
    state['containers'][args[1]]['running']=False
    save()
elif args[0] == 'rename':
    state['containers'][args[2]]=state['containers'].pop(args[1])
    save()
elif args[0] == 'create':
    name=args[args.index('--name')+1]
    env=next(x for x in args if x.startswith('RDC_AUTO_UPDATE='))
    assert env.startswith('RDC_AUTO_UPDATE=')
    state['containers'][name]={'auto':env.split('=',1)[1], 'running':False}
    save()
    print('mock-created')
elif args[0] == 'start':
    state['containers'][args[1]]['running']=True
    save()
elif args[0] == 'pull':
    print('mock-pull')
else:
    raise RuntimeError('Unexpected Docker call: '+str(args))
"""

class UpdatePreservationTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        docker = self.tmp / 'docker'
        docker.write_text(DOCKER)
        docker.chmod(0o755)
        sleep = self.tmp / 'sleep'
        sleep.write_text('#!/bin/sh\nexit 0\n')
        sleep.chmod(0o755)
        self.state = self.tmp / 'state.json'
        self.log = self.tmp / 'docker.jsonl'
        self.env = {
            **os.environ,
            'PATH': str(self.tmp) + os.pathsep + os.environ['PATH'],
            'FAKE_STATE': str(self.state),
            'FAKE_LOG': str(self.log),
            'RDC_ALLOW_HOST_ADMIN': 'true',
            'CONTAINER_NAME': 'rdc-host-admin-test',
        }
        self.env.pop('RDC_AUTO_UPDATE', None)
        for key in ('DOCKER_CONTEXT','DOCKER_HOST'):
            self.env.pop(key, None)

    def update(self, old_setting, **env):
        self.state.write_text(json.dumps({'containers': {
            'rdc-host-admin-test': {'running': True, 'auto': old_setting}}}))
        result=subprocess.run(['bash', str(ROOT/'update.sh'),
                              'egori4/rdc-host-admin:0.2.0'],
                              env={**self.env,**env}, text=True,
                              capture_output=True, timeout=15)
        self.assertEqual(result.returncode,0,result.stderr)
        calls=[json.loads(x) for x in self.log.read_text().splitlines()]
        create=next(c for c in calls if c[0]=='create')
        return create, json.loads(self.state.read_text())

    def test_legacy_container_remains_disabled(self):
        create,state=self.update(None)
        self.assertIn('RDC_AUTO_UPDATE=false',create)
        self.assertIn('rdc-host-admin-test',state['containers'])
        self.assertTrue(state['containers']['rdc-host-admin-test']['running'])
        self.assertEqual(len(state['containers']),2)

    def test_enabled_setting_survives_image_upgrade(self):
        create,_=self.update('true')
        self.assertIn('RDC_AUTO_UPDATE=true',create)

    def test_explicit_setting_overrides_old(self):
        create,_=self.update('true',RDC_AUTO_UPDATE='false')
        self.assertIn('RDC_AUTO_UPDATE=false',create)

if __name__=='__main__':
    unittest.main()
