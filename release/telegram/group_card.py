"""Build the per-zip group card as a Bot API 10.1 Rich Message.

The old group post was a sendDocument with a MarkdownV2 caption capped at 1024
UTF-16 units and no tables. Rich messages allow 32768 characters, real tables,
chips and collapsible blocks, and since Bot API 10.3 the zip itself can ride
inside the message as a document block, so the whole card is one message.

Approved layout V1 (owner, 2026-09-06, from a real render):
  - the zip as an embedded document block at the top
  - Luminaire Protocol table — centered header cell + Kernel/Source/Branch/
    Toolchain/LTO rows, the LTO chip colored by mode (NoLTO red, ThinLTO green,
    FullLTO blue)
  - <variant> table — same shape, Version / SuSFS rows
  - Add-ons table — no header, status chips (Enable green, Disable red, N/A
    neutral, the active Mountless Engine blue)
  - Tuning is deliberately absent: it lives in the channel post's fold.

ESCAPING
Rich Markdown is NOT MarkdownV2. Do not feed it MarkdownV2-escaped text — the
backslashes show up literally. Every table here is raw HTML, so cell text is
html-escaped, not '|'-sanitised.
"""
from __future__ import annotations

import json
import os
import sys

import caption

CHIP_STYLE = {
    "NONE": "danger",
    "THIN": "success",
    "FULL": "primary",
}


def html_cell(text: str) -> str:
    return caption.html_escape(str(text)).replace("\n", " ").strip()


def chip(text: str, style: str = "") -> str:
    style_attr = f' style="{style}"' if style else ""
    return f'<tg-button type="disabled"{style_attr}>{html_cell(text)}</tg-button>'


def table(rows: list, title: str | None = None, cols: int = 2) -> str:
    body = ""
    if title is not None:
        body += f'<tr><th colspan="{cols}" align="center">{html_cell(title)}</th></tr>'
    body += "".join("<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>" for r in rows)
    return f"<table bordered>{body}</table>"


def build_rows(env) -> list:
    lto_mode = env.get("LTO_MODE", "").strip()
    lto_display = caption.LTO_DISPLAY.get(lto_mode, lto_mode or "N/A")
    return [
        ("Kernel", html_cell("Linux " + (env.get("LINUX_VER", "").strip() or "N/A"))),
        ("Source", html_cell(caption.kernel_source_repo(env.get("KERNEL_VERSION", "")))),
        ("Branch", html_cell(env.get("KERNEL_BRANCH", "").strip() or "N/A")),
        ("Toolchain", html_cell(env.get("COMPILER_STRING", "").strip() or "N/A")),
        ("LTO", chip(lto_display, CHIP_STYLE.get(lto_mode, ""))),
    ]


def variant_rows(env) -> list:
    version = env.get("KERNEL_VARIANT_VERSION", "").strip()
    susfs = env.get("SUSFS_VER", "").strip() or "N/A"
    return [
        ("Version", html_cell(version or "N/A")),
        ("SuSFS", html_cell(susfs)),
    ]


def addon_rows(env) -> list:
    active = [t for t in env.get("ADDONS", "").split(",") if t]
    skipped = [t for t in env.get("SKIPPED_ADDONS", "").split(",") if t]
    engine = caption.resolve_mountless_engine(env)
    rows = [("Mountless Engine", chip(engine, "primary" if engine != "None" else ""))]
    for token in caption.toggle_addon_order(env):
        if token in skipped:
            status = chip("N/A")
        elif token in active:
            status = chip("Enable", "success")
        else:
            status = chip("Disable", "danger")
        rows.append((html_cell(caption.addon_display_name(token)), status))
    return rows


def build_markdown(env) -> str:
    variant = env.get("KERNEL_VARIANT_DISPLAY", "").strip() or "Build"
    parts = [
        "![](tg://document?id=zipfile)",
        table(build_rows(env), title="Luminaire Protocol"),
        table(variant_rows(env), title=variant),
        table(addon_rows(env)),
    ]
    return "\n\n".join(parts) + "\n"


def build_payload(env) -> dict:
    return {
        "markdown": build_markdown(env),
        "media": [
            {
                "id": "zipfile",
                "media": {"type": "document", "media": "attach://zip_file"},
            }
        ],
    }


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: group_card.py <out-json-file>")
    payload = build_payload(os.environ)
    with open(sys.argv[1], "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False)
    print("[info] group_card: built %.0f chars (limit 32768) \u2705" % len(payload["markdown"]), flush=True)


if __name__ == "__main__":
    main()