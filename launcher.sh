#!/data/data/com.termux/files/usr/bin/bash
# grok — native Termux launcher (xAI Grok Build, static musl binary). No proot.
#
# DNS is auto-detected each launch (works root OR no-root):
#   • rooted  → a systemless module supplies a real /etc/resolv.conf (via
#     /etc -> /system/etc), so the PRISTINE binary resolves natively, no patch.
#   • no root → byte-patch the one hardcoded 16-byte "/etc/resolv.conf" string to
#     "/sdcard/.grokdns" and seed that file. Zero root, zero reboot.
# grok-dns.py swaps EITHER direction and only writes on an actual change, so it is
# idempotent and self-correcting: it survives a self-update flipping the string
# back, and it fixes the binary if you move between rooted and no-root setups.
VERSIONS="$HOME/.grok/versions"
DIR="$HOME/agents/grok"
DNS="/sdcard/.grokdns"
GROKBIN="$HOME/.grok/bin/grok"

# Adopt grok's own self-updates (Ctrl+U / `grok update`). grok's updater downloads
# the new binary to ~/.grok/downloads/ and marks it current by repointing the
# symlink ~/.grok/bin/grok at it — but it never touches versions/ or .verified,
# which is all this launcher reads. Without this block a self-update silently keeps
# running the old binary. So: resolve that symlink, parse the version from the
# filename, and promote it into the versions/ store + repoint .verified.
upd="$(readlink -f "$GROKBIN" 2>/dev/null || true)"
case "$upd" in
  */grok-*-linux-aarch64)
    uver="${upd##*/grok-}"; uver="${uver%-linux-aarch64}"
    if [ -f "$upd" ] && printf '%s' "$uver" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      if [ ! -f "$VERSIONS/$uver" ]; then
        cp -f "$upd" "$VERSIONS/$uver" && chmod 700 "$VERSIONS/$uver" \
          && printf '%s' "$uver" > "$VERSIONS/.verified"
      elif [ "$(cat "$VERSIONS/.verified" 2>/dev/null || true)" != "$uver" ]; then
        printf '%s' "$uver" > "$VERSIONS/.verified"
      fi
    fi
    ;;
esac

verified="$(cat "$VERSIONS/.verified" 2>/dev/null || true)"
bin=""
if [ -n "$verified" ] && [ -f "$VERSIONS/$verified" ]; then
  bin="$VERSIONS/$verified"
else
  for c in $(ls -1 "$VERSIONS" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | sort -Vr); do
    [ -f "$VERSIONS/$c" ] && { bin="$VERSIONS/$c"; break; }
  done
fi
[ -n "$bin" ] || { echo "[grok] no installed binary in $VERSIONS — run install.sh." >&2; exit 1; }

# pick DNS mode from whether a real /etc/resolv.conf exists (rooted module)
if [ -s /etc/resolv.conf ] && grep -q '^nameserver' /etc/resolv.conf 2>/dev/null; then
  MODE=native
else
  MODE=sdcard
  grep -qs nameserver "$DNS" 2>/dev/null || printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > "$DNS" 2>/dev/null
fi
python3 "$DIR/grok-dns.py" "$bin" "$MODE" 2>/dev/null || true

exec "$bin" "$@"
