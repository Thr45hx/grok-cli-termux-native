#!/data/data/com.termux/files/usr/bin/bash
#
# install.sh — xAI Grok Build CLI (grok), native on Termux (aarch64). No proot.
#
# Grok Build is a statically-linked musl binary that runs directly on the kernel.
# The only thing that fails on Termux is DNS: musl reads /etc/resolv.conf, which
# can't exist on stock Termux (/etc -> /system/etc, read-only). Two paths, both
# native (no proot), auto-selected:
#   • no root → byte-patch that one hardcoded 16-char string -> /sdcard/.grokdns
#     and keep that file populated (zero root, zero reboot).
#   • rooted  → if a systemless module already provides a real /etc/resolv.conf,
#     the PRISTINE binary resolves natively with no patch at all.
# The installed launcher re-checks this every run and self-corrects.
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
need=0; for f in launcher.sh grok-dns.py; do [ -f "$SRC/$f" ] || need=1; done
if [ "$need" = 1 ]; then
  command -v curl >/dev/null || die "curl required to fetch sources."
  SRC="$(mktemp -d)"; say "Fetching source files…"
  for f in launcher.sh grok-dns.py; do curl -fsSL "$RAW/$f" -o "$SRC/$f" || die "fetch $f failed"; done
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

# 4) DNS mode: pristine-native if a real /etc/resolv.conf exists, else sdcard patch
if [ -s /etc/resolv.conf ] && grep -q '^nameserver' /etc/resolv.conf 2>/dev/null; then
  say "Rooted resolv module detected — keeping pristine binary (native DNS)."
  python3 "$SRC/grok-dns.py" "$tmp" native
else
  say "No /etc/resolv.conf — byte-patching DNS path to $DNS (no root)."
  grep -qs nameserver "$DNS" 2>/dev/null || printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > "$DNS" 2>/dev/null || say "WARN: cannot write $DNS — run termux-setup-storage."
  python3 "$SRC/grok-dns.py" "$tmp" sdcard
  grep -a -q '/etc/resolv.conf' "$tmp" && die "resolv string still present after patch." || true
fi

# 5) smoke test (--version needs no DNS) ------------------------------------
smoke="$(mktemp -d)"
HOME="$smoke" timeout -s KILL 25 "$tmp" --version >/dev/null 2>&1 || { rm -rf "$smoke" "$tmp"; die "binary failed --version smoke test."; }
rm -rf "$smoke"

# 6) promote + retain latest+prev -------------------------------------------
mv "$tmp" "$VERSIONS/$VERSION"
printf '%s\n' "$VERSION" > "$VERSIONS/.verified"
prev="$(ls -1 "$VERSIONS" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -2 | head -1)"
for old in "$VERSIONS"/*; do b="$(basename "$old")"; case "$b" in .*) continue;; esac
  [ -f "$old" ] && [ "$b" != "$VERSION" ] && [ "$b" != "$prev" ] && rm -f "$old"; done

# 7) launcher + patcher ------------------------------------------------------
mkdir -p "$DIR"
install -m644 "$SRC/grok-dns.py" "$DIR/grok-dns.py"
install -m755 "$SRC/launcher.sh" "$DIR/launcher.sh"
ln -sf "$DIR/launcher.sh" "$PREFIX/bin/grok"

echo
say "Installed grok $VERSION — native, no proot."
say "Updates: press Ctrl+U in grok (or run 'grok update'); the launcher adopts the"
say "         new version automatically on the next start."
say "Auth:  export XAI_API_KEY=xai-...   or run 'grok' (browser 'Sign in with Grok')."
say "Try:   grok -p \"hello from native Termux\""
