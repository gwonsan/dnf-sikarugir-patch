import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class StartCommandTests(unittest.TestCase):
    def test_rerun_without_downloaded_app_reaches_installer(self):
        with tempfile.TemporaryDirectory(prefix="DNF start ") as tmp:
            root = pathlib.Path(tmp)
            shutil.copy2(ROOT / "시작.command", root)
            binary = root / "DNF Web Launcher.app/Contents/MacOS/DNFWebLauncher"
            binary.parent.mkdir(parents=True)
            # Replace the external installer so the test cannot modify the game or URL handler.
            binary.write_text('#!/bin/bash\n[[ "$1" == --install-ready && "$2" == "${0%/DNF Web Launcher.app/*}/DNF.app" ]] || exit 99\nprintf "%s\\n" "$1" "$2" > "${0%/DNF Web Launcher.app/*}/called"\nexit 42\n')
            binary.chmod(0o755)
            result = subprocess.run(["/bin/bash", str(root / "시작.command")], stdin=subprocess.DEVNULL, capture_output=True, text=True)
            self.assertTrue((root / "called").exists(), result.stdout)
            self.assertEqual((root / "called").read_text().splitlines(), ["--install-ready", str(root / "DNF.app")])
            self.assertEqual(result.returncode, 1)


    def test_install_commands_clear_only_themselves_and_helper_before_launch(self):
        for command in ["시작.command", "설치.command", "처음설치.command"]:
            with self.subTest(command=command), tempfile.TemporaryDirectory(prefix="DNF permission ") as tmp:
                root = pathlib.Path(tmp)
                script = root / command
                shutil.copy2(ROOT / command, script)
                helper = root / "DNF Web Launcher.app"
                binary = helper / "Contents/MacOS/DNFWebLauncher"
                binary.parent.mkdir(parents=True)
                binary.write_text('#!/bin/bash\n/usr/bin/xattr -p com.apple.quarantine "$0" >/dev/null 2>&1 && exit 99\nprintf ready > "${0%/DNF Web Launcher.app/*}/called"\nexit 42\n')
                binary.chmod(0o755)
                outside = root / "unrelated"
                outside.write_text("keep")
                (helper / "external-link").symlink_to(outside)
                (helper / "dangling-link").symlink_to(root / "absent")
                for file in [script, helper, binary, outside]:
                    subprocess.run(["/usr/bin/xattr", "-w", "com.apple.quarantine", "0083;test;DNF;", str(file)], check=True)
                    subprocess.run(["/usr/bin/xattr", "-w", "org.dnf.keep", "keep", str(file)], check=True)
                result = subprocess.run(["/bin/bash", str(script)], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15)
                self.assertTrue((root / "called").exists(), result.stdout + result.stderr)
                self.assertEqual(result.returncode, 1)
                for file in [script, helper, binary]:
                    self.assertNotEqual(subprocess.run(["/usr/bin/xattr", "-p", "com.apple.quarantine", str(file)], capture_output=True).returncode, 0)
                    self.assertEqual(subprocess.check_output(["/usr/bin/xattr", "-p", "org.dnf.keep", str(file)], text=True).strip(), "keep")
                self.assertEqual(subprocess.run(["/usr/bin/xattr", "-p", "com.apple.quarantine", str(outside)], capture_output=True).returncode, 0)


if __name__ == "__main__":
    unittest.main()
