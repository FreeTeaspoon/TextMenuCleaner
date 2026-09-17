#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
SDK=${ANDROID_SDK_ROOT:-${ANDROID_HOME:?Set ANDROID_SDK_ROOT to an Android SDK with build-tools 37.0.0}}
BUILD_TOOLS="$SDK/build-tools/37.0.0"
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT

compile_patcher() {
    javac --release 17 -d "$WORK" "$ROOT/module/patcher/MenuPatcher.java"
    "$BUILD_TOOLS/d8" --output "$WORK" "$WORK"/MenuPatcher*.class
    python3 - "$WORK/classes.dex" "$WORK/unaligned.jar" <<'PY'
from pathlib import Path
import sys, zipfile
dex, jar = Path(sys.argv[1]), Path(sys.argv[2])
with zipfile.ZipFile(jar, 'w', zipfile.ZIP_STORED) as z:
    info = zipfile.ZipInfo('classes.dex')
    info.compress_type = zipfile.ZIP_STORED
    info.date_time = (2026, 9, 9, 0, 0, 0)
    z.writestr(info, dex.read_bytes())
PY
    "$BUILD_TOOLS/zipalign" -f 4 "$WORK/unaligned.jar" "$WORK/patcher.jar"
}

pack_module() {
    local dest=$1
    mkdir -p "$WORK/module/payload"
    cp "$ROOT/module/module.prop" "$ROOT/module/config.sh" "$ROOT/module/menu.conf" "$WORK/module/"
    cp "$ROOT"/module/*.sh "$WORK/module/"
    cp "$ROOT/module/payload/offsets.txt" "$WORK/module/payload/"
    cp "$WORK/patcher.jar" "$WORK/module/payload/patcher.jar"
    cp "$ROOT/module/launcher.png" "$WORK/module/launcher.png"
    : > "$WORK/module/skip_mount"
    mkdir -p "$WORK/module/webroot"
    cp -R "$ROOT/module/webroot/." "$WORK/module/webroot/"
    mkdir -p "$WORK/module/META-INF/com/google/android"
    cp "$ROOT/module/META-INF/com/google/android/updater-script" "$WORK/module/META-INF/com/google/android/"
    cp "$ROOT/module/META-INF/com/google/android/update-binary" "$WORK/module/META-INF/com/google/android/"
    python3 - "$WORK/module" "$dest" <<'PY'
from pathlib import Path
import sys, zipfile
root = Path(sys.argv[1])
with zipfile.ZipFile(sys.argv[2], 'w', zipfile.ZIP_DEFLATED) as z:
    for path in sorted(root.rglob('*')):
        if path.is_file():
            info = zipfile.ZipInfo(str(path.relative_to(root)), (2026, 9, 9, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            executable = path.suffix == '.sh' or path.name == 'update-binary'
            info.external_attr = (0o100755 if executable else 0o100644) << 16
            z.writestr(info, path.read_bytes())
PY
}

build_webui() {
    (cd "$ROOT/webui" && npm install && npm run build)
}

compile_patcher
mkdir -p "$ROOT/dist"
if [[ "${1:-}" == "--pack" ]]; then
    build_webui
    pack_module "$ROOT/dist/TextMenuCleaner-Global-1.3.zip"
    echo "Built $ROOT/dist/TextMenuCleaner-Global-1.3.zip"
    exit 0
fi
STOCK=${1:?Usage: build.sh /path/to/original/MiuixEditor.apk}
expected=$(sed -n 's/^STOCK_SHA=//p' "$ROOT/module/config.sh")
actual=$(sha256sum "$STOCK"); actual=${actual%% *}
[[ "$actual" == "$expected" ]] || { echo 'Unsupported source APK hash' >&2; exit 1; }
python3 "$ROOT/patch_editor.py" "$STOCK" "$WORK/patched.apk"
cp "$STOCK" "$WORK/from-patcher.apk"
java -cp "$WORK" MenuPatcher "$WORK/from-patcher.apk" "$ROOT/module/menu.conf" "$ROOT/module/payload/offsets.txt"
python3 - "$WORK/patched.apk" "$WORK/from-patcher.apk" <<'PY'
import hashlib, sys, zipfile
from pathlib import Path
def dex(path):
    with zipfile.ZipFile(path) as z:
        return hashlib.sha256(z.read('classes.dex')).hexdigest()
left, right = dex(sys.argv[1]), dex(sys.argv[2])
if left != right:
    raise SystemExit(f'Java patcher DEX differs from patch_editor.py: {left} vs {right}')
print('Patcher DEX matches build-time editor patch')
PY
cp "$WORK/patched.patch.json" "$ROOT/dist/TextMenuCleaner-Global-1.3.patch.json"
build_webui
pack_module "$ROOT/dist/TextMenuCleaner-Global-1.3.zip"
echo "Built $ROOT/dist/TextMenuCleaner-Global-1.3.zip"
