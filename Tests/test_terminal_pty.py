"""Exercise the real UI with a harmless helper and synthetic installation state."""
import fcntl
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import tempfile
import termios
import time
import unittest

HARNESS = Path(__file__).resolve().parents[1] / 'build/TerminalHarness'


class Session:
    def __init__(self, body='echo 작업완료', width=100, height=28, extra=None):
        self.temp = tempfile.TemporaryDirectory(prefix='dnf-tui-test-')
        self.root = Path(self.temp.name)
        self.marker = self.root / 'arguments'
        helper = self.root / 'fake helper'
        helper.write_text('#!/bin/bash\nprintf "%s\\n" "$@" >> "$TUI_TEST_ARGS"\n' + body + '\n')
        helper.chmod(0o700)
        self.master, self.slave = pty.openpty()
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack('HHHH', height, width, 0, 0))
        self.original = termios.tcgetattr(self.slave)
        env = dict(os.environ, TERM='xterm-256color', LANG='en_US.UTF-8', TUI_TEST_ARGS=str(self.marker))
        env.pop("NO_COLOR", None)
        env.update(extra or {})
        self.process = subprocess.Popen([str(HARNESS), str(helper)], stdin=self.slave, stdout=self.slave, stderr=self.slave, env=env)
        self.output = b''
        try:
            self.until('무엇을 할까요?' if width >= 36 else '창을')
        except Exception:
            self.close()
            raise

    def pump(self, seconds=.1):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            ready, _, _ = select.select([self.master], [], [], max(0, end-time.monotonic()))
            if ready:
                try:
                    part = os.read(self.master, 65536)
                except OSError:
                    break
                if not part:
                    break
                self.output += part

    def until(self, text, timeout=8):
        end = time.monotonic() + timeout
        needle = text.encode()
        while needle not in self.output and time.monotonic() < end:
            self.pump(.08)
        if needle not in self.output:
            raise AssertionError(f'Missing {text!r}: {self.output.decode(errors="replace")}')

    def send(self, text):
        os.write(self.master, text.encode())

    def finish(self):
        self.process.wait(timeout=8)
        self.pump(.1)
        assert self.process.returncode == 0, self.output.decode(errors='replace')
        restored = termios.tcgetattr(self.slave)
        original = list(self.original)
        # macOS sets PENDIN when switching canonical mode; it is a kernel
        # pending-retype marker, not an input/echo setting owned by this UI.
        restored[3] &= ~termios.PENDIN
        original[3] &= ~termios.PENDIN
        assert restored == original, 'terminal mode was not restored'
        return self.output

    def close(self):
        if self.process.poll() is None:
            self.process.kill()
            self.process.wait()
        os.close(self.master)
        os.close(self.slave)
        self.temp.cleanup()


@unittest.skipUnless(HARNESS.exists(), 'compile TerminalHarness using scripts/test.sh')
class TerminalPTYTests(unittest.TestCase):
    def start(self, **kwargs):
        session = Session(**kwargs)
        self.addCleanup(session.close)
        return session

    def test_arrow_diagnose_and_quit_restores_terminal(self):
        s = self.start()
        self.assertFalse(s.marker.exists())
        self.assertIn(' │ '.encode(), s.output)
        s.send('\x1b[B\r')
        s.until('작업이 완료됐습니다.')
        self.assertEqual(s.marker.read_text().splitlines(), ['--diagnose', '/tmp/Test Game.app'])
        s.send('q')
        output = s.finish()
        self.assertIn(b'\x1b[?25h\x1b[?1049l', output)

    def test_selected_background_stops_before_right_pane(self):
        s = self.start()
        selected = next(line for line in s.output.split(b'\r\n') if '› 1'.encode() in line)
        left, right = selected.split(' │ '.encode(), 1)
        self.assertIn(b'\x1b[38;5;223;48;5;237m', left)
        self.assertIn(b'\x1b[0m', left, 'selection must reset before the divider')
        self.assertNotIn(b'48;5;', right)
        s.send('q')
        s.finish()

    def test_restore_default_cancel_and_explicit_confirm(self):
        s = self.start()
        s.send('3')
        s.until('[1] 취소')
        s.send('\r')
        s.pump(.2)
        self.assertFalse(s.marker.exists())
        s.send('3')
        s.pump(.2)
        s.send('2')
        s.until('작업이 완료됐습니다.')
        self.assertEqual(s.marker.read_text().splitlines(), ['--uninstall'])
        s.send('q')
        s.finish()

    def test_failure_retry_and_redacted_logs(self):
        s = self.start(body='echo "실패 neople://secret-token"; exit 42')
        s.send('1')
        s.until('작업을 완료하지 못했습니다.')
        s.send('r')
        end = time.monotonic() + 5
        while time.monotonic() < end:
            s.pump(.1)
            if s.marker.read_text().count('--install') == 2:
                break
        self.assertEqual(s.marker.read_text().count('--install'), 2)
        s.send('l')
        s.pump(.2)
        self.assertNotIn(b'secret-token', s.output)
        s.send('q')
        s.finish()

    def test_busy_quit_finishes_child_then_exits(self):
        s = self.start(body='echo 진행중; sleep 1; echo finished >> "$TUI_TEST_ARGS"')
        s.send('1')
        s.until('진행중')
        s.send('q')
        s.finish()
        self.assertIn('finished', s.marker.read_text())

    def test_narrow_resize_and_no_color(self):
        s = self.start(width=30, extra={'NO_COLOR': '1'})
        self.assertFalse(s.marker.exists())
        fcntl.ioctl(s.slave, termios.TIOCSWINSZ, struct.pack('HHHH', 28, 60, 0, 0))
        s.until('무엇을 할까요?')
        self.assertNotIn(' │ '.encode(), s.output)
        self.assertNotIn(b'\x1b[33m', s.output)
        s.send('q')
        s.finish()

    def test_dumb_terminal_numeric_and_empty_enter(self):
        s = self.start(extra={'TERM':'dumb'})
        s.send('2\n')
        s.until('작업이 완료됐습니다.')
        s.output = b''
        s.send('\n')
        s.until('무엇을 할까요?')
        s.send('q\n')
        self.assertNotIn(b'\x1b[', s.finish())

    def test_advanced_connection_only_confirmation(self):
        s = self.start()
        s.send('a')
        s.until('연결과 설치 기록만 정리')
        s.send('3')
        s.until('폰트 복원 없이')
        s.send('2')
        s.until('작업이 완료됐습니다.')
        self.assertEqual(s.marker.read_text().splitlines(), ['--uninstall', '--connection-only'])
        s.send('q')
        s.finish()

    def test_sigterm_restores_terminal(self):
        s = self.start()
        s.process.terminate()
        s.finish()

    def test_pipe_is_refused(self):
        p = subprocess.run([str(HARNESS), '/nonexistent-helper'], input='1\n', text=True, capture_output=True)
        self.assertEqual(p.returncode, 1)
        self.assertIn('대화형 터미널', p.stderr)
