# ======================================================
# 📨 TELEGRAM — Display Names
# ======================================================

import json
import os

FEATURES_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "kernel", "features.json")

with open(FEATURES_FILE) as handle:
    FEATURES = json.load(handle)

KERNEL_VERSION_TO_ANDROID = {v: d["android_number"] for v, d in FEATURES["versions"].items()}
ADDON_DISPLAY_NAMES = {k: d["name"] for k, d in FEATURES["addons"].items()}
PATCH_DISPLAY_NAMES = {k: d["name"] for k, d in FEATURES["patches"].items()}
MOUNTLESS_TOKENS = tuple(k for k, d in FEATURES["addons"].items() if d.get("mountless"))

def addon_order():
    return list(FEATURES["addons"])

def toggle_addon_order():
    return [t for t in addon_order() if t not in MOUNTLESS_TOKENS]

def addon_display_name(token):
    if token in ADDON_DISPLAY_NAMES:
        return ADDON_DISPLAY_NAMES[token]
    return " ".join(w.capitalize() for w in token.split("_"))

def resolve_mountless_token(env):
    addon_tokens = [t for t in env.get("ADDONS", "").split(",") if t]
    skipped_tokens = [t for t in env.get("SKIPPED_ADDONS", "").split(",") if t]
    for token in addon_tokens:
        if token in MOUNTLESS_TOKENS and token not in skipped_tokens:
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

def patch_order():
    return list(FEATURES["patches"])

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
