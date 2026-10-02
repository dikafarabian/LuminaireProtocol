from __future__ import annotations

import glob
import json
import os
import sys
import zipfile

import rich_message as rm

RICH_LIMIT = 32768
META_NAME = "luminaire.json"
BANNER_NAMES = ("banner.jpg", "banner.jpeg", "banner.png")


def load_metas(stage_dir: str) -> list:
    metas = []
    for path in glob.glob(os.path.join(stage_dir, "**", "*.zip"), recursive=True):
        try:
            with zipfile.ZipFile(path) as archive:
                meta = json.loads(archive.read(META_NAME))
        except KeyError:
            sys.exit(f"post_card: {os.path.basename(path)} has no {META_NAME}")
        meta["zip_path"] = path
        meta["zip_name"] = os.path.basename(path)
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


def attachment_specs(metas: list, banner: str) -> list:
    specs = [f"banner_file=@{banner}"] if banner else []
    for i, meta in enumerate(metas, 1):
        specs.append(f"zip_{i}=@{meta['zip_path']};filename={meta['zip_name']}")
    return specs


def find_banner() -> str:
    base = os.path.dirname(os.path.abspath(__file__))
    for name in BANNER_NAMES:
        candidate = os.path.join(base, name)
        if os.path.isfile(candidate):
            return candidate
    sys.exit(f"post_card: banner requested but none of {BANNER_NAMES} found in {base}")


def banner_requested() -> bool:
    return os.environ.get("POST_BANNER", "0").lower() in ("1", "true", "yes")


def build_payload(metas: list, env: dict, has_banner: bool) -> dict:
    blocks = "\n".join(variant_block(m, i) for i, m in enumerate(metas, 1))
    markdown = rm.compose_markdown(env, blocks, has_banner=has_banner)
    media = []
    if has_banner:
        media.append({"id": "banner", "media": {"type": "photo", "media": "attach://banner_file"}})
    for i in range(1, len(metas) + 1):
        media.append({"id": f"zip{i}", "media": {"type": "document", "media": f"attach://zip_{i}"}})
    return {"markdown": markdown, "media": media}


def main() -> None:
    if len(sys.argv) != 4:
        sys.exit("usage: post_card.py <stage-dir> <out-payload-json> <out-attachments-file>")
    stage_dir, payload_path, attachments_path = sys.argv[1:4]

    metas = load_metas(stage_dir)
    if not metas:
        sys.exit("post_card: no staged variants found")

    banner = find_banner() if banner_requested() else ""
    payload = build_payload(metas, shared_env(metas[0]), bool(banner))
    if len(payload["markdown"]) > RICH_LIMIT:
        sys.exit(f"post_card: {len(payload['markdown'])} chars exceeds {RICH_LIMIT}")

    with open(payload_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False)
    with open(attachments_path, "w", encoding="utf-8") as f:
        f.write("\n".join(attachment_specs(metas, banner)) + "\n")

    print(
        f"[info] post_card: {len(metas)} variant(s), banner={'yes' if banner else 'no'}, {len(payload['markdown'])} chars (limit {RICH_LIMIT}) \u2705",
        file=sys.stderr,
        flush=True,
    )


if __name__ == "__main__":
    main()
