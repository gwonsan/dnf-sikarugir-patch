#!/usr/bin/env python3
"""Build a prefix-free ready app from verified official inputs."""
import argparse
import ctypes
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

TEMPLATE_HASH = 'bbe996e4e4375318485953d0c7818b7b4b0a4dc1f13303bcc584f99f7602f78d'
ASSET_HASHES = {
    'sourcehansans.ttc': 'e7d21914e6426157fda3f40dbd53df643dd2e5b9bce6e58790d76d666d89a538',
    'NeopleCustomURLStarter.exe': '74515197c22f7523d03a65592f73da6d7c10209e74fc06888fc0045b21f7f743',
    'NeopleInstallerStarter.exe': 'ea90a913e52b1fd8864385ea1b1a329044ef1f3e43d88981d9e3bd87cad437e0',
}


def verify(path, digest):
    if path.is_symlink() or not path.is_file():
        raise ValueError(f'Expected a regular file: {path.name}')
    with path.open('rb') as file:
        hasher = hashlib.sha256()
        for chunk in iter(lambda: file.read(1024 * 1024), b''):
            hasher.update(chunk)
        actual = hasher.hexdigest()
    if actual != digest:
        raise ValueError(f'SHA-256 mismatch: {path.name}')


def publish(source, destination):
    # macOS RENAME_EXCL also rejects an empty destination created during extraction.
    rename = ctypes.CDLL(None, use_errno=True).renamex_np
    rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    if rename(os.fsencode(source), os.fsencode(destination), 0x00000004) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), str(destination))


def create_bundle(template, assets, font_license, destination, template_hash=TEMPLATE_HASH, asset_hashes=ASSET_HASHES):
    if destination.suffix.lower() != '.app' or os.path.lexists(destination):
        raise ValueError('Refusing to overwrite an existing app or symlink.')
    if set(assets) != set(ASSET_HASHES) or set(asset_hashes) != set(ASSET_HASHES):
        raise ValueError('Only the font and two official starter files may be included.')
    verify(template, template_hash)
    for name, path in assets.items():
        verify(path, asset_hashes[name])
    if not font_license.is_file() or font_license.is_symlink():
        raise ValueError('Source Han Sans license is required.')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.dnf-ready-package-', dir=destination.parent) as stage:
        stage = Path(stage)
        subprocess.run(['/usr/bin/tar', '-xf', str(template), '-C', str(stage)], check=True)
        app = stage / 'Template-1.0.21.app'
        support = app / 'Contents/SharedSupport'
        for name in ['prefix', 'wine', 'wswine.bundle', 'Logs', 'winetricks']:
            path = support / name
            if path.is_symlink() or path.is_file():
                path.unlink()
            elif path.is_dir():
                shutil.rmtree(path)
        asset_dir = support / 'dnf-ready'
        asset_dir.mkdir()
        for name, path in assets.items():
            shutil.copyfile(path, asset_dir / name)
        (asset_dir / 'manifest.plist').write_bytes(plistlib.dumps(asset_hashes))
        licenses = app / 'Contents/Resources/DNF-Licenses'
        licenses.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(font_license, licenses / 'SourceHanSans-OFL.txt')
        info = app / 'Contents/Info.plist'
        settings = plistlib.loads(info.read_bytes())
        settings.update({
            'CFBundleName': 'DNF',
            'CFBundleIdentifier': f'io.github.dnf-sikarugir-patch.prepared.{uuid.uuid4()}',
            'DNFReadyVersion': '1', 'DNFPatchBootstrapVersion': '1',
            'D3DMETAL': 1, 'D9VK': 1, 'CNC_DDRAW': 1, 'Skip Mono': 1, 'Skip Gecko': 1,
            'Program Name and Path': '/Program Files (x86)/NeoplePlugin/NeopleCustomURLStarter.exe',
            'Program Flags': '',
        })
        info.write_bytes(plistlib.dumps(settings))
        publish(app, destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--template', type=Path, required=True)
    parser.add_argument('--font', type=Path, required=True)
    parser.add_argument('--plugin-directory', type=Path, required=True)
    parser.add_argument('--font-license', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    assets = {'sourcehansans.ttc': args.font}
    assets.update({name: args.plugin_directory / name for name in ASSET_HASHES if name.endswith('.exe')})
    create_bundle(args.template.resolve(), assets, args.font_license.resolve(), args.destination.absolute())
    print(f'Prepared app created: {args.destination}')


if __name__ == '__main__':
    main()
