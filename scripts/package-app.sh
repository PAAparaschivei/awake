#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
mkdir -p "$root/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$root/.build/module-cache"
swift build -c release --disable-sandbox
bin=$(swift build -c release --show-bin-path --disable-sandbox)
app="$root/dist/Awake.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
ditto "$bin/Awake" "$app/Contents/MacOS/Awake"
ditto "$root/Resources/Info.plist" "$app/Contents/Info.plist"
printf 'APPL????' > "$app/Contents/PkgInfo"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
printf '%s\n' "$app"
