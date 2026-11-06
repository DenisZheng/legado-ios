#!/usr/bin/env python3
"""Live smoke checks for the small public RSS compatibility set.

This is deliberately separate from deterministic unit tests and IPA builds:
a publisher outage must not block application compilation.
"""

from __future__ import annotations

import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from typing import Iterable

FEEDS = (
    ("少数派", "https://sspai.com/feed"),
    ("异次元软件世界", "https://feed.iplaysoft.com/"),
)
USER_AGENT = "Legado-iOS-RSS-SmokeTest/1.0 (+https://github.com/DenisZheng/legado-ios)"
TIMEOUT_SECONDS = 25
MAX_BODY_BYTES = 4 * 1024 * 1024
RETRIES = 2


@dataclass
class FeedResult:
    name: str
    url: str
    final_url: str
    status: int
    feed_title: str
    entry_count: int
    format_name: str


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1].split(":")[-1].lower()


def child_text(element: ET.Element, wanted: str) -> str:
    for child in list(element):
        if local_name(child.tag) == wanted:
            return "".join(child.itertext()).strip()
    return ""


def entry_link(entry: ET.Element) -> str:
    for child in list(entry):
        if local_name(child.tag) != "link":
            continue
        href = (child.attrib.get("href") or "").strip()
        rel = (child.attrib.get("rel") or "alternate").strip().lower()
        if href and rel in ("alternate", ""):
            return href
        text = "".join(child.itertext()).strip()
        if text:
            return text
    return ""


def parse_feed(body: bytes) -> tuple[str, int, str]:
    try:
        root = ET.fromstring(body)
    except ET.ParseError as exc:
        raise ValueError(f"response is not valid XML: {exc}") from exc

    root_name = local_name(root.tag)
    if root_name == "rss":
        channel = next((node for node in list(root) if local_name(node.tag) == "channel"), None)
        if channel is None:
            raise ValueError("RSS document has no channel element")
        title = child_text(channel, "title")
        entries = [node for node in list(channel) if local_name(node.tag) == "item"]
        format_name = "RSS"
    elif root_name == "feed":
        title = child_text(root, "title")
        entries = [node for node in list(root) if local_name(node.tag) == "entry"]
        format_name = "Atom"
    elif root_name == "rdf":
        title = child_text(root, "title")
        entries = [node for node in list(root) if local_name(node.tag) == "item"]
        format_name = "RSS/RDF"
    else:
        raise ValueError(f"unexpected XML root element: {root_name!r}")

    if not title:
        raise ValueError("feed title is empty")
    if not entries:
        raise ValueError("feed contains no item/entry elements")

    valid_entries = 0
    for entry in entries:
        title_text = child_text(entry, "title")
        link_text = entry_link(entry)
        if title_text and link_text:
            valid_entries += 1

    if valid_entries == 0:
        raise ValueError("feed has no entries with both title and link")

    return title, valid_entries, format_name


def fetch(url: str) -> tuple[int, str, bytes]:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "application/rss+xml, application/atom+xml, application/xml, text/xml;q=0.9, */*;q=0.5",
            "Accept-Encoding": "identity",
        },
        method="GET",
    )

    last_error: Exception | None = None
    for attempt in range(RETRIES + 1):
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
                status = response.status
                final_url = response.geturl()
                body = response.read(MAX_BODY_BYTES + 1)
            if status < 200 or status >= 300:
                raise ValueError(f"HTTP status {status}")
            if len(body) > MAX_BODY_BYTES:
                raise ValueError(f"response exceeded {MAX_BODY_BYTES} bytes")
            if not body.strip():
                raise ValueError("empty response body")
            return status, final_url, body
        except urllib.error.HTTPError as exc:
            last_error = ValueError(f"HTTP status {exc.code}")
            if exc.code not in (408, 425, 429, 500, 502, 503, 504):
                break
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
            last_error = exc
        if attempt < RETRIES:
            time.sleep(2 ** attempt)

    raise ValueError(str(last_error or "request failed"))


def check_feed(name: str, url: str) -> FeedResult:
    status, final_url, body = fetch(url)
    title, count, format_name = parse_feed(body)
    return FeedResult(name, url, final_url, status, title, count, format_name)


def main(feeds: Iterable[tuple[str, str]]) -> int:
    failures = 0
    results: list[FeedResult] = []

    print("Live public RSS smoke test")
    print("==========================")
    for name, url in feeds:
        try:
            result = check_feed(name, url)
            results.append(result)
            print(
                f"PASS | {result.name} | HTTP {result.status} | "
                f"{result.format_name} | {result.entry_count} valid entries | "
                f"title={result.feed_title!r}"
            )
            if result.final_url != result.url:
                print(f"       redirected to: {result.final_url}")
        except Exception as exc:  # surfaced in CI log and summary
            failures += 1
            print(f"FAIL | {name} | {url} | {exc}")

    summary_path = __import__("os").environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as summary:
            summary.write("# Public RSS live smoke test\n\n")
            summary.write("| Source | Result | Format | Valid entries | Feed title |\n")
            summary.write("|---|---:|---|---:|---|\n")
            for result in results:
                summary.write(
                    f"| {result.name} | HTTP {result.status} | {result.format_name} | "
                    f"{result.entry_count} | {result.feed_title.replace('|', '/')} |\n"
                )
            if failures:
                summary.write(f"\n**Failed feeds:** {failures}\n")
            else:
                summary.write("\nAll public feeds passed.\n")

    print(f"\nResult: {len(results)} passed, {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main(FEEDS))
