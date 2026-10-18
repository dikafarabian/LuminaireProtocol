# ======================================================
# 📨 TELEGRAM — Display Names
# ======================================================

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
    return tuple(tokens) if tokens else ("nomount",)

def toggle_addon_order(env):
    mountless = set(addon_mountless_tokens(env))
    return [t for t in addon_order(env) if t not in mountless]

def addon_display_name(token):
    if token in ADDON_DISPLAY_NAMES:
        return ADDON_DISPLAY_NAMES[token]
    return " ".join(w.capitalize() for w in token.split("_"))

def resolve_mountless_token(env):
    addon_tokens = [t for t in env.get("ADDONS", "").split(",") if t]
    skipped_tokens = [t for t in env.get("SKIPPED_ADDONS", "").split(",") if t]
    mountless_tokens = addon_mountless_tokens(env)
    for token in addon_tokens:
        if token in mountless_tokens and token not in skipped_tokens:
            return token
    return ""

def resolve_mountless_engine(env):
    token = resolve_mountless_token(env)
    return addon_display_name(token) if token else "None"

def lookup_version(raw, token):
    for pair in raw.split(","):
        name, _, version = pair.partition("=")
        if name == token:
            return version.strip()
    return ""

def addon_version(env, token):
    return lookup_version(env.get("ADDON_VERSIONS", ""), token)

PATCH_DISPLAY_NAMES = {
    "bore":                     "BORE",
    "le9uo":                    "le9uo",
    "kcompressd":               "Kcompressd",
    "workqueue_catchup":        "Workqueue Catch-up",
    "schedutil_catchup":        "Schedutil Catch-up",
    "ufs_writebooster_catchup": "UFS WriteBooster Catch-up",
    "bbrv3":                    "BBRv3",
    "bbg":                      "BBG",
    "wireguard":                "WireGuard",
}

def patch_order(env):
    raw = env.get("PATCH_FEATURE_ORDER", "")
    order = [t for t in raw.split(",") if t]
    if order:
        return order
    applied = [t for t in env.get("APPLIED_PATCHES", "").split(",") if t]
    skipped = [t for t in env.get("SKIPPED_PATCHES", "").split(",") if t]
    return applied + skipped

def patch_display_name(token):
    if token in PATCH_DISPLAY_NAMES:
        return PATCH_DISPLAY_NAMES[token]
    return " ".join(w.capitalize() for w in token.split("_"))

def patch_active_line(env, token):
    name = patch_display_name(token)
    version = lookup_version(env.get("PATCH_VERSIONS", ""), token)
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
