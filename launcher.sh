#!/data/data/com.termux/files/usr/bin/bash
# grok — native Termux launcher (xAI Grok Build, static musl binary). No proot, no root.
#
# musl reads /etc/resolv.conf for DNS, which can't exist on Termux (/etc -> /system/etc,
# read-only) — and a static binary ignores LD_PRELOAD, so a preload shim won't help.
# Fix: byte-patch the single hardcoded "/etc/resolv.conf" string -> "/sdcard/.grokdns"
# (same 16 chars) and keep that file populated. Zero root, zero proot. A grok
# self-update restores the original string, so we re-patch once per version.
VERSIONS="/data/data/com.termux/files/home/.grok/versions"
DIR="/data/data/com.termux/files/home/agents/grok"
DNS="/sdcard/.grokdns"

verified="$(cat "$VERSIONS/.verified" 2>/dev/null || true)"
bin=""
if [ -n "$verified" ] && [ -f "$VERSIONS/$verified" ]; then
  bin="$VERSIONS/$verified"
else
  for c in $(ls -1 "$VERSIONS" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | sort -Vr); do
    [ -f "$VERSIONS/$c" ] && { bin="$VERSIONS/$c"; break; }
  done
fi
[ -n "$bin" ] || { echo "[grok] no installed binary in $VERSIONS — run install." >&2; exit 1; }

# keep the sdcard resolv file populated
grep -qs nameserver "$DNS" 2>/dev/null || printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > "$DNS" 2>/dev/null

# byte-patch the binary's resolv path once per version (self-updates reset it)
if [ "$(cat "$VERSIONS/.dns-patched" 2>/dev/null || true)" != "$verified" ]; then
  if python3 "$DIR/grok-dns-patch.py" "$bin" 2>/dev/null; then
    printf '%s' "$verified" > "$VERSIONS/.dns-patched"
  fi
fi

exec "$bin" "$@"
