# ======================================================
# 📨 TELEGRAM — Post Payload Builder
# ======================================================

from __future__ import annotations

import glob
import json
import os
import random
import sys
import zipfile

import rich_message as rm

RICH_LIMIT = 32768
META_NAME = "luminaire.json"
BANNER_DIR = "banner"
BANNER_PATTERNS = ("*.png", "*.jpg", "*.jpeg")


def load_metas(stage_dir: str) -> list:
    metas = []
    for path in glob.glob(os.path.join(stage_dir, "**", "*.zip"), recursive=True):
        with zipfile.ZipFile(path) as archive:
            if META_NAME not in archive.namelist():
                continue
            meta = json.loads(archive.read(META_NAME))
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
            "ADDON_VERSIONS": first.get("addon_versions", ""),
            "TUNING_VERSIONS": first.get("tuning_versions", ""),
            "APPLIED_TUNING": first.get("applied_tuning", ""),
            "SKIPPED_TUNING": first.get("skipped_tuning", ""),
        }
    )
    return env


def variant_title(meta: dict) -> str:
    key = meta["variant"]
    version = meta.get("variant_version", "")
    has_susfs = key.endswith("_SUSFS")
    base = key[: -len("_SUSFS")] if has_susfs else key
    parts = [" ".join(p for p in (rm.variant_display(base), version) if p)]
    if has_susfs:
        parts.append(" ".join(p for p in ("SuSFS", meta.get("susfs_version", "")) if p))
    return " \u00b7 ".join(parts)


def variant_block(meta: dict, index: int) -> str:
    return "\n".join(
        [
            rm.variant_header(variant_title(meta), rm.release_url(meta["variant"])),
            "",
            f"![](tg://document?id=zip{index})",
            "",
        ]
    )


def attachment_specs(metas: list, banners: list) -> list:
    specs = [f"banner_file{i}=@{path}" for i, path in enumerate(banners, 1)]
    for i, meta in enumerate(metas, 1):
        specs.append(f"zip_{i}=@{meta['zip_path']};filename={meta['zip_name']}")
    return specs


def find_banners() -> list:
    base = os.path.join(os.path.dirname(os.path.abspath(__file__)), BANNER_DIR)
    banners = sorted({p for pattern in BANNER_PATTERNS for p in glob.glob(os.path.join(base, pattern))})
    if not banners:
        sys.exit(f"post_card: banner requested but no {BANNER_PATTERNS} found in {base}")
    random.shuffle(banners)
    return banners


def banner_requested() -> bool:
    return os.environ.get("POST_BANNER", "0").lower() in ("1", "true", "yes")


def build_payload(metas: list, env: dict, banner_count: int) -> dict:
    blocks = "\n".join(variant_block(m, i) for i, m in enumerate(metas, 1))
    banner_ids = [f"banner{i}" for i in range(1, banner_count + 1)]
    markdown = rm.compose_markdown(env, blocks, banner_ids=banner_ids)
    media = [
        {"id": f"banner{i}", "media": {"type": "photo", "media": f"attach://banner_file{i}"}}
        for i in range(1, banner_count + 1)
    ]
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

    banners = find_banners() if banner_requested() else []
    payload = build_payload(metas, shared_env(metas[0]), len(banners))
    if len(payload["markdown"]) > RICH_LIMIT:
        sys.exit(f"post_card: {len(payload['markdown'])} chars exceeds {RICH_LIMIT}")

    with open(payload_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False)
    with open(attachments_path, "w", encoding="utf-8") as f:
        f.write("\n".join(attachment_specs(metas, banners)) + "\n")

    print(
        f"[info] post_card: {len(metas)} variant(s), banners={len(banners)}, {len(payload['markdown'])} chars (limit {RICH_LIMIT}) \u2705",
        file=sys.stderr,
        flush=True,
    )


if __name__ == "__main__":
    main()
