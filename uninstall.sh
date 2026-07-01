#!/data/data/com.termux/files/usr/bin/bash
#
# uninstall.sh — remove the native grok launcher, install dir, and binaries.
# Leaves ~/.grok (auth/config). sdcard DNS file is removed.
#
set -euo pipefail
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
say(){ printf '\033[1;32m[grok-native]\033[0m %s\n' "$*"; }

say "Removing launcher symlink…"; rm -f "$PREFIX/bin/grok"
say "Removing install dir + versioned binaries…"; rm -rf "$HOME_DIR/agents/grok" "$HOME_DIR/.grok/versions"
rm -f /sdcard/.grokdns 2>/dev/null || true
say "Done. Auth/config left in ~/.grok (rm -rf ~/.grok to remove that too)."
