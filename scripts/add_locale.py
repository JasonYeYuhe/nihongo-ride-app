#!/usr/bin/env python3
"""Add (or update) one App Store storefront locale, and PROVE it landed.

Two records make a locale visible, and forgetting either leaves a half-configured
listing that App Store Connect will happily accept:

  * `appInfoLocalizations`      — name, subtitle, privacy policy. App-level.
  * `appStoreVersionLocalizations` — description, keywords, What's New, URLs. Per version.

Everything written here is READ BACK and compared byte for byte, because ASC
silently truncates and normalises: the response to a PATCH is not evidence that
the stored text is the text that was sent. That is the same rule
`submit_*.py:set_whats_new` follows, and it is why the star-glyph rejection is
caught here rather than at review.

Usage:
  python3 scripts/add_locale.py --locale ja --content docs/store/ja-listing.json [--platform IOS|MAC_OS] [--dry-run]

The content file is JSON with any of: name, subtitle, description, keywords,
whatsNew, promotionalText, supportUrl, marketingUrl.
"""
import argparse, json, subprocess, sys
from pathlib import Path

APP = "6777469778"
REPO = Path(__file__).resolve().parent.parent
APP_INFO_FIELDS = {"name", "subtitle", "privacyPolicyUrl"}

# Quantities the copy is allowed to name, and how to recompute each. A needle that appears in
# the copy while its computed value does not is a stale figure.
CHECKED_FIGURES = {
    "passages": lambda N: [{"needle": "読解パッセージ", "value": str(N["passages"])},
                           {"needle": "reading passages", "value": str(N["passages"])},
                           {"needle": "阅读文章", "value": str(N["passages"])}],
}
VERSION_FIELDS = {"description", "keywords", "whatsNew", "promotionalText",
                  "supportUrl", "marketingUrl"}
_failures = []


def fail(msg):
    print(f"  !! {msg}")
    _failures.append(msg)


def asc(method, endpoint, body=None):
    cmd = ["scripts/asc_api.sh", method, endpoint]
    if body is not None:
        cmd.append(json.dumps(body))
    r = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
    if r.returncode != 0:
        return {"errors": [{"detail": f"asc_api.sh exited {r.returncode}: {r.stderr[:200]}"}]}
    if not r.stdout.strip():
        # An empty body is a FAILURE, not an empty success — a 204 on a GET means
        # the request was wrong, and treating it as {} makes it read as "nothing there".
        return {"errors": [{"detail": "empty response"}]}
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError:
        return {"errors": [{"detail": f"non-JSON: {r.stdout[:200]}"}]}


