"""Check that journey failures block launch and preserve the last good app."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
MOCK_TOOL = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
root = pathlib.Path(os.environ['BUILD_GATE_ROOT'])
with (root / 'calls.jsonl').open('a') as log:
    log.write(json.dumps({'tool': name, 'args': args, 'require_ui': os.environ.get('CONSTELLATION_REQUIRE_UI_TESTS'), 'ui_binary': os.environ.get('CONSTELLATION_UI_TEST_BINARY')}) + '\n')
if name == 'xcrun':
    if args[:2] == ['swift', 'build']:
        if '--show-bin-path' in args: print(root / 'products')
        sys.exit(int(os.environ.get('MOCK_BUILD_EXIT', '0')))
    if args[:2] == ['swift', 'test']:
        print('Fixture UI journey output')
        sys.exit(int(os.environ.get('MOCK_UI_EXIT', '0')))
    if args[:2] == ['swift', 'scripts/render-icon.swift']:
        pathlib.Path(args[-1]).mkdir(parents=True)
if name == 'iconutil':
    pathlib.Path(args[args.index('-o') + 1]).write_bytes(b'fixture icon')
'''


class BuildGates(unittest.TestCase):
    def fixture(self, real_verifier=False):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        (root / 'scripts').mkdir()
        for name in ['run.sh', 'build.sh', 'build-app.sh']:
            shutil.copy2(SCRIPTS / name, root / 'scripts' / name)
        verify = root / 'scripts/verify-ui.sh'
        if real_verifier:
            shutil.copy2(SCRIPTS / 'verify-ui.sh', verify)
        else:
            verify.write_text('#!/bin/bash\nset -eu\nprintf "%s\\n" "$1" >> "$BUILD_GATE_ROOT/verified-binaries"\nexit "${MOCK_UI_EXIT:-0}"\n')
            verify.chmod(0o755)
        (root / 'products').mkdir()
        binary = root / 'products/ConstellationBar'
        binary.write_text('#!/bin/bash\ntouch "$BUILD_GATE_ROOT/launched"\n')
        binary.chmod(0o755)
        (root / 'products/libNativeMediaHelper.dylib').write_bytes(b'fixture helper')
        (root / 'tools').mkdir()
        for name in ['xcrun', 'codesign', 'iconutil']:
            tool = root / 'tools' / name
            tool.write_text(MOCK_TOOL)
            tool.chmod(0o755)
        (root / 'Resources').mkdir()
        (root / 'Resources/Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString': '0.0.0'}))
        (root / 'VERSION').write_text('0.7.1\n')
        (root / 'LICENSE').write_text('fixture')
        (root / '.build/ConstellationBar.app').mkdir(parents=True)
        (root / '.build/ConstellationBar.app/last-good').write_text('preserve me')
        return root

    def run_script(self, root, name, *arguments, **overrides):
        env = dict(os.environ, PATH=str(root / 'tools') + ':' + os.environ['PATH'], BUILD_GATE_ROOT=str(root))
        env.pop('CONSTELLATION_SIGNING_IDENTITY', None)
        env.update(overrides)
        return subprocess.run(['bash', str(root / 'scripts' / name), *arguments], cwd=root,
                              env=env, capture_output=True, text=True, timeout=15)

    def test_run_does_not_launch_after_failed_journeys(self):
        root = self.fixture()
        result = self.run_script(root, 'run.sh', MOCK_UI_EXIT='7')
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertFalse((root / 'launched').exists())
        self.assertTrue((root / 'verified-binaries').exists())

    def test_run_verifies_then_launches(self):
        root = self.fixture()
        result = self.run_script(root, 'run.sh', '--configure')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((root / 'launched').exists())
        self.assertEqual((root / 'verified-binaries').read_text().strip(), str(root / 'products/ConstellationBar'))

    def test_compile_failure_stops_before_journeys_and_launch(self):
        root = self.fixture()
        result = self.run_script(root, 'run.sh', MOCK_BUILD_EXIT='9')
        self.assertEqual(result.returncode, 9)
        self.assertFalse((root / 'verified-binaries').exists())
        self.assertFalse((root / 'launched').exists())

    def test_failed_packaged_app_journey_preserves_previous_app(self):
        root = self.fixture()
        result = self.run_script(root, 'build-app.sh', MOCK_UI_EXIT='7')
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertEqual((root / '.build/ConstellationBar.app/last-good').read_text(), 'preserve me')
        verified = (root / 'verified-binaries').read_text()
        self.assertIn('app-staging.', verified)
        self.assertIn('Contents/MacOS/ConstellationBar', verified)

    def test_packaged_app_is_replaced_only_after_passing_journeys(self):
        root = self.fixture()
        result = self.run_script(root, 'build-app.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((root / '.build/ConstellationBar.app/Contents/MacOS/ConstellationBar').exists())
        self.assertTrue((root / '.build/ConstellationBar.previous.app/last-good').exists())

    def test_verifier_propagates_failures_and_requires_ui_instead_of_skipping(self):
        root = self.fixture(real_verifier=True)
        result = self.run_script(root, 'verify-ui.sh', str(root / 'products/ConstellationBar'), MOCK_UI_EXIT='8')
        self.assertEqual(result.returncode, 8, result.stderr)
        calls = [json.loads(line) for line in (root / 'calls.jsonl').read_text().splitlines()]
        tests = next(call for call in calls if call['args'][:2] == ['swift', 'test'])
        self.assertEqual(tests['require_ui'], '1')
        self.assertEqual(tests['ui_binary'], str(root / 'products/ConstellationBar'))
        logs = list((root / '.build/ui-journeys').glob('run.*/tests.log'))
        self.assertEqual(len(logs), 1)
        self.assertIn('Fixture UI journey output', logs[0].read_text())


if __name__ == '__main__':
    unittest.main()
