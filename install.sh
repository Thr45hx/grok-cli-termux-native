#!/data/data/com.termux/files/usr/bin/bash
#
# install.sh — xAI Grok Build CLI (grok), native on Termux (aarch64). No proot, no root.
#
# Grok Build is a statically-linked musl binary that runs directly on the kernel.
# The only thing that fails on Termux is DNS: musl reads /etc/resolv.conf, which
# can't exist (/etc -> /system/etc, read-only). This installer byte-patches that
# one hardcoded 16-char string -> /sdcard/.grokdns and keeps that file populated,
# so DNS resolves natively with zero root and zero proot.
#
set -euo pipefail

say(){ printf '\033[1;32m[grok-native]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31m[grok-native] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
VERSIONS="$HOME_DIR/.grok/versions"
DIR="$HOME_DIR/agents/grok"
DNS="/sdcard/.grokdns"
CHANNEL="${GROK_CHANNEL:-stable}"
PLATFORM="linux-aarch64"
PRIMARY="https://x.ai/cli"
FALLBACK="https://storage.googleapis.com/grok-build-public-artifacts/cli"
RAW="https://raw.githubusercontent.com/Thr45hx/grok-cli-termux-native/main"

# 0) sanity ------------------------------------------------------------------
[ -d "$PREFIX" ] || die "Not a Termux environment."
case "$(uname -m)" in aarch64|arm64) ;; *) die "arm64/aarch64 only (found $(uname -m)).";; esac

# source dir (support curl | bash) ------------------------------------------
SRC="$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)"
need=0; for f in launcher.sh grok-dns-patch.py; do [ -f "$SRC/$f" ] || need=1; done
if [ "$need" = 1 ]; then
  command -v curl >/dev/null || die "curl required to fetch sources."
  SRC="$(mktemp -d)"; say "Fetching source files…"
  for f in launcher.sh grok-dns-patch.py; do curl -fsSL "$RAW/$f" -o "$SRC/$f" || die "fetch $f failed"; done
fi

# 1) deps --------------------------------------------------------------------
say "Installing base packages (python curl)…"
pkg update -y >/dev/null 2>&1 || true
pkg install -y python curl >/dev/null || die "pkg install failed."

# 2) resolve version ---------------------------------------------------------
VERSION="${1:-}"; BASE="$PRIMARY"
if [ -z "$VERSION" ]; then
  say "Resolving latest $CHANNEL version…"
  VERSION="$(curl -fsSL --max-time 15 "$PRIMARY/$CHANNEL" 2>/dev/null || true)"
  [ -z "$VERSION" ] && { VERSION="$(curl -fsSL --max-time 15 "$FALLBACK/$CHANNEL" 2>/dev/null || true)"; BASE="$FALLBACK"; }
  [ -n "$VERSION" ] || die "could not resolve latest $CHANNEL version."
fi
printf '%s' "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+' || die "bad version '$VERSION'."
say "Version: $VERSION"

# 3) download ----------------------------------------------------------------
mkdir -p "$VERSIONS"
tmp="$VERSIONS/$VERSION.tmp"
say "Downloading grok $VERSION ($PLATFORM)…"
if ! curl -fsSL --max-time 600 "$BASE/grok-$VERSION-$PLATFORM" -o "$tmp"; then
  say "Primary failed — trying GCS fallback…"
  curl -fsSL --max-time 600 "$FALLBACK/grok-$VERSION-$PLATFORM" -o "$tmp" || die "download failed."
fi
chmod +x "$tmp"
file "$tmp" | grep -q "statically linked" || say "WARN: binary not statically linked; native path may differ."

# 4) sdcard DNS: file + 16-byte patch ---------------------------------------
grep -qs nameserver "$DNS" 2>/dev/null || printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > "$DNS" 2>/dev/null || say "WARN: cannot write $DNS — run termux-setup-storage."
python3 "$SRC/grok-dns-patch.py" "$tmp"
grep -a -q '/etc/resolv.conf' "$tmp" && die "resolv string still present after patch." || true

# 5) smoke test (--version needs no DNS) ------------------------------------
smoke="$(mktemp -d)"
HOME="$smoke" timeout -s KILL 25 "$tmp" --version >/dev/null 2>&1 || { rm -rf "$smoke" "$tmp"; die "binary failed --version smoke test."; }
rm -rf "$smoke"

# 6) promote + retain latest+prev -------------------------------------------
mv "$tmp" "$VERSIONS/$VERSION"
printf '%s\n' "$VERSION" > "$VERSIONS/.verified"
printf '%s'   "$VERSION" > "$VERSIONS/.dns-patched"
prev="$(ls -1 "$VERSIONS" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -2 | head -1)"
for old in "$VERSIONS"/*; do b="$(basename "$old")"; case "$b" in .*) continue;; esac
  [ -f "$old" ] && [ "$b" != "$VERSION" ] && [ "$b" != "$prev" ] && rm -f "$old"; done

# 7) launcher + patcher ------------------------------------------------------
mkdir -p "$DIR"
install -m644 "$SRC/grok-dns-patch.py" "$DIR/grok-dns-patch.py"
install -m755 "$SRC/launcher.sh" "$DIR/launcher.sh"
ln -sf "$DIR/launcher.sh" "$PREFIX/bin/grok"

echo
say "Installed grok $VERSION — native, no proot, no root."
say "Auth:  export XAI_API_KEY=xai-...   or run 'grok' (browser 'Sign in with Grok')."
say "Try:   grok -p \"hello from native Termux\""
