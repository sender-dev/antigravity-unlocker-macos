#!/usr/bin/env bash
# Antigravity Unlocker — macOS launcher.
#
# Double-clicked in Finder (the `.command` suffix is what makes Finder run it in
# Terminal) or started by hand: `bash launch.command`. No sudo: on macOS only the
# *write* into a system install needs root, and that goes through the tool's own
# administrator prompt (osascript) when you switch the patch on. Running the whole
# thing under sudo would put the LaunchAgents and the per-user state in root's
# home instead of yours.
#
# Finder starts a .command with a minimal PATH (`/usr/bin:/bin:/usr/sbin:/sbin`),
# so the usual Homebrew and user locations are added here rather than assumed.

if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi
set -u

export PATH="$PATH:/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$HOME/.agy/bin"

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$SELF/ag_unlocker"
chmod +x "$BIN" 2>/dev/null || true

say_error() {
    printf '%s\n' "$1" >&2
    if [ ! -t 2 ]; then
        osascript -e "display dialog \"${1//\"/\\\"}\" with title \"Antigravity Unlocker\" buttons {\"OK\"} default button \"OK\" with icon caution" >/dev/null 2>&1 || true
    else
        read -r -p "Нажмите Enter для выхода..." _ || true
    fi
}

if [ "$(id -u)" -eq 0 ]; then
    say_error "Запускайте без sudo: bash launch.command
Под root программа не видит ваш рабочий стол и искала бы Antigravity
в домашней папке root. Права root ей нужны только на запись патча,
и их она запрашивает сама."
    exit 1
fi

if [ ! -f "$BIN" ]; then
    say_error "Не найден файл программы: $BIN
Распакуйте архив целиком и запустите launch.command из распакованной папки."
    exit 1
fi

# A folder the program cannot run from: a quarantined download, a read-only
# mount, or an unpacking that dropped the permissions. `xattr` is cleared when it
# was set, and a copy in the data dir is used when it simply cannot start.
if ! "$BIN" --version >/dev/null 2>&1; then
    xattr -d com.apple.quarantine "$BIN" 2>/dev/null || true
    chmod +x "$BIN" 2>/dev/null || true
fi
if ! "$BIN" --version >/dev/null 2>&1; then
    HOME_BIN="$HOME/Library/Application Support/agunlocker/ag_unlocker"
    if mkdir -p "$(dirname "$HOME_BIN")" \
        && cp -f "$BIN" "$HOME_BIN.new" \
        && chmod +x "$HOME_BIN.new" \
        && mv -f "$HOME_BIN.new" "$HOME_BIN" \
        && xattr -d com.apple.quarantine "$HOME_BIN" 2>/dev/null || true; then :; fi
    if [ -f "$HOME_BIN" ] && "$HOME_BIN" --version >/dev/null 2>&1; then
        BIN="$HOME_BIN"
    else
        say_error "Программа не запускается ни отсюда, ни из домашней папки: $BIN
Нужен 64-битный macOS (Apple silicon или Intel)."
        exit 1
    fi
fi

# The binary picks the terminal UI by itself (--tui is only said here to be
# plain about it) when it was started from a terminal.
exec "$BIN" "$@"