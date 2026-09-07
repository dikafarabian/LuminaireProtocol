"""Build the channel post as a Bot API 10.1 Rich Message (sendRichMessage).

WHY THIS EXISTS
The channel post used to be a sendPhoto with a MarkdownV2 caption, which caps at
1024 UTF-16 units and supports no tables. Rich messages allow 32768 characters,
real tables, buttons, and collapsible <details> blocks, so the whole feature list
fits inside the post itself and no external Telegraph page is needed.

WHAT IS DELIBERATE HERE (decided with the project owner, iterated on-device)
  - title    : "# Luminaire Protocol | <linux_ver>"  — H1; headings render in a
               serif face chosen by the client, which is not selectable.
  - subtitle : blockquote, NOT a heading, so it stays sans-serif.
  - "What's Inside?" is a <details> block, not a link to a page. Markdown IS
    parsed inside <details> (one of only three block tags where that is true),
    so tables and fenced blocks work in there.
  - its <summary> is an INLINE blue button. RichText (the type a summary accepts)
    includes RichTextButton, so a real button is legal there; type="disabled" is
    used on purpose because no button type can toggle a details block — the tap
    must fall through to the summary, which is what does the expanding.
  - the variant table is headerless: the name/version pair reads on its own,
    so no "Variant | Version" band sits above the download links.
  - Changelog is a GREEN button (left) pointing at the branch's commit history,
    directly above the fenced changelog block. The ```lang fence tag is NOT
    rendered as a visible label in a rich message, unlike the old caption.
  - Support is a BLUE button (centered) above the bug-report note.
  - no <hr/> divider.

ESCAPING
Rich Markdown is NOT MarkdownV2. Do not feed it MarkdownV2-escaped text — the
backslashes show up literally. Only two things need care:
  - a '#' at the start of a line is a heading marker, so a leading hashtag must
    be written '\\#GKI' (the Bot API docs show exactly this).
  - every table here is raw HTML, so cell text is html-escaped; the '|'
    sanitising that pipe tables need does not apply.
"""
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


def source_branch(env) -> str:
    """Branch the release was built from.

    KERNEL_BRANCH is what the build jobs export; it is the truth when present.
    Falls back to the project's naming convention, overridable with
    KERNEL_SOURCE_BRANCH, because the android<n> prefix does not track the
    kernel version.
    """
    explicit = env.get("KERNEL_BRANCH", "").strip()
    if explicit:
        return explicit
    override = env.get("KERNEL_SOURCE_BRANCH", "").strip()
    if override:
        return override
    kv = env.get("KERNEL_VERSION", "").strip()
    return f"android14-{kv}-luminaire" if kv else ""


def commits_url(env) -> str:
    """Full commit history of the release branch.

    Overridable with COMMITS_URL. Otherwise derived from the orchestrator repo's
    owner plus LuminaireKernel-<KERNEL_VERSION>.
    """
    explicit = env.get("COMMITS_URL", "").strip()
    if explicit:
        return explicit
    server = env.get("GITHUB_SERVER_URL", "https://github.com").rstrip("/")
    repo = env.get("GITHUB_REPOSITORY", "")
    owner = repo.split("/")[0] if "/" in repo else repo
    kv = env.get("KERNEL_VERSION", "").strip()
    branch = source_branch(env)
    if not owner or not kv or not branch:
        return ""
    return f"{server}/{owner}/LuminaireKernel-{kv}/commits/{branch}"


def html_cell(text: str) -> str:
    """Escape text for an HTML table cell."""
    return caption.html_escape(str(text)).replace("\n", " ").strip()


def build_info_table(env) -> str:
    """The old group-post ```Luminaire block, as a bordered HTML table.

    Written as raw HTML instead of markdown pipe syntax on purpose: pipe tables
    are GitHub-style and REQUIRE a header row whose cells are per-column, while
    an HTML table can spend a single colspan'd header cell on the section title
    itself. That is what lets the "Build Information" label live INSIDE the
    table instead of as a separate bold line above it.

    The padded key/value block this replaces only stayed aligned because every
    label was ljust()-ed to the longest one; a table cannot drift.

    CAREFUL: markdown is NOT parsed inside a block HTML tag like <table>, so a
    highlighted cell must use HTML (<mark>, <code>, <tg-button>) — '**bold**'
    renders literally in there. The LTO value is a disabled button so it reads as
    a chip without becoming tappable, and its color tracks the mode: NoLTO red,
    ThinLTO green, FullLTO blue.
    """
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
    """One <tg-button-row> holding one or more url buttons.

    buttons: list of (text, url, style) tuples; entries with no url are dropped.
    Omitting align is what makes a row stretch full width (that is how the
    Changelog button renders), so pass align only to shrink-wrap a row.
    Up to 8 buttons fit in a row.
    """
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
    """A non-tappable button, used as a colored status chip inside a table cell.

    type="disabled" on purpose: it reads as a chip and cannot be pressed.
    style="" gives the plain (uncolored) chip.
    """
    style_attr = f' style="{style}"' if style else ""
    return f'<tg-button type="disabled"{style_attr}>{html_cell(text)}</tg-button>'


