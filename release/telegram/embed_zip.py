#!/usr/bin/env python3
"""Splice a local zip into a rich-message payload as a document media block.

Bot API 10.3+: rich messages carry general files. The builder writes
'media': [{'id': 'zipfile', 'media': {'type': 'document',
'media': 'attach://zip_file'}}], and the caller posts it with
-F 'rich_message=<payload' -F 'zip_file=@path.zip'.

Usage: embed_zip.py <zip-path> <payload-json>
"""
from __future__ import annotations

import json
import os
import sys


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: embed_zip.py <zip-path> <payload-json>")
    zip_path, payload_path = sys.argv[1], sys.argv[2]

    if not os.path.isfile(zip_path) or os.path.getsize(zip_path) == 0:
        sys.exit(f"embed_zip: {zip_path} missing or empty")

    with open(payload_path, encoding="utf-8") as f:
        payload = json.load(f)

    assert payload.get("markdown"), "payload has no markdown"
    assert payload.get("media") and payload["media"][0].get("media", {}).get(
        "media"
    ) == "attach://zip_file", "payload does not declare attach://zip_file"
    assert "![](tg://document?id=zipfile)" in payload["markdown"], (
        "markdown does not contain the zipfile document block"
    )

    print(f"[info] embed_zip: {os.path.basename(zip_path)} "
          f"({os.path.getsize(zip_path)} bytes) spliced into {payload_path} \u2705",
          flush=True)


if __name__ == "__main__":
    main()