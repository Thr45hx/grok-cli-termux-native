# grok-cli-termux-native

Run **xAI's Grok Build CLI (`grok`) natively on Termux** (Android · aarch64) — **no proot, no root, no reboot.**

Grok Build ships a **statically-linked musl** aarch64 binary — no interpreter, no glibc — so it runs directly on the kernel and bundles its own TLS roots. It boots native on Termux out of the box. The **only** thing that fails is DNS: musl reads `/etc/resolv.conf`, which can't exist on Termux (`/etc → /system/etc`, read-only), and a *static* binary ignores `LD_PRELOAD` so a preload shim can't help either.

## Demo — Grok explaining its own install

Asked how it's running, Grok inspects its own launcher + binary on-device (Android 17, Pixel 9 Pro XL) and explains why a static musl ELF just runs — the kernel's `binfmt_elf` loader maps it directly, no dynamic linker, no proot, no qemu:

![Grok explains its native install](screenshots/grok-explains-native.png)

## The fix: one 16-byte patch

There is exactly **one** hardcoded `/etc/resolv.conf` string in the binary. `/sdcard/.grokdns` is also exactly 16 bytes, so we swap them **in place** — no length change, no relocation — and drop a resolv file there:

```
/etc/resolv.conf   →   /sdcard/.grokdns      (nameserver 8.8.8.8 / 8.8.4.4)
```

Now musl resolves DNS from a file Termux *can* write, with **zero root and zero proot**. (`/sdcard` is the only short, app-readable path that fits in 16 bytes.)

> HTTPS already works — Grok bundles its CA roots. Only DNS needed fixing.

## Requirements

- Termux on **aarch64 / arm64**, with storage access (`termux-setup-storage`)
- Internet on first run

## Install

```bash
git clone https://github.com/Thr45hx/grok-cli-termux-native
cd grok-cli-termux-native
bash install.sh
```

or one-shot:

```bash
curl -fsSL https://raw.githubusercontent.com/Thr45hx/grok-cli-termux-native/main/install.sh | bash
```

Then authenticate and go:

```bash
export XAI_API_KEY=xai-...        # or just run `grok` for the browser "Sign in with Grok" flow
grok -p "hello from native Termux"
```

## Stays working across updates

- The launcher **re-patches** the binary once per version (a self-update / re-install restores the original string) and **re-seeds** `/sdcard/.grokdns` if it goes missing.
- `grok-dns-patch.py` rewrites only the matching 16 bytes in place — no multi-hundred-MB copy.

## Layout

```
~/.grok/versions/<ver>          # grok binary (byte-patched)
~/agents/grok/
├── launcher.sh                 # ← $PREFIX/bin/grok symlinks here
└── grok-dns-patch.py
/sdcard/.grokdns                # nameserver 8.8.8.8 / 8.8.4.4
```

## Rooted? Cleaner option

If you're rooted (Magisk/APatch), a systemless `/system/etc/resolv.conf` module gives a real `/etc/resolv.conf` (since `/etc → /system/etc`) — then the **pristine** binary resolves natively with no byte-patch at all. This repo takes the no-root path by default.

## Uninstall

```bash
bash uninstall.sh
```

## Part of the native-Termux CLI family

One-command **native, no-proot** installers for AI coding CLIs on Termux — same toolkit, one per agent:

- [claude-code-termux-native](https://github.com/Thr45hx/claude-code-termux-native) — Claude Code
- [antigravity-cli-termux-native](https://github.com/Thr45hx/antigravity-cli-termux-native) — Google Antigravity
- [grok-cli-termux-native](https://github.com/Thr45hx/grok-cli-termux-native) — xAI Grok Build
- [opencode-termux-native](https://github.com/Thr45hx/opencode-termux-native) — OpenCode
- [copilot-cli-termux-native](https://github.com/Thr45hx/copilot-cli-termux-native) — GitHub Copilot

## Notes

- **AI-assisted:** built and reverse-engineered with AI help — a daily-driver, not a toy. Provided as-is.
- **Tested on:** Android 17, rooted **Pixel 9 Pro XL** (Tensor G4, aarch64).
- **Root / no-root:** **No root needed** by default (sdcard byte-patch); rooted users can use a systemless resolv module for the pristine binary.
- **License:** [MIT](./LICENSE).

---

Unofficial — not affiliated with xAI. Provided as-is, no warranty.
