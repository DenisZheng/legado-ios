#!/usr/bin/env python3
"""读取本地 RSS 源集合，生成能力清单和未执行矩阵；不联网、不执行源脚本。"""

import argparse
import csv
import hashlib
import json
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


STAGES = (
    "import", "sort_search", "refresh", "article_parse",
    "content", "image", "video", "persistence",
)
OBJECTS = ("java", "cache", "cookie", "source")
DISPLAY_FIELDS = {"sourceName", "sourceGroup", "sourceComment"}
KEY_FIELDS = (
    "ruleArticles", "ruleContent", "ruleNextPage", "nextContentUrl", "sortUrl",
    "header", "loginUrl", "loginUi", "loginCheckJs", "preloadJs", "injectJs", "jsLib",
)


def references(text, object_name):
    # 字面调用引用，包括 obj.method() 和 obj["method"]()；不作 JS 执行或完整语法分析。
    pattern = rf"\b{object_name}\s*(?:\.\s*([\w$]+)|\[\s*['\"]([\w$]+)['\"]\s*\])\s*\("
    return sorted({dot or bracket for dot, bracket in re.findall(pattern, text)})


def inspect_source(source):
    fields = {key: value for key, value in source.items()
              if isinstance(value, str) and key not in DISPLAY_FIELDS}
    text = "\n".join(fields.values())
    calls = {obj: references(text, obj) for obj in OBJECTS}
    tags = set()
    if source.get("singleUrl"):
        tags.add("single-page")
    elif not source.get("ruleArticles"):
        tags.add("default-feed")
    if source.get("ruleArticles"):
        tags.add("custom-rules")
    if re.search(r"@js:|<js>|\b(?:java|cache|cookie)\s*[.\[]", text):
        tags.add("js")
    if any(source.get(key) for key in ("loginUrl", "loginUi", "loginCheckJs")):
        tags.add("login")
    if (source.get("singleUrl") or source.get("injectJs") or source.get("preloadJs")
            or re.search(r"webView[\"']?\s*:\s*true", text)
            or any(name.startswith("webView") for name in calls["java"])):
        tags.add("webview")
    if source.get("ruleImage") or source.get("coverDecodeJs"):
        tags.add("image")
    if source.get("header"):
        tags.add("header")
    if re.search(r"\.m3u8\b", text, re.IGNORECASE):
        tags.add("hls-reference")
    if re.search(r"\.mpd\b|<MPD\b", text, re.IGNORECASE):
        tags.add("mpd-reference")
    if re.search(r"createSymmetricCrypto|javax\.crypto", text):
        tags.add("crypto")
    for obj in ("cache", "cookie"):
        if calls[obj]:
            tags.add(obj)
    page_calls = {
        field: {obj: references(value, obj) for obj in OBJECTS}
        for field, value in fields.items() if field in {"injectJs", "preloadJs"}
    }
    return {
        "source_id": hashlib.sha256(source["sourceUrl"].encode()).hexdigest()[:16],
        "source_name": source.get("sourceName", ""),
        "source_url": source["sourceUrl"],
        "capabilities": sorted(tags),
        "literal_api_references": calls,
        "page_script_references": page_calls,
        "nonempty_fields": sorted(key for key, value in source.items() if value),
    }


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_file", type=Path)
    parser.add_argument("--output", type=Path, required=True, help="新的本地输出目录，必须不存在")
    parser.add_argument("--ios-commit", required=True)
    parser.add_argument("--android-commit", required=True)
    args = parser.parse_args()

    raw = args.source_file.read_bytes()
    sources = json.loads(raw.decode("utf-8-sig"))
    if not isinstance(sources, list) or not sources:
        parser.error("源集合必须是非空 JSON 数组。")
    if any(not isinstance(s, dict) or not isinstance(s.get("sourceUrl"), str)
           or not s["sourceUrl"].strip() for s in sources):
        parser.error("每条源必须包含非空字符串 sourceUrl。")
    identities = Counter(s["sourceUrl"] for s in sources)
    if any(count > 1 for count in identities.values()):
        parser.error("集合包含重复 sourceUrl；请先记录并确定合并规则，脚本不会静默丢弃条目。")
    entries = [inspect_source(source) for source in sources]
    if len({entry["source_id"] for entry in entries}) != len(entries):
        parser.error("source_id 出现冲突，无法生成可靠矩阵。")
    # 不覆盖先前运行的结果，也不修改用户的原始集合。
    args.output.mkdir(parents=True, exist_ok=False)
    capabilities = Counter(tag for entry in entries for tag in entry["capabilities"])
    api_counts = {
        obj: dict(Counter(method for entry in entries
                          for method in entry["literal_api_references"][obj]).most_common())
        for obj in OBJECTS
    }
    field_counts = {field: sum(bool(source.get(field)) for source in sources) for field in KEY_FIELDS}
    manifest = {
        "run_id": args.output.name,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "input_file": args.source_file.name,
        "input_sha256": hashlib.sha256(raw).hexdigest(),
        "input_bytes": len(raw),
        "source_count": len(sources),
        "unique_source_count": len(identities),
        "duplicate_policy": "拒绝重复 sourceUrl，等待显式合并规则",
        "ios_commit": args.ios_commit,
        "android_commit": args.android_commit,
        "android_execution": "NOT_RUN",
        "ios_execution": "NOT_RUN",
        "device": None,
        "network_execution": False,
        "inventory_only": True,
        "capability_detection": "基于字段和字面引用的启发式分类，不代表执行结果或完整 JS 调用分析",
        "capability_counts": dict(capabilities.most_common()),
        "nonempty_field_counts": field_counts,
        "type_counts": dict(Counter(str(source.get("type", "missing")) for source in sources)),
        "literal_api_source_counts": api_counts,
    }
    write_json(args.output / "manifest.json", manifest)
    write_json(args.output / "source-index.json", entries)
    with (args.output / "results.csv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=[
            "run_id", "source_id", "capabilities", "stage", "status", "evidence_type",
            "android_result", "ios_commit", "device", "reason", "task_id", "evidence_path",
        ], lineterminator="\n")
        writer.writeheader()
        for entry in entries:
            for stage in STAGES:
                writer.writerow({
                    "run_id": args.output.name, "source_id": entry["source_id"],
                    "capabilities": ";".join(entry["capabilities"]), "stage": stage,
                    "status": "NOT_RUN", "evidence_type": "", "android_result": "NOT_RUN",
                    "ios_commit": args.ios_commit, "device": "",
                    "reason": "仅完成本地集合盘点，尚未在 Android/iOS 执行该阶段",
                    "task_id": "P3-03", "evidence_path": "",
                })
    print(json.dumps({"sources": len(entries), "stage_rows": len(entries) * len(STAGES),
                      "output": str(args.output), "execution": "NOT_RUN"}, ensure_ascii=False))


if __name__ == "__main__":
    main()
