#!/data/data/com.termux/files/usr/bin/env python3
# Set the grok (static musl) binary's DNS-config path in place. Both targets are
# exactly 16 bytes, so it's a byte-for-byte swap (no length change, no relocation):
#
#   native  -> "/etc/resolv.conf"   (rooted: a systemless resolv module provides it)
#   sdcard  -> "/sdcard/.grokdns"   (no root: the only short, app-writable path)
#
# Called by launcher.sh with the chosen mode. Idempotent and bidirectional: it only
# writes when the binary isn't already in the requested mode, so it survives grok
# self-updates (which restore the original string) and switching root <-> no-root.
import sys, mmap

NATIVE = b"/etc/resolv.conf"
SDCARD = b"/sdcard/.grokdns"          # both exactly 16 bytes
assert len(NATIVE) == len(SDCARD) == 16

path, mode = sys.argv[1], sys.argv[2]
target = NATIVE if mode == "native" else SDCARD
other  = SDCARD if mode == "native" else NATIVE

with open(path, "r+b") as f:
    mm = mmap.mmap(f.fileno(), 0)
    try:
        n = 0
        i = mm.find(other)
        while i != -1:
            mm[i:i + 16] = target
            n += 1
            i = mm.find(other, i + 16)
        if n:
            mm.flush()
            sys.stderr.write(f"[grok] DNS path -> {target.decode()} ({n}x)\n")
    finally:
        mm.close()