def section_label(text: str) -> str:
    """A full-width chip used as a section label for a non-table block.

    A table can carry its own title in a colspan'd header cell, but a plain
    bold line cannot be centered. The label is a neutral chip inside a
    <tg-button-row> with NO align attribute: omitting align is what stretches
    the row edge to edge (align=center would shrink-wrap it around the chip).
    The chip inside the row fills the row's full width.

    No style attribute on purpose. RichMessageButton.style accepts only
    danger / success / primary; there is no grey value, and the neutral chip is
    the grey-looking one. An invented style="grey" is accepted by the server and
    then silently ignored, so it must never be used.
    """
    return f"<tg-button-row>{chip(text)}</tg-button-row>"


def core_features_folds() -> list:
    """Core features as one nested <details> per category.

    Nested details are legal (verified on-device) and keep the opened post short:
    the reader expands only the category they care about. Trade-off the owner
    accepted: it costs a second tap to reach any feature text.

    The section label is a full-width chip row (no align attribute — that is
    what stretches a <tg-button-row> edge to edge; align=center would
    shrink-wrap it around the chip) so it lines up with the centered header
    cells of the tables around it.
    """
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
    """Luminaire Tuning as a fold, sibling to the Core Features categories.

    The table is HTML and headerless on purpose: the fold's summary already
    names the section, and a pipe table would force a redundant header row back
    in (pipe syntax requires one, HTML does not).
    """
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
    """Add-ons NOT folded — the owner wants the status table visible right away.

    Unlike the Core Features categories and Tuning, this one is the part readers
    actually come for, so hiding it behind a tap costs more than the height it
    saves. It carries no label at all: the rows are self-describing, and the
    owner cut the heading rather than repeat what the chips already say.
    """
    return [addon_table(env)]


def addon_table(env) -> str:
    """Add-on status as a bordered HTML table with colored chips.

    Chip colors chosen by the owner:
      Enable -> green   Disable -> red   N/A -> neutral chip (no style)
      Mountless Engine -> blue when an engine is active, neutral chip on None.

    There is no grey style value: RichMessageButton.style accepts only danger /
    success / primary, and omitting it lets the client pick a neutral color. An
    invented value like style="grey" is accepted by the server and then silently
    ignored, so it must never be used — it would look identical to neutral while
    reading as if a color was chosen.

    HTML rather than pipe syntax because chips are HTML and markdown is not
    parsed inside a <table>; the same reason build_info_table() is HTML. Left
    without 'compact' so the cells stay roomy: a chip cannot be forced
    full-width — only a block-level <tg-button-row> stretches, and a chip is
    bound by its cell — so widening the cell is the closest reachable effect.
    """
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
    """The old Telegraph page's content, inlined as a collapsible block.

    Structure: an outer "What's Inside?" fold containing the Build table, then a
    row of sibling folds — one per Core Features category, plus Luminaire Tuning.
    Add-ons stays UNFOLDED at the end: it is the part readers come for, so it is
    visible as soon as the post is expanded.

    Mixed rendering per section, each chosen by the owner from real renders:
      - Build    : bordered HTML table, title in a centered colspan header cell,
                   LTO as a color-coded chip
      - Core     : centered neutral chip label, bullets inside each category fold
      - Tuning   : folded, one-column headerless HTML table
      - Add-ons  : not folded, no label, two-column table, status as chips

    The Full Changelog button sits ABOVE the changelog block, as its label.
    Support and Join share one row with no align attribute, which is what makes a
    button row stretch full width.
    """
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
    """Download links as a headerless bordered HTML table.

    Raw HTML rather than pipe syntax because a pipe table cannot drop its header
    row, and the owner wants none — the variant name and its version read as a
    pair without a "Variant | Version" band above them. Links stay clickable in
    a table cell (unlike inside a pre block), which is why this is a table at
    all.
    """
    rows = []
    for key, link in variant_links.items():
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
