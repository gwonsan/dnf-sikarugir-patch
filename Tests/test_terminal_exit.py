"""Run the entry scripts on a PTY, replacing only the app at their boundary."""
import os
from pathlib import Path
import pty
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class TerminalExitTests(unittest.TestCase):
    def run_command(self, name, status=0, program='Apple_Terminal', acknowledge=False):
        with tempfile.TemporaryDirectory(prefix='DNF window finish ') as tmp:
            root = Path(tmp)
            script = (ROOT / name).read_text()
            # Substitute the platform prerequisite boundary: even a Mac without
            # Rosetta must never start softwareupdate during a unit test.
            script = script.replace('/usr/bin/arch', '/usr/bin/true').replace('/usr/sbin/softwareupdate', '/usr/bin/false')
            (root / name).write_text(script)
            base = root / ('설치 자료' if name == '던파.command' else '')
            helper = base / 'DNF Web Launcher.app/Contents/MacOS/DNFWebLauncher'
            helper.parent.mkdir(parents=True)
            marker = root / 'close-tty'
            ran = root / 'ran'
            helper.write_text('''#!/bin/bash
if [[ "$1" == --close-terminal ]]; then
  printf '%s' "$2" > "$DNF_TEST_CLOSE"
  exit 0
fi
printf 'done' > "$DNF_TEST_RAN"
exit "$DNF_TEST_STATUS"
''')
            helper.chmod(0o755)
            master, slave = pty.openpty()
            expected_tty = os.ttyname(slave)
            env = dict(os.environ, TERM_PROGRAM=program, DNF_TEST_CLOSE=str(marker), DNF_TEST_RAN=str(ran), DNF_TEST_STATUS=str(status))
            process = subprocess.Popen(['/bin/bash', str(root / name)], stdin=slave,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
            try:
                deadline = time.monotonic() + 5
                while not ran.exists() and time.monotonic() < deadline:
                    time.sleep(.03)
                self.assertTrue(ran.exists())
                if acknowledge:
                    time.sleep(.2)
                    self.assertIsNone(process.poll(), 'error/diagnosis must remain readable before acknowledgment')
                    self.assertFalse(marker.exists(), 'cannot close before user reads the result')
                    os.write(master, b'\n')
                output, error = process.communicate(timeout=3)
                expected_status = 1 if status and name in ['시작.command','설치.command','처음설치.command'] else status
                self.assertEqual(process.returncode, expected_status, output + error)
                if program == 'Apple_Terminal':
                    deadline = time.monotonic() + 3
                    while not marker.exists() and time.monotonic() < deadline:
                        time.sleep(.03)
                    self.assertTrue(marker.exists(), 'completed command must schedule window cleanup')
                    self.assertEqual(marker.read_text(), expected_tty)
                else:
                    self.assertFalse(marker.exists(), 'other terminal apps must be left alone')
            finally:
                if process.poll() is None:
                    process.kill(); process.communicate()
                os.close(master); os.close(slave)

    def test_successful_install_and_menu_exit_do_not_wait_for_enter(self):
        for name in ['던파.command','시작.command','설치.command','처음설치.command','복원.command']:
            with self.subTest(name=name): self.run_command(name)

    def test_errors_wait_before_scheduling_close_and_keep_exit_status(self):
        for name in ['던파.command','시작.command','설치.command','처음설치.command','복원.command','진단.command']:
            with self.subTest(name=name): self.run_command(name, status=42, acknowledge=True)

    def test_successful_diagnosis_remains_readable_until_enter(self):
        self.run_command('진단.command', acknowledge=True)

    def test_other_terminal_apps_are_not_closed(self):
        self.run_command('던파.command', program='iTerm.app')
