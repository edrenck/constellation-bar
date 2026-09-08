"""Exercise distribution gates without contacting Apple or accessing signing keys."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

RELEASE_SCRIPT = Path(__file__).resolve().parents[1] / "release.sh"

MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
name=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
with open(os.environ['RELEASE_TEST_CALLS'],'a') as log: log.write(name+' '+ ' '.join(args)+'\n')
if name=='xcrun':
    if args[:2]==['notarytool','history']: sys.exit(int(os.environ.get('AUTH_EXIT','0')))
    if args[:2]==['notarytool','submit']:
        print(json.dumps({'id':'fixture-submission', 'status':os.environ.get('APPLE_STATUS','Accepted')}))
        sys.exit(int(os.environ.get('MOCK_SUBMIT_EXIT','0')))
    if args[:2]==['notarytool','log']:
        pathlib.Path(args[-1]).write_text('{"issues":[]}')
    if args[:2]==['stapler','validate']: sys.exit(int(os.environ.get('STAPLE_EXIT','0')))
if name=='ditto': pathlib.Path(args[-1]).write_bytes(b'fixture archive')
'''


class ReleaseGates(unittest.TestCase):
    def run_release(self, **overrides):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        (root / 'scripts').mkdir()
        shutil.copy2(RELEASE_SCRIPT, root / 'scripts/release.sh')
        build = root / 'scripts/build-app.sh'
        build.write_text('#!/bin/bash\nmkdir -p .build/ConstellationBar.app\ntouch .build/build-was-run\n')
        build.chmod(0o755)
        (root / 'VERSION').write_text('0.5.0\n')
        (root / 'bin').mkdir()
        for name in ('xcrun', 'ditto', 'codesign', 'lipo', 'spctl'):
            path = root / 'bin' / name
            path.write_text(MOCK)
            path.chmod(0o755)
        calls = root / 'calls'
        env = dict(os.environ, PATH=str(root / 'bin') + ':' + os.environ['PATH'],
                   RELEASE_TEST_CALLS=str(calls),
                   CONSTELLATION_SIGNING_IDENTITY='Developer ID Application: Fixture (TESTTEAM)',
                   CONSTELLATION_NOTARY_PROFILE='fixture-profile', **overrides)
        result = subprocess.run(['bash', str(root / 'scripts/release.sh')], env=env,
                                capture_output=True, text=True, timeout=15)
        return root, result, calls.read_text() if calls.exists() else ''

    def test_missing_credentials_stop_before_build(self):
        root, result, calls = self.run_release(AUTH_EXIT='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((root / '.build/build-was-run').exists())
        self.assertNotIn('notarytool submit', calls)

    def test_invalid_apple_response_never_creates_distribution(self):
        root, result, calls = self.run_release(APPLE_STATUS='Invalid')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((root / '.build/distribution').exists())
        self.assertNotIn('stapler staple', calls)
        self.assertEqual(len(list(root.glob('.build/notarization-report.*/apple-log.json'))), 1)

    def test_in_progress_or_failed_submission_never_publishes(self):
        for options in ({'APPLE_STATUS': 'In Progress'}, {'MOCK_SUBMIT_EXIT': '1'}):
            with self.subTest(options=options):
                root, result, calls = self.run_release(**options)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((root / '.build/distribution').exists())
                self.assertNotIn('stapler staple', calls)

    def test_stapling_failure_prevents_distribution(self):
        root, result, calls = self.run_release(STAPLE_EXIT='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((root / '.build/distribution').exists())
        self.assertNotIn('spctl ', calls)

    def test_accepted_stapled_assessed_build_has_final_checksum(self):
        root, result, calls = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('stapler validate', calls)
        self.assertIn('spctl --assess', calls)
        distribution = root / '.build/distribution'
        self.assertTrue((distribution / 'ConstellationBar-0.5.0-universal.zip').exists())
        check = subprocess.run(['shasum', '-a', '256', '-c', 'SHA256SUMS'], cwd=distribution,
                               capture_output=True, text=True)
        self.assertEqual(check.returncode, 0, check.stderr)


if __name__ == '__main__':
    unittest.main()
