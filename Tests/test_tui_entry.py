import os
import pathlib
import pty
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class TUIEntryTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue((ROOT / "던파.command").is_file(), "The unified entry command is missing")
        self.tmp = tempfile.TemporaryDirectory(prefix="DNF menu 한글 ")
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        self.script = self.root / "던파.command"
        shutil.copy2(ROOT / "던파.command", self.script)
        self.helper = self.root / "설치 자료/DNF Web Launcher.app"
        self.binary = self.helper / "Contents/MacOS/DNFWebLauncher"

    def install_helper(self, status=0):
        self.binary.parent.mkdir(parents=True)
        # The real helper installs apps and registers URL handlers. Replace that
        # boundary only; run the actual entry script and macOS xattr handling.
        self.binary.write_text(
            '#!/bin/bash\nprintf "%s\\0" "$@" > "$2/called"\n'
            f'exit {status}\n'
        )
        self.binary.chmod(0o755)

    def run_entry(self):
        return subprocess.run(["/bin/bash", str(self.script)], stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, timeout=10)

    def test_missing_helper_explains_extraction_without_building(self):
        scripts = self.root / "scripts"
        scripts.mkdir()
        (scripts / "build.sh").write_text('#!/bin/bash\ntouch "${0%/scripts/build.sh}/built"\n')
        result = self.run_entry()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("압축", result.stdout + result.stderr)
        self.assertIn("설치 자료", result.stdout + result.stderr)
        self.assertFalse((self.root / "built").exists())

    def test_spaced_package_path_reaches_menu_as_one_exact_argument(self):
        self.install_helper()
        result = self.run_entry()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / "called").read_bytes().split(b"\0")[:-1],
                         [b"--menu", os.fsencode(self.root)])

    def test_helper_failure_status_is_preserved(self):
        self.install_helper(status=42)
        result = self.run_entry()
        self.assertEqual(result.returncode, 42, result.stdout + result.stderr)

    def test_failure_waits_for_enter_in_terminal_and_preserves_status(self):
        self.install_helper(status=42)
        master, slave = pty.openpty()
        try:
            process = subprocess.Popen(["/bin/bash", str(self.script)], stdin=slave,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                time.sleep(0.3)
                self.assertIsNone(process.poll(), "Terminal closed before the error could be read")
                os.write(master, b"\n")
                process.communicate(timeout=10)
                self.assertEqual(process.returncode, 42)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate()
        finally:
            os.close(master)
            os.close(slave)

    def test_quarantine_scope_excludes_ready_app_unrelated_files_and_link_targets(self):
        self.install_helper()
        ready = self.root / "설치 자료/DNF.app"
        ready.mkdir()
        outside = self.root / "unrelated"
        outside.write_text("keep")
        (self.helper / "external-link").symlink_to(outside)
        (self.helper / "dangling-link").symlink_to(self.root / "absent")
        for path in [self.script, self.helper, self.binary, ready, outside]:
            subprocess.run(["/usr/bin/xattr", "-w", "com.apple.quarantine", "0083;test;DNF;", str(path)], check=True)
            subprocess.run(["/usr/bin/xattr", "-w", "org.dnf.keep", "keep", str(path)], check=True)
        result = self.run_entry()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for path in [self.script, self.helper, self.binary]:
            self.assertNotEqual(subprocess.run(["/usr/bin/xattr", "-p", "com.apple.quarantine", str(path)], capture_output=True).returncode, 0)
            self.assertEqual(subprocess.check_output(["/usr/bin/xattr", "-p", "org.dnf.keep", str(path)], text=True).strip(), "keep")
        for path in [ready, outside]:
            self.assertEqual(subprocess.run(["/usr/bin/xattr", "-p", "com.apple.quarantine", str(path)], capture_output=True).returncode, 0)

    def test_legacy_source_commands_use_new_build_layout(self):
        scripts = self.root / 'scripts'
        scripts.mkdir()
        helper = self.root / 'dist/DNF-Sikarugir-Patch-dev/설치 자료/DNF Web Launcher.app/Contents/MacOS/DNFWebLauncher'
        helper.parent.mkdir(parents=True)
        helper.write_text('#!/bin/bash\nprintf "%s\\n" "$@" > "$TUI_LEGACY_ARGS"\n')
        helper.chmod(0o755)
        (scripts / 'build.sh').write_text('#!/bin/bash\nexit 0\n')
        marker = self.root / 'legacy-args'
        for name, command in [('설치.command', '--install'), ('처음설치.command', '--setup'), ('복원.command', '--uninstall'), ('진단.command', '--diagnose')]:
            shutil.copy2(ROOT / name, self.root / name)
            result = subprocess.run(['/bin/bash', str(self.root / name)], stdin=subprocess.DEVNULL,
                                    capture_output=True, text=True, timeout=10,
                                    env=dict(os.environ, TUI_LEGACY_ARGS=str(marker)))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(marker.read_text().splitlines()[0], command)

    def test_helper_bundle_symlink_is_rejected_before_external_execution(self):
        self.install_helper()
        outside = self.root / "outside.app"
        self.helper.rename(outside)
        self.helper.symlink_to(outside)
        result = self.run_entry()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "called").exists())


if __name__ == "__main__":
    unittest.main()
