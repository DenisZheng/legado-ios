# Public real-world RSS compatibility fixtures

This small fixture set is derived from public feed endpoints found in the
project maintainer's supplied Legado source collection.

## Sources

| Source | Public feed URL | Format |
|---|---|---|
| 少数派 | https://sspai.com/feed | RSS 2.0 |
| 异次元软件世界 | https://feed.iplaysoft.com/ | RSS / Atom feed |

The endpoints were also checked live by GitHub Actions on 2026-11-06:
both returned HTTP 200 and valid RSS XML. The smoke run found 10 valid entries
for 少数派 and 30 for 异次元软件世界. See
[Public RSS Live Smoke Test](https://github.com/DenisZheng/legado-ios/actions/runs/42177537134).

## Fixture policy

The XML files are **sanitized synthetic fixtures**, not copies of publisher
articles or live feed payloads. They preserve only the basic RSS 2.0 shape
needed for deterministic parser tests. Titles, URLs, dates, and summaries in
the XML fixtures are synthetic test values.

The manifest contains only public feed URLs and minimal Legado source fields.
It intentionally excludes cookies, credentials, private feeds, personal
sources, custom JavaScript, login rules, and the rest of the supplied export.

## Updating

If a publisher changes its feed format, update the synthetic fixture to model
the newly observed structure and keep the test deterministic. Do not add
full article bodies or large live feed snapshots to this repository.
