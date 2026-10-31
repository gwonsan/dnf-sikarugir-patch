#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_name="DNF-Ready-dev"
task_source="${1:-$task_root/build/prepared/DNF.app}"
python3 - "$task_source" "$task_root" <<'PY'
import os
from pathlib import Path
import plistlib
import runpy
import sys
app = Path(sys.argv[1])
package = runpy.run_path(str(Path(sys.argv[2]) / 'scripts/package-ready.py'))
support = app / 'Contents/SharedSupport'
settings = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
if app.is_symlink() or settings.get('DNFReadyVersion') != '1' or settings.get('D3DMETAL') != 1:
    raise SystemExit('Expected an uninitialized prepared DNF.app.')
if any(os.path.lexists(support / name) for name in ['prefix', 'wine', 'wswine.bundle', 'Logs']):
    raise SystemExit('Do not package an initialized app, Wine engine or launcher logs.')
assets = support / 'dnf-ready'
expected = package['ASSET_HASHES']
if assets.is_symlink() or set(p.name for p in assets.iterdir()) != set(expected) | {'manifest.plist'}:
    raise SystemExit('Unexpected ready assets.')
if (assets / 'manifest.plist').is_symlink() or plistlib.loads((assets / 'manifest.plist').read_bytes()) != expected:
    raise SystemExit('Asset manifest differs from pinned files.')
for name, digest in expected.items():
    package['verify'](assets / name, digest)
for license in ['Contents/Resources/DNF-Licenses/SourceHanSans-OFL.txt', 'Contents/Frameworks/renderer/d3dmetal/License.rtf', 'Contents/Frameworks/renderer/d3dmetal/Acknowledgements.rtf']:
    if not (app / license).is_file():
        raise SystemExit('Missing third-party license: ' + license)
print('PASS: pinned assets, D3DMetal, license notices, no prefix/engine/logs')
PY
mkdir -p "$task_root/dist"
task_stage="$(mktemp -d "$task_root/dist/.ready-stage.XXXXXX")"
trap 'rm -rf "$task_stage"' EXIT
task_dist="$task_stage/$task_name"
task_ready="$task_dist/설치 자료/DNF.app"
mkdir -p "$task_dist/설치 자료"
ditto "$task_source" "$task_ready"
bash "$task_root/scripts/build.sh"
ditto "$task_root/dist/DNF-Sikarugir-Patch-dev/설치 자료/DNF Web Launcher.app" "$task_dist/설치 자료/DNF Web Launcher.app"
cp "$task_root/던파.command" "$task_root/README.md" "$task_root/LICENSE" "$task_root/THIRD_PARTY.md" "$task_dist/"
ditto "$task_root/docs/images" "$task_dist/docs/images"
chmod +x "$task_dist/"*.command
ditto -c -k --keepParent --norsrc --noextattr "$task_dist" "$task_stage/$task_name.zip"
rm -rf "$task_root/dist/$task_name"
mv "$task_dist" "$task_root/dist/$task_name"
mv -f "$task_stage/$task_name.zip" "$task_root/dist/$task_name.zip"
echo "준비된 앱 개발 패키지 완료: dist/$task_name.zip"
