from __future__ import annotations

import glob
import json
import os
import sys

import rich_message as rm

RICH_LIMIT = 32768
BANNER_NAMES = ("banner.jpg", "banner.jpeg", "banner.png")


def load_metas(stage_dir: str) -> list:
    metas = []
    for path in glob.glob(os.path.join(stage_dir, "**", "meta.json"), recursive=True):
        with open(path, encoding="utf-8") as f:
            meta = json.load(f)
        metas.append(meta)
    metas.sort(key=lambda m: (rm.variant_sort_key(m["variant"]), m["variant"]))
    return metas


def shared_env(first: dict) -> dict:
    env = dict(os.environ)
    env.update(
        {
            "LINUX_VER": first.get("linux_ver", ""),
            "KERNEL_VERSION": first.get("kernel_version", ""),
            "KERNEL_BRANCH": first.get("kernel_branch", ""),
            "COMPILER_STRING": first.get("compiler_string", ""),
            "LTO_MODE": first.get("lto_mode", ""),
            "ADDONS": first.get("addons", ""),
            "ADDON_ORDER": first.get("addon_order", ""),
            "SKIPPED_ADDONS": first.get("skipped_addons", ""),
            "APPLIED_TUNING": first.get("applied_tuning", ""),
            "SKIPPED_TUNING": first.get("skipped_tuning", ""),
        }
    )
    return env


def variant_block(meta: dict, index: int) -> str:
    title = rm.html_cell(rm.variant_display(meta["variant"]))
    version = rm.html_cell(meta.get("variant_version", ""))
    if version:
        title = f"{title} \u00b7 {version}"
    return "\n".join(
        [
            f'<table bordered><tr><th align="center">{title}</th></tr></table>',
            "",
            f"![](tg://document?id=zip{index})",
            "",
        ]
    )


def find_banner() -> str:
    base = os.path.dirname(os.path.abspath(__file__))
    for name in BANNER_NAMES:
        candidate = os.path.join(base, name)
        if os.path.isfile(candidate):
            return candidate
    return ""


def build_payload(metas: list, env: dict, has_banner: bool, file_ids: dict) -> dict:
    blocks = "\n".join(variant_block(m, i) for i, m in enumerate(metas, 1))
    markdown = rm.compose_markdown(env, blocks, has_banner=has_banner)
    media = []
    if has_banner:
        media.append({"id": "banner", "media": {"type": "photo", "media": "attach://banner_file"}})
    for i, meta in enumerate(metas, 1):
        media.append({"id": f"zip{i}", "media": {"type": "document", "media": file_ids[meta["variant"]]}})
    return {"markdown": markdown, "media": media}


def main() -> None:
    if len(sys.argv) != 5:
        sys.exit("usage: group_card.py <stage-dir> <file-ids-json> <out-payload-json> <out-attachments-file>")
    stage_dir, file_ids_path, payload_path, attachments_path = sys.argv[1:5]

    metas = load_metas(stage_dir)
    if not metas:
        sys.exit("group_card: no staged variants found")

    with open(file_ids_path, encoding="utf-8") as f:
        file_ids = json.load(f)
    missing = [m["variant"] for m in metas if not file_ids.get(m["variant"])]
    if missing:
        sys.exit(f"group_card: no file_id for {', '.join(missing)}")

    banner = find_banner()
    payload = build_payload(metas, shared_env(metas[0]), bool(banner), file_ids)
    if len(payload["markdown"]) > RICH_LIMIT:
        sys.exit(f"group_card: {len(payload['markdown'])} chars exceeds {RICH_LIMIT}")

    with open(payload_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False)
    with open(attachments_path, "w", encoding="utf-8") as f:
        f.write(f"banner_file=@{banner}\n" if banner else "")

    print(
        f"[info] group_card: {len(metas)} variant(s), {len(payload['markdown'])} chars (limit {RICH_LIMIT}) \u2705",
        file=sys.stderr,
        flush=True,
    )


if __name__ == "__main__":
    main()
