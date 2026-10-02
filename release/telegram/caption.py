# ======================================================
# 📨 TELEGRAM — Display Names & Push Caption
# ======================================================

import os
import sys

PUSH_TEXT_LIMIT = 4096

KERNEL_VERSION_TO_ANDROID = {
    "5.10": "12",
    "5.15": "13",
    "6.1":  "14",
    "6.6":  "15",
    "6.12": "16",
}

ADDON_DISPLAY_NAMES = {
    "rekernel":    "Re:Kernel",
    "droidspaces": "Droidspaces",
    "zeromount":   "ZeroMount",
    "nomount":     "NoMount",
    "ntsync":      "NTSync",
    "lz4zstd":     "LZ4+ZSTD",
    "lz4kd":       "LZ4KD",
    "mglru":       "MGLRU",
}

def addon_order(env):
    raw = env.get("ADDON_ORDER", "")
    order = [t for t in raw.split(",") if t]
    if order:
        return order
    applied = [t for t in env.get("APPLIED_ADDONS", "").split(",") if t]
    skipped = [t for t in env.get("SKIPPED_ADDONS", "").split(",") if t]
    return applied + skipped

def addon_mountless_tokens(env):
    raw = env.get("ADDON_MOUNTLESS_TOKENS", "")
    tokens = [t for t in raw.split(",") if t]
    return tuple(tokens) if tokens else ("nomount", "zeromount")

def toggle_addon_order(env):
    mountless = set(addon_mountless_tokens(env))
    return [t for t in addon_order(env) if t not in mountless]

def addon_display_name(token):
    if token in ADDON_DISPLAY_NAMES:
        return ADDON_DISPLAY_NAMES[token]
    return " ".join(w.capitalize() for w in token.split("_"))

def resolve_mountless_engine(env):
    addon_tokens = [t for t in env.get("ADDONS", "").split(",") if t]
    skipped_tokens = [t for t in env.get("SKIPPED_ADDONS", "").split(",") if t]
    mountless_tokens = addon_mountless_tokens(env)
    for token in addon_tokens:
        if token in mountless_tokens and token not in skipped_tokens:
            return addon_display_name(token)
    return "None"

TUNING_DISPLAY_NAMES = {
    "bore":                     "BORE",
    "adios":                    "ADIOS",
    "le9uo":                    "le9uo",
    "kcompressd":               "Kcompressd",
    "workqueue_catchup":        "Workqueue Catch-up",
    "schedutil_catchup":        "Schedutil Catch-up",
    "ufs_writebooster_catchup": "UFS WriteBooster Catch-up",
    "bbrv3":                    "BBRv3",
    "bbg":                      "BBG",
    "wireguard":                "WireGuard",
}

def tuning_order(env):
    raw = env.get("TUNING_FEATURE_ORDER", "")
    order = [t for t in raw.split(",") if t]
    if order:
        return order
    applied = [t for t in env.get("APPLIED_TUNING", "").split(",") if t]
    skipped = [t for t in env.get("SKIPPED_TUNING", "").split(",") if t]
    return applied + skipped

def tuning_display_name(token):
    if token in TUNING_DISPLAY_NAMES:
        return TUNING_DISPLAY_NAMES[token]
    return " ".join(w.capitalize() for w in token.split("_"))

def tuning_active_line(env, token):
    name = tuning_display_name(token)
    version = env.get(f"{token.upper()}_VERSION", "").strip()
    return f"{name} {version}" if version else name

FRAGMENT_FEATURES = {
    "Filesystem": [
        "Mountify / OverlayFS",
        "F2FS Extended Attributes",
        "POSIX ACL",
    ],
    "Memory": [
        "ZRAM (LZ4 compression)",
        "Memory Tracking",
        "Writeback Support",
    ],
    "CPU & Scheduler": [
        "Ondemand Governor (included)",
        "Frame Warning Disabled",
        "I/O Scheduler (MQ-Deadline, Kyber)",
    ],
    "Network": [
        ("TCP Congestion Control", ["BBR", "BIC", "CUBIC", "Westwood", "HTCP"]),
        ("Network Schedulers", ["FQ", "FQ_CoDel", "CAKE", "PIE", "FQ-PIE"]),
        "IP Set",
        "IPv6 NAT",
        "TTL Target (Netfilter)",
    ],
    "Debug": [
        "Full Kallsyms",
        "UBSAN Disabled",
        "Page Owner Disabled",
        "RCU Trace Disabled",
    ],
}

LTO_DISPLAY = {
    "NONE": "NoLTO",
    "THIN": "ThinLTO",
    "FULL": "FullLTO",
}

LTO_CHIP_STYLE = {
    "NONE": "danger",
    "THIN": "success",
    "FULL": "primary",
}

def html_escape(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

def html_escape_attr(s):
    return html_escape(s).replace('"', "&quot;")


def utf16_len(s):
    return sum(2 if ord(c) > 0xFFFF else 1 for c in s)

def truncate(caption, limit, suffix="\n\u2026\n```"):
    if utf16_len(caption) <= limit:
        return caption
    suffix_len = utf16_len(suffix)
    result = []
    current_len = 0
    for ch in caption:
        ch_len = 2 if ord(ch) > 0xFFFF else 1
        if current_len + ch_len + suffix_len > limit:
            break
        result.append(ch)
        current_len += ch_len
    return "".join(result) + suffix

def kernel_source_repo(kernel_ver):
    return f"LuminaireKernel-{kernel_ver}" if kernel_ver else "N/A"


def build_push_caption(env):
    branch_raw = env.get("BRANCH", "")
    author     = env.get("AUTHOR", "")
    author_url = html_escape_attr("https://t.me/{}".format(author))
    commit_short = env.get("COMMIT", "")[:7]
    commit_url   = html_escape_attr(env.get("URL", ""))
    title = env.get("TITLE", "")
    body  = env.get("BODY", "")
    head = "\n".join([
        "New Commit \U0001F4CC",
        "",
        f"Branch : <code>{html_escape(branch_raw)}</code>",
        f'Author : <a href="{author_url}">{html_escape(author)}</a>',
    ])
    title_block = f'<pre><code class="language-Title">{html_escape(title)}</code></pre>'
    head_full = head + "\n" + title_block
    footer = f'\nCommit : <a href="{commit_url}">{html_escape(commit_short)}</a>'
    if not body.strip():
        return truncate(head_full + footer, PUSH_TEXT_LIMIT)
    wrapper = '\n<pre><code class="language-Message"></code></pre>'
    fixed_len = utf16_len(head_full) + utf16_len(footer) + utf16_len(wrapper)
    body_budget = PUSH_TEXT_LIMIT - fixed_len
    body_esc = html_escape(body)
    if utf16_len(body_esc) > body_budget:
        body_esc = truncate(body_esc, max(body_budget, 0), suffix="\n\u2026")
    message_block = f'<pre><code class="language-Message">{body_esc}</code></pre>'
    return head_full + "\n" + message_block + footer

def main():
    if len(sys.argv) != 3 or sys.argv[1] != "push":
        sys.exit("usage: caption.py push <out-file>")
    caption = build_push_caption(os.environ)
    with open(sys.argv[2], "w") as f:
        f.write(caption)
    print("[info] telegram_caption: push caption written ✅", flush=True)

if __name__ == "__main__":
    main()
