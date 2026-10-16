#!/usr/bin/env bash
# Builds the macOS bundle: release/AG_<version>_macos/ (+ .tar.gz), laid out like
# the Linux one - the binary, this launcher, the README and the icon.
#
# Run it on a Mac (`bash build_macos.sh`), from the repository root or from
# `macos/`. Cross-compiling from Linux is not supported: `ring` and `webpki`
# compile C against the Apple SDK, so a host without Xcode's toolchain cannot
# produce the ELF-side equivalent of the Linux zigbuild path. On a Mac the
# toolchain is the normal one - `xcode-select --install` for the SDK and linkers,
# rustup for the target below.
#
# The architecture is the host's unless a target is named:
#   bash build_macos.sh                 # host arch, bundle only
#   bash build_macos.sh --universal     # arm64 + x86_64, merged with lipo
#   bash build_macos.sh --target x86_64-apple-darwin
#
# The version comes from Cargo.toml, the same source the other builds use, so a
# bundle is always named for what it actually contains. `AG_FULL_VERSION` is
# exported the way build.rs expects, so a `2.23.1_2` build calls itself that
# rather than plain `2.23.1`.
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' Cargo.toml | head -1)"
[ -n "$VERSION" ] || { echo "не удалось прочитать version из Cargo.toml" >&2; exit 1; }

MODE="single"
TARGET=""
case "${1:-}" in
    --universal) MODE="universal" ;;
    --target)    TARGET="${2:?--target needs a triple}" ;;
    --target=*)  TARGET="${1#--target=}" ;;
    "") ;;
    *) echo "неизвестный аргумент: $1" >&2; exit 2 ;;
esac

if [ "$(uname -s)" != "Darwin" ]; then
    echo "Этот скрипт надо запускать на macOS: сборка линкует C-зависимости" >&2
    echo "(ring, webpki) против Apple SDK, которой на этой машине нет." >&2
    exit 1
fi

command -v cargo >/dev/null || {
    echo "cargo не найден. Поставьте rustup: https://rustup.rs" >&2
    exit 1
}

export AG_FULL_VERSION="$VERSION"

build_one() {
    local triple="$1"
    echo "[INFO] cargo build --release --bin ag_unlocker --target $triple"
    rustup target add "$triple" >/dev/null 2>&1 || true
    cargo build --release --bin ag_unlocker --target "$triple"
    # Ad-hoc sign: on Apple silicon an unsigned Mach-O will not run at all, and
    # the linker's own signature is lost the moment the file is copied or
    # re-written. `-` is the ad-hoc identity - there is no Developer ID here.
    codesign --force --sign - --timestamp=none \
        "target/$triple/release/ag_unlocker"
    echo "$triple"
}

BUNDLE="$ROOT/release/AG_${VERSION}_macos"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE"

if [ "$MODE" = "universal" ]; then
    ARCH="$(uname -m)"
    OTHER="x86_64"; [ "$ARCH" = "x86_64" ] && OTHER="aarch64"
    build_one "${ARCH}-apple-darwin" >/dev/null
    build_one "${OTHER}-apple-darwin" >/dev/null
    lipo -create \
        "target/${ARCH}-apple-darwin/release/ag_unlocker" \
        "target/${OTHER}-apple-darwin/release/ag_unlocker" \
        -output "$BUNDLE/ag_unlocker"
    note="universal (${ARCH} + ${OTHER})"
else
    TRIPLE="${TARGET:-$(rustc -vV | sed -n 's/^host: //p')}"
    case "$TRIPLE" in
        *apple-darwin) ;;
        *) echo "цель $TRIPLE не macOS" >&2; exit 1 ;;
    esac
    build_one "$TRIPLE" >/dev/null
    cp "target/$TRIPLE/release/ag_unlocker" "$BUNDLE/ag_unlocker"
    note="$TRIPLE"
fi

chmod +x "$BUNDLE/ag_unlocker"
cp "$ROOT/macos/launch.command" "$BUNDLE/launch.command"
chmod +x "$BUNDLE/launch.command"
cp "$ROOT/guide.md" "$BUNDLE/README.md"
[ -f "$ROOT/icon.ico" ] || true

# The binary is signed by the build above; a copy loses nothing, but re-sign so
# the bundle as shipped is what was tested.
codesign --force --sign - --timestamp=none "$BUNDLE/ag_unlocker" 2>/dev/null || true

# A .tar.gz for transfer, exec bits preserved - the same shape as the Linux
# bundle so one unpacking routine works for both.
tar -czf "$BUNDLE.tar.gz" -C "$ROOT/release" "AG_${VERSION}_macos"

echo
echo "Готово: $BUNDLE  [$note]"
echo "        $BUNDLE.tar.gz"
echo "Двойной клик по launch.command внутри папки (или: bash launch.command)."
echo "Первый запуск: если macOS ругается на «неопознанного разработчика» —"
echo "  xattr -dr com.apple.quarantine \"$BUNDLE\""