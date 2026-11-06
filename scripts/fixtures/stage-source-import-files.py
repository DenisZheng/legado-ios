#!/usr/bin/env python3
"""在指定模拟器的 Files 本地目录准备导入样本，避免共享应用目录的文档 ID 映射。"""

import json
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import unquote, urlparse


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: stage-source-import-files.py <booted-simulator-UUID>")
    device_id = sys.argv[1]
    devices = json.loads(command("xcrun", "simctl", "list", "devices", "--json"))["devices"]
    device = next(d for values in devices.values() for d in values if d["udid"] == device_id)
    if device["state"] != "Booted":
        raise RuntimeError("指定模拟器尚未启动。")
    data_root = Path(device["dataPath"]).resolve()
    fixture_container = Path(command(
        "xcrun", "simctl", "get_app_container", device_id,
        "com.epiboly.legado.source-import-fixtures", "data",
    )).resolve()
    app_plist = subprocess.check_output(["xcrun", "simctl", "listapps", device_id])
    apps = json.loads(subprocess.check_output(
        ["plutil", "-convert", "json", "-o", "-", "--", "-"], input=app_plist,
    ))
    raw_group = apps["com.apple.DocumentsApp"]["GroupContainers"]["group.com.apple.FileProvider.LocalStorage"]
    parsed_group = urlparse(raw_group)
    if parsed_group.scheme != "file" or parsed_group.netloc not in {"", "localhost"}:
        raise RuntimeError("Files 返回的本地容器不是文件 URL。")
    group = Path(unquote(parsed_group.path)).resolve()
    destination = (group / "File Provider Storage" / "Legado Import Fixtures").resolve()
    # 只向该模拟器的指定夹具目录写入，不修改提供器数据库或其他应用数据。
    if not fixture_container.is_relative_to(data_root) or not destination.is_relative_to(data_root):
        raise RuntimeError("夹具路径不在指定模拟器的数据目录内。")
    names = (
        "JSON-Source.json", "JSON-Uppercase.JSON", "JSON-Text.txt", "RSS-Source.json",
        "TXT-Book.txt", "TXT-Uppercase.TXT", "EPUB-Book.epub",
    )
    originals = [fixture_container / "Documents" / name for name in names]
    for _ in range(20):
        if all(path.is_file() and path.stat().st_size > 0 for path in originals):
            break
        time.sleep(0.5)
    else:
        raise RuntimeError("测试应用未生成全部 7 个非空文件。")
    destination.mkdir(parents=True, exist_ok=True)
    for path in originals:
        target = destination / path.name
        data = path.read_bytes()
        if not target.exists() or target.read_bytes() != data:
            target.write_bytes(data)
        if target.read_bytes() != data:
            raise RuntimeError(f"夹具校验失败：{path.name}")
    print(f"Staged {len(names)} files in Files > On My iPhone > Legado Import Fixtures")


if __name__ == "__main__":
    main()
