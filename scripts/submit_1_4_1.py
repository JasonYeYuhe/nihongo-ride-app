#!/usr/bin/env python3
"""One-shot: attach the processed 1.4.1 builds and submit both platforms for review.

Idempotent-ish: re-running after a partial failure is safe (attach is a PATCH;
it skips submit if a submission is already open). Run only once both builds are VALID.
"""
import json, subprocess, sys, os

APP = "6777469778"
TARGETS = [
    {"name": "macOS", "platform": "MAC_OS", "version_id": "2e925e56-57fa-4455-981a-03ba3971f5d3", "build_num": "7"},
    {"name": "iOS",   "platform": "IOS",    "version_id": "bee240c1-6870-458a-bed0-9ebb0fed9591", "build_num": "8"},
]

def asc(method, ep, body=None):
    env = dict(os.environ)
    if body is not None:
        json.dump(body, open("/tmp/asc_body.json", "w"), ensure_ascii=False)
        env["ASC_BODY_FILE"] = "/tmp/asc_body.json"
    out = subprocess.run(["scripts/asc_api.sh", method, ep], capture_output=True, text=True, env=env).stdout
    try:
        return json.loads(out) if out.strip() else {}
    except Exception:
        return {"_raw": out}

def find_build(num):
    d = asc("GET", f"/v1/builds?filter[app]={APP}&limit=30&sort=-uploadedDate"
                   f"&fields[builds]=version,processingState,usesNonExemptEncryption")
    for b in d.get("data", []):
        a = b["attributes"]
        if a["version"] == num:
            return b["id"], a
    return None, None

def main():
    for t in TARGETS:
        print(f"\n===== {t['name']} (build {t['build_num']}) =====")
        bid, battr = find_build(t["build_num"])
        if not bid:
            print(f"  !! build {t['build_num']} not found — aborting"); sys.exit(1)
        if battr.get("processingState") != "VALID":
            print(f"  !! build {t['build_num']} state={battr.get('processingState')} (not VALID) — aborting"); sys.exit(1)
        print(f"  build id={bid} VALID  usesNonExemptEncryption={battr.get('usesNonExemptEncryption')}")

        # export compliance (Info.plist declares ITSAppUsesNonExemptEncryption=false;
        # set explicitly if ASC still shows it unanswered)
        if battr.get("usesNonExemptEncryption") is None:
            r = asc("PATCH", f"/v1/builds/{bid}", {"data": {"type": "builds", "id": bid,
                    "attributes": {"usesNonExemptEncryption": False}}})
            print("  set usesNonExemptEncryption=false:", "OK" if "errors" not in r else r.get("errors"))

        # attach build to version
        r = asc("PATCH", f"/v1/appStoreVersions/{t['version_id']}/relationships/build",
                {"data": {"type": "builds", "id": bid}})
        print("  attach build:", "OK" if not r.get("errors") else r["errors"])

        # confirm attached
        chk = asc("GET", f"/v1/appStoreVersions/{t['version_id']}/build?fields[builds]=version")
        print("  attached build version:", (chk.get("data") or {}).get("attributes", {}).get("version"))

        # create review submission
        sub = asc("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions",
                  "attributes": {"platform": t["platform"]},
                  "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
        if sub.get("errors"):
            print("  create submission ERR:", sub["errors"][0].get("detail")); continue
        sid = sub["data"]["id"]
        print("  reviewSubmission id=", sid)

        # add the version as an item
        it = asc("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems",
                 "relationships": {
                     "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
                     "appStoreVersion": {"data": {"type": "appStoreVersions", "id": t["version_id"]}}}}})
        print("  add item:", "OK" if not it.get("errors") else it["errors"][0].get("detail"))

        # submit
        fin = asc("PATCH", f"/v1/reviewSubmissions/{sid}", {"data": {"type": "reviewSubmissions",
                  "id": sid, "attributes": {"submitted": True}}})
        if fin.get("errors"):
            print("  SUBMIT ERR:", fin["errors"][0].get("detail"))
        else:
            print("  SUBMITTED ✓ state=", fin["data"]["attributes"].get("state"))

if __name__ == "__main__":
    main()
