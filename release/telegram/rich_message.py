from __future__ import annotations

import json
import os
import sys

import caption

VARIANT_DISPLAY_PLAIN = {
    "KSU": "KernelSU",
    "KSU_SUSFS": "KernelSU+SUSFS",
    "KOWSU": "KowSU",
    "KOWSU_SUSFS": "KowSU+SUSFS",
    "KSUNEXT": "KernelSU-Next",
    "KSUNEXT_SUSFS": "KernelSU-Next+SUSFS",
    "SUKISU": "SukiSU-Ultra",
    "SUKISU_SUSFS": "SukiSU-Ultra+SUSFS",
    "RESUKISU": "ReSukiSU",
    "RESUKISU_SUSFS": "ReSukiSU+SUSFS",
    "VANILLA": "Vanilla",
}

BUG_REPORT_NOTE = (
    "If you encounter any issues or unexpected behavior, please report them "
    "through the [Luminaire Lab]({group_url}) discussion group."
)

def variant_display(key: str) -> str:
    return VARIANT_DISPLAY_PLAIN.get(key, key)


VARIANT_ORDER = ["KSU", "KOWSU", "KSUNEXT", "SUKISU", "RESUKISU", "VANILLA"]


def variant_sort_key(key: str):
    base = key[:-len("_SUSFS")] if key.endswith("_SUSFS") else key
    try:
        return VARIANT_ORDER.index(base)
    except ValueError:
        return len(VARIANT_ORDER)


def source_branch(env) -> str:
    explicit = env.get("KERNEL_BRANCH", "").strip()
    if explicit:
        return explicit
    override = env.get("KERNEL_SOURCE_BRANCH", "").strip()
    if override:
        return override
    kv = env.get("KERNEL_VERSION", "").strip()
    return f"android14-{kv}-luminaire" if kv else ""

def commits_url(env) -> str:
    explicit = env.get("COMMITS_URL", "").strip()
    if explicit:
        return explicit
    server = env.get("GITHUB_SERVER_URL", "https://github.com").rstrip("/")
    owner = env.get("KERNEL_SOURCE_OWNER", "").strip() or "chainonyourdoor"
    kv = env.get("KERNEL_VERSION", "").strip()
    branch = source_branch(env)
    if not owner or not kv or not branch:
        return ""
    return f"{server}/{owner}/LuminaireKernel-{kv}/commits/{branch}"

def html_cell(text: str) -> str:
    return caption.html_escape(str(text)).replace("\n", " ").strip()

def build_info_table(env) -> str:
    kv = env.get("KERNEL_VERSION", "").strip()
    lto_raw = env.get("LTO_MODE", "").strip()
    lto_display = caption.LTO_DISPLAY.get(lto_raw, lto_raw or "N/A")
    lto_chip = chip(lto_display, caption.LTO_CHIP_STYLE.get(lto_raw, ""))
    rows = [
        ("Kernel", html_cell("Linux " + (env.get("LINUX_VER", "").strip() or "N/A"))),
        ("Source", html_cell(caption.kernel_source_repo(kv))),
        ("Branch", html_cell(source_branch(env) or "N/A")),
        ("Toolchain", html_cell(env.get("COMPILER_STRING", "").strip() or "N/A")),
        ("LTO", lto_chip),
    ]
    head = '<tr><th colspan="2" align="center">Build Information</th></tr>'
    body = "".join(f"<tr><td>{html_cell(k)}</td><td>{v}</td></tr>" for k, v in rows)
    return f"<table bordered>{head}{body}</table>"

def button_row(buttons, align: str = "") -> str:
    if isinstance(buttons, tuple):
        buttons = [buttons]
    live = [(t, u, s) for t, u, s in buttons if u]
    if not live:
        return ""
    align_attr = f' align="{align}"' if align else ""
    out = [f"<tg-button-row{align_attr}>"]
    for text, url, style in live:
        style_attr = f' style="{style}"' if style else ""
        out.append(f'  <tg-button type="url"{style_attr} url="{url}">{text}</tg-button>')
    out.append("</tg-button-row>")
    return "\n".join(out)

def chip(text: str, style: str = "") -> str:
    style_attr = f' style="{style}"' if style else ""
    return f'<tg-button type="disabled"{style_attr}>{html_cell(text)}</tg-button>'

def section_label(text: str) -> str:
    return f"<tg-button-row>{chip(text)}</tg-button-row>"

def core_features_folds() -> list:
    out = ['<tg-button-row><tg-button type="disabled">Core Features'
           "</tg-button></tg-button-row>", ""]
    for category, items in caption.FRAGMENT_FEATURES.items():
        out.append("<details>")
        out.append(f"<summary>{category}</summary>")
        out.append("")
        for item in items:
            if isinstance(item, tuple):
                label, subs = item
                out.append(f"- {label}: {', '.join(subs)}")
            else:
                out.append(f"- {item}")
        out.append("</details>")
    return out