def upsert(kind, parent_ep, create_rel, locale, attrs, dry):
    """Create or patch one localization, then read every field back."""
    if not attrs:
        return
    existing = asc("GET", f"{parent_ep}?limit=60&fields[{kind}]=locale")
    if existing.get("errors"):
        fail(f"{kind}: list failed: {existing['errors'][0].get('detail')}")
        return
    by_locale = {r["attributes"]["locale"]: r["id"] for r in existing.get("data", [])}
    lid = by_locale.get(locale)
    if dry:
        print(f"  [dry-run] would {'PATCH ' + lid if lid else 'CREATE'} {kind} {locale} "
              f"with {sorted(attrs)}")
        return

    if lid:
        r = asc("PATCH", f"/v1/{kind}/{lid}",
                {"data": {"type": kind, "id": lid, "attributes": attrs}})
    else:
        r = asc("POST", f"/v1/{kind}", {"data": {
            "type": kind, "attributes": dict(attrs, locale=locale),
            "relationships": create_rel}})
    if r.get("errors"):
        fail(f"{kind} {locale}: {r['errors'][0].get('detail')}")
        return
    lid = lid or r["data"]["id"]

    # Read back. Every field, compared exactly.
    check = asc("GET", f"/v1/{kind}/{lid}?fields[{kind}]={','.join(sorted(attrs))}")
    got = (check.get("data") or {}).get("attributes", {})
    for key, want in sorted(attrs.items()):
        have = got.get(key)
        if have != want:
            fail(f"{kind} {locale} {key}: stored text differs from what was sent "
                 f"({len(have or '')} chars vs {len(want)})")
        else:
            print(f"    {kind[:16]:16} {locale:8} {key:16} OK ({len(want)} chars, read back identical)")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--locale", required=True)
    ap.add_argument("--content", required=True)
    ap.add_argument("--version", help="marketing version; default = the newest editable one")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--skip-number-check", action="store_true",
                    help="upload copy whose figures this repo cannot confirm; say why in the commit")
    args = ap.parse_args()

    content = json.loads(Path(args.content).read_text(encoding="utf-8"))
    unknown = set(content) - APP_INFO_FIELDS - VERSION_FIELDS
    if unknown:
        print(f"unknown fields in {args.content}: {sorted(unknown)}")
        return 2

    # Store copy is a place numbers go to rot. `en-US` and `zh-Hans` both told users "183
    # reading passages" for months after the corpus reached 233, and the ja draft inherited it
    # by copying. So any figure here that names a quantity this repo can compute is checked
    # against the computation before it is uploaded.
    if not args.skip_number_check:
        from release_numbers import numbers as _n
        N = _n()
        blob = " ".join(str(v) for v in content.values())
        wrong = []
        for key, claimed in CHECKED_FIGURES.items():
            for token in claimed(N):
                if token["needle"] in blob and token["value"] not in blob:
                    wrong.append(f"copy says {token['needle']!r} but {key} is {token['value']}")
        if wrong:
            print("STORE-COPY-FIGURE-MISMATCH:")
            for w in wrong:
                print(f"  {w}")
            print("  Fix the copy, or pass --skip-number-check and say why.")
            return 2

    # App-level record.
    infos = asc("GET", f"/v1/apps/{APP}/appInfos?limit=5")
    if infos.get("errors"):
        print(f"cannot read appInfos: {infos['errors'][0].get('detail')}")
        return 3
    # An app has TWO appInfo records once a version is in preparation: the live one and the
    # editable one. The first draft of this script took data[0], got the live record, and ASC
    # answered "A relationship cannot be created in current state" -- an error that names the
    # symptom and not the cause. Select by state, and fail loudly rather than guess, because
    # picking the wrong one of two look-alike records is this project's oldest defect shape.
    editable = [r for r in infos["data"]
                if r["attributes"].get("state") not in ("READY_FOR_DISTRIBUTION",)
                and r["attributes"].get("appStoreState") != "READY_FOR_SALE"]
    if len(editable) != 1:
        states = [(r["id"], r["attributes"].get("state")) for r in infos["data"]]
        print(f"cannot identify one editable appInfo among {states}")
        return 3
    info_id = editable[0]["id"]
    upsert("appInfoLocalizations",
           f"/v1/appInfos/{info_id}/appInfoLocalizations",
           {"appInfo": {"data": {"type": "appInfos", "id": info_id}}},
           args.locale, {k: v for k, v in content.items() if k in APP_INFO_FIELDS},
           args.dry_run)

    # Per-platform version records.
    for platform in ("MAC_OS", "IOS"):
        q = f"/v1/apps/{APP}/appStoreVersions?limit=5&filter[platform]={platform}"
        if args.version:
            q += f"&filter[versionString]={args.version}"
        vs = asc("GET", q + "&fields[appStoreVersions]=versionString,appStoreState")
        if vs.get("errors") or not vs.get("data"):
            fail(f"{platform}: no version found")
            continue
        # Select by state, never by position. data[0] is whatever ASC returned first, and this
        # file already carries the scar of that: the appInfo lookup above took data[0], got the
        # LIVE record, and answered "A relationship cannot be created in current state". Exactly
        # one editable version must exist, or stop.
        LOCKED = ("READY_FOR_SALE", "IN_REVIEW", "WAITING_FOR_REVIEW", "PENDING_DEVELOPER_RELEASE")
        editable = [r for r in vs["data"] if r["attributes"]["appStoreState"] not in LOCKED]
        if len(editable) != 1:
            fail(f"{platform}: expected exactly one editable version, found "
                 + str([(r["attributes"]["versionString"], r["attributes"]["appStoreState"])
                        for r in vs["data"]]))
            continue
        v = editable[0]
        print(f"  {platform} {v['attributes']['versionString']} "
              f"({v['attributes']['appStoreState']})")
        upsert("appStoreVersionLocalizations",
               f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations",
               {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}},
               args.locale, {k: val for k, val in content.items() if k in VERSION_FIELDS},
               args.dry_run)

    if _failures:
        print(f"\nFAILED with {len(_failures)} problem(s)")
        return 1
    print("\nclean.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
