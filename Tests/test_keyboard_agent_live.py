"""Opt-in installed-agent lifecycle regression. Requires user-granted TCC permissions.

Set DNF_LIVE_KEYBOARD_HELPER to the installed nested app and
DNF_LIVE_KEYBOARD_WRAPPER to its existing enabled profile's wrapper.
Never types keys, reads authentication arguments, or grants permissions.
"""
import os
from pathlib import Path
import signal
import subprocess
import time
import unittest

HELPER = os.environ.get('DNF_LIVE_KEYBOARD_HELPER')
WRAPPER = os.environ.get('DNF_LIVE_KEYBOARD_WRAPPER')

@unittest.skipUnless(HELPER and WRAPPER, 'opt-in live installed-agent test')
class InstalledAgentLifecycleTests(unittest.TestCase):
    def test_intentional_initial_pause_keeps_agent_ready(self):
        app = Path(HELPER).resolve()
        executable = str(app / 'Contents/MacOS/DNFWebLauncher')
        def pids():
            rows = subprocess.check_output(['/bin/ps', '-axo', 'pid=,comm='], text=True).splitlines()
            return [int(row.strip().split(None, 1)[0]) for row in rows if len(row.strip().split(None, 1)) == 2 and row.strip().split(None, 1)[1] == executable]
        self.assertFalse(pids(), 'close only the keyboard agent before this isolated lifecycle test')
        launch = subprocess.Popen(['/usr/bin/open', '-W', '-n', '-g', str(app), '--args', '--keyboard-agent', WRAPPER])
        try:
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline and launch.poll() is None:
                time.sleep(.1)
            self.assertIsNone(launch.poll(), 'agent exited during its intentional initial pause')
            self.assertEqual(len(pids()), 1, 'one actual agent remains ready')
        finally:
            for pid in pids():
                os.kill(pid, signal.SIGTERM)
            try:
                launch.wait(timeout=5)
            except subprocess.TimeoutExpired:
                launch.terminate()
                launch.wait(timeout=5)
