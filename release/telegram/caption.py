import os
import sys


CAPTION_LIMIT = 1024
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
    "kasumi":      "Kasumi",
    "ntsync":      "NTSync",
    "lz4zstd":     "LZ4+ZSTD",
    "lz4kd":       "LZ4KD",
    "mglru":       "MGLRU",
}


def addon_order(env):
    """Full addon catalog (toggle + mountless-engine addons together),
    read from ADDON_ORDER — exported by kernel/addons/registry.sh so
    this list never needs editing here just because an addon was
    added/removed there. See tuning_order() above for the same
    pattern applied to kernel/tuning/ features."""
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
    """addon_order() minus the mountless-engine addons, which are
    shown as a single 'Mountless Engine' line instead of their own
    Enable/Disable row."""
    mountless = set(addon_mountless_tokens(env))
    return [t for t in addon_order(env) if t not in mountless]


def addon_display_name(token):
    if token in ADDON_DISPLAY_NAMES:
        return ADDON_DISPLAY_NAMES[token]
    return " ".join(w.capitalize() for w in token.split("_"))


def resolve_mountless_engine(env):
    """Which mountless-engine addon (if any) is active this build, as
    its display name, or 'None'. Shared by build_blocks() (group
    caption's dedicated "Mountless Engine" line) and the rich channel
    post's Add-ons table, both of which need it as its own row instead
    of relying on toggle_addon_order(), which deliberately excludes
    mountless tokens from the regular Enable/Disable rows."""
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
    """The full set+order of kernel/tuning/ features (applied AND
    skipped this build), read from TUNING_FEATURE_ORDER — exported
    by kernel/tuning/registry.sh so this list never needs editing
    here just because a feature was added/removed there."""
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
    """Display text for an ACTIVE tuning feature only — caller is
    expected to have already skipped inactive/skipped tokens, since
    the zip caption only lists features that are actually on. Appends
    the patch version (e.g. 'v6.8.0-rc1') when the feature's .sh script
    exported one via f"{TOKEN}_VERSION" (see BORE_VERSION in
    kernel/tuning/bore/bore.sh) — for versioned features like BORE,
    which version is running is the actually useful information."""
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


def mdv2_code_escape(s):
    s = s.replace("\\", "\\\\")
    s = s.replace("`", "\\`")
    return s


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


def build_blocks(env):
    linux_ver       = mdv2_code_escape(env.get("LINUX_VER", "N/A"))
    kernel_ver      = env.get("KERNEL_VERSION", "")
    source_str      = mdv2_code_escape(kernel_source_repo(kernel_ver))
    kernel_branch   = mdv2_code_escape(env.get("KERNEL_BRANCH", "N/A"))
    compiler        = mdv2_code_escape(env.get("COMPILER_STRING", "N/A"))
    lto             = mdv2_code_escape(env.get("LTO_MODE", "NONE"))
    kernel_variant  = mdv2_code_escape(env.get("KERNEL_VARIANT_DISPLAY", "N/A"))
    susfs_ver       = mdv2_code_escape(env.get("SUSFS_VER", "N/A"))
    addon_tokens = [t for t in env.get("ADDONS", "").split(",") if t]
    skipped_tokens = [t for t in env.get("SKIPPED_ADDONS", "").split(",") if t]
    mountless = mdv2_code_escape(resolve_mountless_engine(env))
    toggle_order = toggle_addon_order(env)
    addon_name_width = max(
        [len(addon_display_name(t)) for t in toggle_order] + [len("Mountless Engine")]
    ) + 1
    addon_status_lines = []
    for token in toggle_order:
        name = addon_display_name(token)
        if token in skipped_tokens:
            status = "N/A"
        elif token in addon_tokens:
            status = "Enable"
        else:
            status = "Disable"
        addon_status_lines.append(f"{name.ljust(addon_name_width)}: {mdv2_code_escape(status)}")
    tuning_skipped_tokens = [t for t in env.get("SKIPPED_TUNING", "").split(",") if t]
    tuning_order_list = tuning_order(env)
    tuning_active_lines = [
        mdv2_code_escape(tuning_active_line(env, token))
        for token in tuning_order_list
        if token not in tuning_skipped_tokens
    ]
    block_luminaire = (
        "```Luminaire\n"
        f"Kernel    : Linux {linux_ver}\n"
        f"Source    : {source_str}\n"
        f"Branch    : {kernel_branch}\n"
        f"Toolchain : {compiler}\n"
        f"LTO       : {lto}```"
    )
    is_vanilla = env.get("KERNEL_VARIANT", "").upper() == "VANILLA"
    if is_vanilla:
        root_lines = [
            "Version : Vanilla",
            "SuSFS   : N/A (Vanilla)",
        ]
    else:
        ksu_version = mdv2_code_escape(env.get("KERNEL_VARIANT_VERSION", "")) or "N/A"
        root_lines = [
            f"Version : {ksu_version}",
            f"SuSFS   : {susfs_ver}",
        ]
    variant_label = "Vanilla" if is_vanilla else kernel_variant
    block_root = f"```{variant_label}\n" + "\n".join(root_lines) + "```"
    block_addons = (
        "```Add-ons\n"
        f"{'Mountless Engine'.ljust(addon_name_width)}: {mountless}\n"
        + "\n".join(addon_status_lines) +
        "```"
    )
    has_active_tuning = bool(tuning_active_lines)
    if has_active_tuning:
        block_tuning = (
            "```Tuning\n"
            + "\n".join(tuning_active_lines) +
            "```"
        )
    else:
        block_tuning = None
    return block_luminaire, block_root, block_tuning, block_addons


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
    if len(sys.argv) == 3 and sys.argv[1] == "push":
        env = os.environ
        caption = build_push_caption(env)
        with open(sys.argv[2], "w") as f:
            f.write(caption)
        print("[info] telegram_caption: push caption written ✅", flush=True)
        return
    out_group = sys.argv[1]
    env = os.environ
    block_luminaire, block_root, block_tuning, block_addons = build_blocks(env)
    caption_group = "\n".join(
        b for b in [block_luminaire, block_root, block_tuning, block_addons] if b is not None
    )
    caption_group = truncate(caption_group, CAPTION_LIMIT)
    with open(out_group, "w") as f:
        f.write(caption_group)
    print("[info] telegram_caption: caption written ✅", flush=True)


if __name__ == "__main__":
    main()
