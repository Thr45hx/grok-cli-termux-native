#!/data/data/com.termux/files/usr/bin/env python3
# Byte-patch the grok (static musl) binary so its one hardcoded "/etc/resolv.conf"
# reads "/sdcard/.grokdns" instead (same 16 bytes) — native DNS on Termux with no
# root and no proot. Only the matching bytes are rewritten in place (no 123 MB
# rewrite). Idempotent. Re-run after a grok self-update (updates restore the string).
import sys, mmap

OLD = b"/etc/resolv.conf"
NEW = b"/sdcard/.grokdns"          # exactly len(OLD) == 16 bytes
assert len(OLD) == len(NEW)

path = sys.argv[1]
with open(path, "r+b") as f:
    mm = mmap.mmap(f.fileno(), 0)
    try:
        n = 0
        i = mm.find(OLD)
        while i != -1:
            mm[i:i + len(NEW)] = NEW
            n += 1
            i = mm.find(OLD, i + len(NEW))
        if n:
            mm.flush()
            sys.stderr.write(f"[grok] DNS byte-patch: {n}x /etc/resolv.conf -> /sdcard/.grokdns\n")
    finally:
        mm.close()