def tuning_fold(env) -> list:
    applied = [t for t in env.get("APPLIED_TUNING", "").split(",") if t]
    rows = [
        caption.tuning_active_line(env, t)
        for t in caption.tuning_order(env)
        if t in applied
    ]
    if not rows:
        rows = ["None active this build"]
    body = "".join(f"<tr><td>{html_cell(r)}</td></tr>" for r in rows)
    return [
        "<details>",
        "<summary>Luminaire Tuning</summary>",
        "",
        f"<table bordered>{body}</table>",
        "</details>",
    ]

def addon_section(env) -> list:
    return [addon_table(env)]

def addon_table(env) -> str:
    addon_tokens = [t for t in env.get("ADDONS", "").split(",") if t]
    skipped_addons = [t for t in env.get("SKIPPED_ADDONS", "").split(",") if t]

    engine = caption.resolve_mountless_engine(env)
    engine_cell = chip(engine, "primary" if engine != "None" else "")
    rows = [("Mountless Engine", engine_cell)]

    for token in caption.toggle_addon_order(env):
        name = caption.addon_display_name(token)
        if token in skipped_addons:
            status = chip("N/A")
        elif token in addon_tokens:
            status = chip("Enable", "success")
        else:
            status = chip("Disable", "danger")
        rows.append((name, status))

    body = "".join(f"<tr><td>{html_cell(k)}</td><td>{v}</td></tr>" for k, v in rows)
    return f"<table bordered>{body}</table>"

def features_details(env, style: str = "") -> str:
    out = [
        "<details>",
        '<summary><tg-button type="disabled" style="primary">'
        "What's Inside?</tg-button></summary>",
        "",
        build_info_table(env),
        "",
    ]
    out += core_features_folds()
    out += tuning_fold(env)
    out += [""]
    out += addon_section(env)
    out.append("</details>")
    return "\n".join(out)

def variant_table(variant_links, variant_versions) -> str:
    rows = []
    for key, link in sorted(variant_links.items(), key=lambda kv: variant_sort_key(kv[0])):
        name = html_cell(variant_display(key))
        ver = html_cell(variant_versions.get(key, "") or "\u2014")
        rows.append(f'<tr><td><a href="{link}">{name}</a></td><td>{ver}</td></tr>')
    return "<table bordered>" + "".join(rows) + "</table>"

def changelog_block(env) -> str:
    raw = env.get("CHANGELOG", "").strip()
    if not raw:
        return ""
    entries = [e.strip() for e in raw.split(";") if e.strip()]
    if not entries:
        return ""
    body = "\n".join(f"\u2022 {e}" for e in entries)
    return "```\n" + body + "\n```"

def build_markdown(env, variant_links, variant_versions, has_banner=True) -> str:
    linux_ver = env.get("LINUX_VER", "N/A")
    kernel_ver = env.get("KERNEL_VERSION", "")
    android_ver = caption.KERNEL_VERSION_TO_ANDROID.get(kernel_ver, "?")
    major_minor = ".".join(linux_ver.split(".")[:2]) + ".x"
    group_url = "https://t.me/{}".format(env.get("TELEGRAM_GROUP", ""))
    support_url = "https://sociabuzz.com/chainonyourdoor"

    parts = []
    if has_banner:
        parts.append("![](tg://photo?id=banner)")
    parts.append(f"# Luminaire Protocol | {linux_ver}")
    parts.append(f"> GKI Kernel | Android {android_ver} | Linux {major_minor}")
    parts.append(features_details(env))
    parts.append(variant_table(variant_links, variant_versions))

    cl = changelog_block(env)
    if cl:
        parts.append(button_row(("Full Changelog", commits_url(env), "success")))
        parts.append(cl)
    else:
        parts.append(button_row(("Commits", commits_url(env), "success")))

    parts.append(button_row([
        ("Support", support_url, "primary"),
        ("Join", group_url, "primary"),
    ]))
    parts.append("> " + BUG_REPORT_NOTE.format(group_url=group_url))
    parts.append("\\#GKI \\#Kernel \\#Luminaire")

    return "\n\n".join(p for p in parts if p) + "\n"

def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: rich_message.py <out-json-file>")
    env = os.environ

    try:
        variant_links = json.loads(env.get("VARIANT_LINKS_JSON", "") or "{}")
    except Exception:
        variant_links = {}
    try:
        variant_versions = json.loads(env.get("VARIANT_VERSIONS_JSON", "") or "{}")
    except Exception:
        variant_versions = {}

    has_banner = env.get("RICH_HAS_BANNER", "1") not in ("", "0", "no")
    md = build_markdown(env, variant_links, variant_versions, has_banner=has_banner)

    payload = {"markdown": md}
    if has_banner:
        payload["media"] = [
            {
                "id": "banner",
                "media": {"type": "photo", "media": "attach://banner_file"},
            }
        ]

    with open(sys.argv[1], "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False)

    print(
        f"[info] rich_message: built {len(md)} chars (limit 32768) \u2705",
        file=sys.stderr,
        flush=True,
    )

if __name__ == "__main__":
    main()
