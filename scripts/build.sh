#!/bin/bash
# Offline, dependency-free universal macOS input method and Installer package build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SDK="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
BUILD="$ROOT/build"
APP="$BUILD/SoumaoWubi.app"
STAGE="$BUILD/package-root"
PACKAGE="$ROOT/搜猫五笔-1.3.1.pkg"
COMPONENT="$BUILD/SoumaoWubi-component.pkg"
mkdir -p "$BUILD" "$BUILD/module-cache" "$APP/Contents/MacOS" "$APP/Contents/Resources"
export CLANG_MODULE_CACHE_PATH="$BUILD/module-cache"
export SWIFT_MODULECACHE_PATH="$BUILD/module-cache"
for required in Sources/main.swift Sources/NetworkGuard.c Sources/NetworkGuard.h Resources/wubi.tsv; do
    [[ -f "$required" ]] || { echo "Missing required source: $required" >&2; exit 1; }
done
/usr/bin/xcrun swift -module-cache-path "$BUILD/module-cache" scripts/generate-icons.swift "$ROOT/Resources"
/usr/bin/xcrun swift -module-cache-path "$BUILD/module-cache" scripts/generate-pinyin.swift "$ROOT/Resources/wubi.tsv" "$ROOT/Resources/pinyin.tsv"
for arch in arm64 x86_64; do
    /usr/bin/xcrun clang -O2 -arch "$arch" -mmacosx-version-min=14.0 -isysroot "$SDK" \
        -c Sources/NetworkGuard.c -o "$BUILD/NetworkGuard-$arch.o"
    /usr/bin/xcrun swiftc -O -swift-version 5 -module-name SoumaoWubi \
        -module-cache-path "$BUILD/module-cache" -target "$arch-apple-macosx14.0" -sdk "$SDK" \
        -import-objc-header Sources/NetworkGuard.h Sources/*.swift "$BUILD/NetworkGuard-$arch.o" \
        -framework AppKit -framework InputMethodKit -framework Carbon -lsandbox \
        -o "$BUILD/SoumaoWubi-$arch"
done
/usr/bin/lipo -create "$BUILD/SoumaoWubi-arm64" "$BUILD/SoumaoWubi-x86_64" -output "$APP/Contents/MacOS/SoumaoWubi"
/bin/cp Resources/Info.plist "$APP/Contents/Info.plist"
for resource in wubi.tsv pinyin.tsv Soumao.icns SoumaoMenu.tiff; do
    /bin/cp "Resources/$resource" "$APP/Contents/Resources/$resource"
done
for locale in zh-Hans en; do
    mkdir -p "$APP/Contents/Resources/$locale.lproj"
    /bin/cp "Resources/$locale.lproj/InfoPlist.strings" "$APP/Contents/Resources/$locale.lproj/InfoPlist.strings"
done
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - --timestamp=none "$APP"
/usr/bin/codesign --verify --strict --verbose=2 "$APP"
# This directory is exclusively build-generated staging, never an installation target.
if [[ -d "$STAGE" ]]; then /bin/rm -rf "$STAGE"; fi
mkdir -p "$STAGE/Library/Input Methods"
/usr/bin/ditto "$APP" "$STAGE/Library/Input Methods/SoumaoWubi.app"
/usr/bin/pkgbuild --analyze --root "$STAGE" "$BUILD/components.plist"
/usr/libexec/PlistBuddy -c 'Add :0:BundleIsRelocatable bool false' "$BUILD/components.plist"
/usr/libexec/PlistBuddy -c 'Set :0:BundleOverwriteAction upgrade' "$BUILD/components.plist"
/usr/bin/pkgbuild --root "$STAGE" --component-plist "$BUILD/components.plist" \
    --identifier com.soumao.inputmethod.Wubi.pkg --version 1.3.1 --install-location / \
    --ownership recommended --scripts "$ROOT/scripts/package-scripts" "$COMPONENT"
/usr/bin/productbuild --distribution "$ROOT/Resources/Distribution.xml" \
    --resources "$ROOT/Resources/Installer" --package-path "$BUILD" "$PACKAGE"
/usr/bin/shasum -a 256 "$PACKAGE"
echo "Built: $PACKAGE"
