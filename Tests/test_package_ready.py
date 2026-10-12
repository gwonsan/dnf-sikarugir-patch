import hashlib
import importlib.util
import pathlib
import plistlib
import subprocess
import tempfile
import unittest

script = pathlib.Path(__file__).resolve().parents[1] / 'scripts/package-ready.py'
spec = importlib.util.spec_from_file_location('package_ready', script)
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class PackageTests(unittest.TestCase):
    def test_publication_never_replaces_a_destination_created_during_build(self):
        with tempfile.TemporaryDirectory(prefix='dnf publication ') as directory:
            root = pathlib.Path(directory)
            source = root / 'Stage.app'
            destination = root / 'Existing.app'
            source.mkdir()
            destination.mkdir()
            with self.assertRaises(OSError):
                package.publish(source, destination)
            self.assertTrue(source.is_dir())
            self.assertTrue(destination.is_dir())

    def test_only_allowlisted_assets_without_a_prefix_or_engine(self):
        with tempfile.TemporaryDirectory(prefix='dnf package ') as directory:
            root = pathlib.Path(directory)
            template = root / 'Template-1.0.21.app'
            support = template / 'Contents/SharedSupport'
            support.mkdir(parents=True)
            (support / 'prefix').mkdir()
            (support / 'Logs').mkdir()
            (support / 'wine').mkdir()
            (template / 'Contents/Info.plist').write_bytes(plistlib.dumps({'D3DMETAL': 0, 'OtherSetting': 'keep'}))
            archive = root / 'template.tar'
            subprocess.run(['/usr/bin/tar', '-cf', str(archive), '-C', str(root), template.name], check=True)
            assets = {}
            for name in package.ASSET_HASHES:
                path = root / name
                path.write_bytes(b'fixture')
                assets[name] = path
            license = root / 'OFL.txt'
            license.write_text('license fixture')
            expected = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in assets.items()}
            destination = root / 'Ready/DNF.app'
            package.create_bundle(archive, assets, license, destination, hashlib.sha256(archive.read_bytes()).hexdigest(), expected)
            bundle_support = destination / 'Contents/SharedSupport'
            self.assertFalse((bundle_support / 'prefix').exists())
            self.assertFalse((bundle_support / 'wine').exists())
            self.assertFalse((bundle_support / 'Logs').exists())
            self.assertEqual(set(p.name for p in (bundle_support / 'dnf-ready').iterdir()), set(assets) | {'manifest.plist'})
            settings = plistlib.loads((destination / 'Contents/Info.plist').read_bytes())
            self.assertEqual(settings['D3DMETAL'], 1)
            self.assertEqual(settings['OtherSetting'], 'keep')
            self.assertTrue((destination / 'Contents/Resources/DNF-Licenses/SourceHanSans-OFL.txt').is_file())
            with self.assertRaises(Exception):
                package.create_bundle(archive, assets, license, destination, hashlib.sha256(archive.read_bytes()).hexdigest(), expected)
            assets['sourcehansans.ttc'].write_bytes(b'changed')
            with self.assertRaises(Exception):
                package.create_bundle(archive, assets, license, root / 'Tampered.app', hashlib.sha256(archive.read_bytes()).hexdigest(), expected)
            self.assertFalse((root / 'Tampered.app').exists())


if __name__ == '__main__':
    unittest.main()
