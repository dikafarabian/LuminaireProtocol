# ======================================================
# 📨 TELEGRAM — Rich Message Composer
# ======================================================

from __future__ import annotations

import json
import os

import caption

VARIANT_DISPLAY = {
    "KSU": "KernelSU",
    "KOWSU": "KowSU",
    "KSUNEXT": "KernelSU-Next",
    "SUKISU": "SukiSU-Ultra",
    "BAKASU": "BakaSU",
    "VANILLA": "Vanilla",
}

LINKS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "links.json")


def load_links() -> dict:
    try:
        with open(LINKS_PATH, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


LINKS = load_links()

BUG_REPORT_NOTE = (
    "If you encounter any issues or unexpected behavior, please report them "
    'through the <tg-button type="url" style="primary" url="{group_url}">Luminaire Lab</tg-button> discussion group.'
)

def variant_display(key: str) -> str:
    return VARIANT_DISPLAY.get(key, key)


def is_build_mode(env) -> bool:
    return env.get("RUN_MODE", "").strip().upper() == "BUILD"


VARIANT_ORDER = ["KSU", "KOWSU", "KSUNEXT", "SUKISU", "BAKASU", "VANILLA"]


def variant_sort_key(key: str):
    base = key[:-len("_SUSFS")] if key.endswith("_SUSFS") else key
    try:
        return VARIANT_ORDER.index(base)
    except ValueError:
        return len(VARIANT_ORDER)


def commits_url(env) -> str:
    owner = env.get("KERNEL_SOURCE_OWNER", "").strip()
    repo = env.get("KERNEL_SOURCE_REPO", "").strip()
    branch = env.get("KERNEL_BRANCH", "").strip()
    if not (owner and repo and branch):
        return ""
    return f"https://github.com/{owner}/{repo}/commits/{branch}"

def html_cell(text: str) -> str:
    return caption.html_escape(str(text)).replace("\n", " ").strip()

def build_info_table(env) -> str:
    lto_raw = env.get("LTO_MODE", "").strip()
    lto_display = caption.LTO_DISPLAY.get(lto_raw, lto_raw or "N/A")
    lto_chip = chip(lto_display, caption.LTO_CHIP_STYLE.get(lto_raw, ""))
    rows = [
        ("Kernel", html_cell("Linux " + (env.get("LINUX_VER", "").strip() or "N/A"))),
        ("Source", html_cell(env.get("KERNEL_SOURCE_REPO", "").strip() or "N/A")),
        ("Branch", html_cell(env.get("KERNEL_BRANCH", "").strip() or "N/A")),
        ("Toolchain", html_cell(env.get("COMPILER_STRING", "").strip() or "N/A")),
        ("LTO", lto_chip),
    ]
    body = "".join(f"<tr><td>{html_cell(k)}</td><td>{v}</td></tr>" for k, v in rows)
    return f"<table bordered>{body}</table>"

def button_row(buttons) -> str:
    if isinstance(buttons, tuple):
        buttons = [buttons]
    live = [(t, u, s) for t, u, s in buttons if u]
    if not live:
        return ""
    out = ["<tg-button-row>"]
    for text, url, style in live:
        style_attr = f' style="{style}"' if style else ""
        out.append(f'  <tg-button type="url"{style_attr} url="{url}">{text}</tg-button>')
    out.append("</tg-button-row>")
    return "\n".join(out)

def chip(text: str, style: str = "") -> str:
    style_attr = f' style="{style}"' if style else ""
    return f'<tg-button type="disabled"{style_attr}>{html_cell(text)}</tg-button>'


def release_url(key: str) -> str:
    base = key[:-len("_SUSFS")] if key.endswith("_SUSFS") else key
    return LINKS.get("variants", {}).get(base, "")


def variant_header(title: str, url: str = "") -> str:
    action = f'type="url" url="{url}"' if url else 'type="callback_data" data="x"'
    return (
        f'<tg-button-row><tg-button {action} '
        f'style="primary">{html_cell(title)}</tg-button></tg-button-row>'
    )


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

def engine_chip(engine: str, link: bool, version: str = "") -> str:
    label = f"{engine} {version}" if version else engine
    url = LINKS.get("mountless", {}).get(engine, "") if link else ""
    if not url:
        return chip(label, "primary" if engine != "None" else "")
    return f'<tg-button type="url" style="primary" url="{url}">{html_cell(label)}</tg-button>'

def addon_table(env, link_engine: bool = False) -> str:
    addon_tokens = [t for t in env.get("ADDONS", "").split(",") if t]
    skipped_addons = [t for t in env.get("SKIPPED_ADDONS", "").split(",") if t]

    engine = caption.resolve_mountless_engine(env)
    engine_token = caption.resolve_mountless_token(env)
    engine_version = caption.addon_version(env, engine_token) if engine_token else ""
    engine_cell = engine_chip(engine, link_engine, engine_version)
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

def features_details(env) -> str:
    out = [
        "<details>",
        '<summary><tg-button type="disabled" style="primary">'
        "What's Inside?</tg-button></summary>",
        "",
    ]
    out += core_features_folds()
    out += tuning_fold(env)
    out.append("</details>")
    return "\n".join(out)


def changelog_block(env) -> str:
    raw = env.get("CHANGELOG", "").strip()
    if not raw:
        return ""
    entries = [e.strip() for e in raw.split(";") if e.strip()]
    if not entries:
        return ""
    body = "\n".join(f"\u2022 {e}" for e in entries)
    return "```\n" + body + "\n```"

def banner_slideshow(banner_ids) -> str:
    slides = "\n".join(f'<img src="tg://photo?id={banner_id}" tg-spoiler/>' for banner_id in banner_ids)
    return f"<tg-slideshow>\n{slides}\n</tg-slideshow>"


def compose_markdown(env, variants_block, banner_ids=()) -> str:
    linux_ver = env.get("LINUX_VER", "N/A")
    kernel_ver = env.get("KERNEL_VERSION", "")
    android_ver = caption.KERNEL_VERSION_TO_ANDROID.get(kernel_ver, "?")
    major_minor = ".".join(linux_ver.split(".")[:2]) + ".x"
    group_url = "https://t.me/{}".format(env.get("TELEGRAM_GROUP", ""))
    support_url = "https://sociabuzz.com/chainonyourdoor"
    artifact_url = "https://t.me/LuminaireCI"

    build_mode = is_build_mode(env)

    parts = []
    if build_mode:
        parts += [build_info_table(env), addon_table(env, link_engine=True), variants_block]
    else:
        if banner_ids:
            parts.append(banner_slideshow(banner_ids))
        parts.append(f"# Luminaire Protocol | {linux_ver}")
        parts.append(f"> GKI Kernel | Android {android_ver} | Linux {major_minor}")
        parts.append(features_details(env))
        parts.append(build_info_table(env))
        parts.append(addon_table(env, link_engine=True))
        parts.append(variants_block)

    cl = changelog_block(env)
    if cl:
        if not build_mode:
            parts.append(button_row(("Full Changelog", commits_url(env), "success")))
        parts.append(cl)
    elif not build_mode:
        parts.append(button_row(("Commits", commits_url(env), "success")))

    if not build_mode:
        parts.append(button_row([
            ("Support", support_url, "primary"),
            ("Luminaire Artifact", artifact_url, "primary"),
        ]))
        parts.append("> " + BUG_REPORT_NOTE.format(group_url=group_url))
        parts.append("\\#GKI \\#Kernel \\#Luminaire")

    return "\n\n".join(p for p in parts if p) + "\n"
