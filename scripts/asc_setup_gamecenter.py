#!/usr/bin/env python3
"""
One-shot: create the Game Center config for Nihongo Ride via the App Store
Connect API — the Time Attack leaderboard + 5 achievements, each with en-US +
zh-Hans localizations and the badge art in design/gamecenter/.

Already run once on 2026-06-19 (Game Center enabled for app 6777469778,
leaderboard `ta_score` + ach_* created). Kept for audit / reproducibility; it
is NOT idempotent — re-running creates duplicates. To re-run cleanly, delete the
existing gameCenterLeaderboards / gameCenterAchievements first.

vendorIdentifiers MUST match the constants in GameCenterManager.swift.

Requires: PyJWT, requests, and the shared ASC key at
~/.appstoreconnect/private_keys/AuthKey_DMMFP6XTXX.p8

Image-commit note: gameCenter*Images commit with {uploaded: true} ONLY — unlike
appScreenshots they have no `sourceFileChecksum` attribute (409 if sent).
"""
import time, requests, jwt

KEY_ID = "DMMFP6XTXX"
ISSUER = "c5671c11-49ec-47d9-bd38-5e3c1a249416"
KEY_PATH = f"/Users/jason/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"
BASE = "https://api.appstoreconnect.apple.com"
APP = "6777469778"
IMGDIR = "design/gamecenter"


def tok():
    k = open(KEY_PATH).read()
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 18 * 60, "aud": "appstoreconnect-v1"},
                      k, algorithm="ES256", headers={"kid": KEY_ID})


def hdr():
    return {"Authorization": f"Bearer {tok()}", "Content-Type": "application/json"}


def post(path, body):
    r = requests.post(f"{BASE}{path}", headers=hdr(), json=body)
    if r.status_code >= 300:
        print("POST", path, r.status_code, r.text[:400]); r.raise_for_status()
    return r.json()["data"]


def upload_image(img_type, rel_key, rel_type, loc_id, path):
    data = open(path, "rb").read()
    d = post(f"/v1/{img_type}", {"data": {"type": img_type,
             "attributes": {"fileName": path.split("/")[-1], "fileSize": len(data)},
             "relationships": {rel_key: {"data": {"type": rel_type, "id": loc_id}}}}})
    for op in d["attributes"]["uploadOperations"]:
        h = {x["name"]: x["value"] for x in op["requestHeaders"]}
        requests.request(op["method"], op["url"], headers=h,
                         data=data[op["offset"]:op["offset"] + op["length"]]).raise_for_status()
    # GC images commit with uploaded:true only (no checksum attribute).
    r = requests.patch(f"{BASE}/v1/{img_type}/{d['id']}", headers=hdr(),
                       json={"data": {"type": img_type, "id": d["id"], "attributes": {"uploaded": True}}})
    r.raise_for_status()


def main():
    # Enable Game Center (creates the gameCenterDetail).
    gcd = post("/v1/gameCenterDetails", {"data": {"type": "gameCenterDetails",
               "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})["id"]

    # Leaderboard.
    lb = post("/v1/gameCenterLeaderboards", {"data": {"type": "gameCenterLeaderboards",
        "attributes": {"referenceName": "Time Attack High Score", "vendorIdentifier": "ta_score",
                       "defaultFormatter": "INTEGER", "submissionType": "BEST_SCORE", "scoreSortType": "DESC"},
        "relationships": {"gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": gcd}}}}})["id"]
    for loc, name in [("en-US", "Time Attack"), ("zh-Hans", "限时赛")]:
        l = post("/v1/gameCenterLeaderboardLocalizations", {"data": {"type": "gameCenterLeaderboardLocalizations",
            "attributes": {"locale": loc, "name": name},
            "relationships": {"gameCenterLeaderboard": {"data": {"type": "gameCenterLeaderboards", "id": lb}}}}})["id"]
        upload_image("gameCenterLeaderboardImages", "gameCenterLeaderboardLocalization",
                     "gameCenterLeaderboardLocalizations", l, f"{IMGDIR}/leaderboard_ta_score.png")

    # Achievements (vendorIdentifier == GameCenterManager.Achievement.rawValue).
    ach = [
        ("ach_first_ride", "First Ride", 10, "first_ride.png",
         ("First Ride", "Finish your first ride.", "You completed your first ride!"),
         ("首次出发", "完成你的第一程。", "你完成了第一程!")),
        ("ach_words_100", "Century", 20, "words_100.png",
         ("Century", "Type 100 words across your rides.", "You've typed 100 words!"),
         ("百词", "累计打对 100 个词。", "你累计打对了 100 个词!")),
        ("ach_words_1000", "Long Hauler", 50, "words_1000.png",
         ("Long Hauler", "Type 1,000 words across your rides.", "You've typed 1,000 words!"),
         ("千里", "累计打对 1000 个词。", "你累计打对了 1000 个词!")),
        ("ach_streak_7", "Seven-Day Streak", 30, "streak_7.png",
         ("Seven-Day Streak", "Ride 7 days in a row.", "Seven days straight — great streak!"),
         ("七日连骑", "连续 7 天骑行。", "连续七天,势头正好!")),
        ("ach_flawless", "Flawless Run", 40, "flawless.png",
         ("Flawless Run", "Finish a run flawlessly.", "A flawless run — perfect!"),
         ("完美一程", "完成一局完美骑行。", "完美一程,无可挑剔!")),
    ]
    for vid, ref, pts, img, en, zh in ach:
        aid = post("/v1/gameCenterAchievements", {"data": {"type": "gameCenterAchievements",
            "attributes": {"referenceName": ref, "vendorIdentifier": vid, "points": pts,
                           "showBeforeEarned": True, "repeatable": False},
            "relationships": {"gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": gcd}}}}})["id"]
        for loc, (nm, bef, aft) in [("en-US", en), ("zh-Hans", zh)]:
            l = post("/v1/gameCenterAchievementLocalizations", {"data": {"type": "gameCenterAchievementLocalizations",
                "attributes": {"locale": loc, "name": nm, "beforeEarnedDescription": bef, "afterEarnedDescription": aft},
                "relationships": {"gameCenterAchievement": {"data": {"type": "gameCenterAchievements", "id": aid}}}}})["id"]
            upload_image("gameCenterAchievementImages", "gameCenterAchievementLocalization",
                         "gameCenterAchievementLocalizations", l, f"{IMGDIR}/{img}")
    print("Game Center config created.")


if __name__ == "__main__":
    main()
