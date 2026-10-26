"""Exercise terminal ownership with a real controlling PTY, never Rosetta."""
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import sys
import tempfile
import time
import unittest

HARNESS = Path(__file__).resolve().parents[1] / 'build/InteractiveHarness'


@unittest.skipUnless(HARNESS.exists(), 'compile InteractiveHarness using scripts/test.sh')
class InteractiveCommandTests(unittest.TestCase):
    def run_session(self, body, answer=b'confirm\n', expect_no_descendant=False, platform_shell=False):
        with tempfile.TemporaryDirectory(prefix='DNF interactive ') as tmp:
            script = Path(tmp) / 'installer fixture.py'
            marker = Path(tmp) / 'child.pid'
            if platform_shell:
                script.write_text('printf "%s" "$$" > "$(dirname "$0")/child.pid"\n' + body)
            else:
                script.write_text("import os\nfrom pathlib import Path\nPath(__file__).with_name('child.pid').write_text(str(os.getpid()))\n" + body)
            pid, master = pty.fork()  # child becomes a session leader and owns stdin's terminal
            if pid == 0:
                os.execv(str(HARNESS), [str(HARNESS), "/bin/sh" if platform_shell else sys.executable, str(script), 'argument with spaces'])
            output = b''
            sent = False
            finished = False
            try:
                deadline = time.monotonic() + 4
                while time.monotonic() < deadline:
                    if select.select([master], [], [], .05)[0]:
                        try:
                            data = os.read(master, 65536)
                        except OSError:
                            break
                        if not data: break
                        output += data
                    if b'INPUT_READY' in output and not sent:
                        os.write(master, answer); sent = True
                    child, status = os.waitpid(pid, os.WNOHANG)
                    if child:
                        finished = True
                        break
                if not finished:
                    for _ in range(10):
                        child, status = os.waitpid(pid, os.WNOHANG)
                        if child:
                            finished = True
                            break
                        time.sleep(.02)
                self.assertTrue(finished, f'installer stopped before terminal input could complete: {output.decode(errors="replace")}')
                # Drain final output already queued before exit.
                while select.select([master], [], [], .05)[0]:
                    try:
                        data = os.read(master, 65536)
                        if not data: break
                        output += data
                    except OSError: break
                descendant = Path(tmp) / 'descendant.pid'
                if expect_no_descendant and descendant.exists():
                    descendant_pid = int(descendant.read_text())
                    gone = False
                    for _ in range(50):
                        try: os.kill(descendant_pid, 0)
                        except ProcessLookupError:
                            gone = True
                            break
                        time.sleep(.02)
                    self.assertTrue(gone, 'cancelled installer left its helper process alive')
                return os.waitstatus_to_exitcode(status), output.decode(errors='replace')
            finally:
                # Only fixture processes in this fresh PTY session are terminated.
                descendant = Path(tmp) / 'descendant.pid'
                if descendant.exists():
                    try: os.kill(int(descendant.read_text()), signal.SIGKILL)
                    except ProcessLookupError: pass
                if marker.exists():
                    try: os.kill(int(marker.read_text()), signal.SIGKILL)
                    except ProcessLookupError: pass
                if not finished:
                    try: os.kill(pid, signal.SIGKILL)
                    except ProcessLookupError: pass
                    try: os.waitpid(pid, 0)
                    except ChildProcessError: pass
                os.close(master)

    def test_interactive_input_and_foreground_handoff(self):
        code, output = self.run_session('''import os,sys
assert os.tcgetpgrp(0) == os.getpgrp(), 'installer does not own foreground terminal'
assert sys.argv[1] == 'argument with spaces'
print('INPUT_READY', flush=True)
assert input() == 'confirm'
print('INPUT_ACCEPTED', flush=True)
''')
        self.assertEqual(code, 0, output)
        self.assertIn('INPUT_ACCEPTED', output)
        self.assertIn('INTERACTIVE_STATUS=0', output)

    def test_declined_agreement_keeps_nonzero_exit_and_restores_parent(self):
        code, output = self.run_session("import sys\nprint('INPUT_READY', flush=True)\ninput()\nsys.exit(7)\n")
        self.assertEqual(code, 0, output)
        self.assertIn('INTERACTIVE_STATUS=7', output)

    def test_ctrl_c_cancels_child_and_restores_parent(self):
        code, output = self.run_session("print('INPUT_READY', flush=True)\ninput()\n", answer=b'\x03')
        self.assertEqual(code, 0, output)
        self.assertIn('INTERACTIVE_STATUS=', output)
        self.assertNotIn('INTERACTIVE_STATUS=0', output)

    def test_ctrl_z_cancels_stopped_installer_instead_of_hanging(self):
        code, output = self.run_session("print('INPUT_READY', flush=True)\ninput()\n", answer=b'\x1a')
        self.assertEqual(code, 1, output)
        self.assertIn('INTERACTIVE_ERROR=', output)

    def test_noninteractive_launch_refuses_before_starting_child(self):
        p = subprocess.run([str(HARNESS), '/usr/bin/true'], input='', text=True, capture_output=True, timeout=5)
        self.assertEqual(p.returncode, 1)
        self.assertIn('대화형 터미널', p.stderr)

    def test_stopped_installation_cancels_its_descendants(self):
        body = """import os,signal,time
from pathlib import Path
reader,writer = os.pipe()
child = os.fork()
if child == 0:
    os.close(reader)
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    os.write(writer, b'ready'); os.close(writer)
    time.sleep(20)
    os._exit(0)
os.close(writer); os.read(reader, 5); os.close(reader)
Path(__file__).with_name('descendant.pid').write_text(str(child))
print('INPUT_READY', flush=True)
input()
"""
        code, output = self.run_session(body, answer=b'\x1a', expect_no_descendant=True)
        self.assertEqual(code, 1, output)
        self.assertIn('INTERACTIVE_ERROR=', output)

    def test_apple_platform_executable_can_read_terminal_input(self):
        code, output = self.run_session("printf 'INPUT_READY\\n'\nIFS= read -r answer\n[ \"$answer\" = confirm ] || exit 7\nprintf 'INPUT_ACCEPTED\\n'\n", platform_shell=True)
        self.assertEqual(code, 0, output)
        self.assertIn('INPUT_ACCEPTED', output)
        self.assertIn('INTERACTIVE_STATUS=0', output)
