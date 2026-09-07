#!/usr/bin/env python3
"""The App Store Connect release machinery every `scripts/submit_<version>.py` was hand-copying.

WHY THIS FILE EXISTS, MEASURED. `submit_1_30.py` is 791 lines, of which about 160 are that
release's config — VERSION, TARGETS, What's New, the description edits, the review notes — and
the remaining 630 are machinery that is identical in every release and was retyped or pasted by
hand each time. There are 28 such scripts on disk. Shipping therefore cost an hour of careful,
error-prone work before a line of the new feature was involved, and v1.30 proved the risk is not
theoretical: its `do_submit` carried the ordering rule in a comment rather than in the control
flow, both platforms went to Apple without the purchase, and both submissions had to be cancelled
and rebuilt.

WHAT DID **NOT** CHANGE, AND WHY THAT IS THE POINT. The old scripts are the record of what was
actually sent for each release, so **none of them is edited and none is deleted**, including
`submit_1_30.py`. This module was ported from it and is held to it by
`scripts/test_asc_release.py`, which drives BOTH against the same stateful fake App Store Connect
and requires the same API calls, with the same bodies, in the same order. A rewrite that is
merely plausible is what this repo calls an uncalibrated instrument, and "I read it carefully"
is not a control.

WHAT THIS MODULE ADDS ON TOP OF THE PORT. Each addition is a contract that has been written in a
comment in every submit script since v1.5 and enforced by nothing — *where a comment states a
contract, check whether anything enforces it* is this repo's cheapest detector, and it had never
been pointed at the file that ships the releases. All of them live in `preflight`, which runs
before any mode, touches nothing outside this process, and exits non-zero on its own:

  * **The star glyph.** `# What's New — MUST NOT contain the literal star glyph (ASC rejects it)`
    has ridden along in twenty-plus scripts, and `docs/ASC_METADATA.md` records the rejection
    twice. Nothing ever checked. NOTE THE POPULATION THIS SKIPS: the only glyph this repo has
    *measured* a rejection for is U+2605 BLACK STAR, so that is the only one asserted. Other
    glyphs ASC may dislike are unmeasured here, and this check says nothing about them.
  * **`old` must not be a substring of `new` in a description edit.** If it is, the edit
    re-applies on every run and the sentence grows without bound: `edited_description`'s
    already-done branch requires `old` to be ABSENT from the live text, and an append-only edit
    leaves it present, so the next run reads it as un-applied. v1.30's pair happens not to trip
    this; nothing stopped the next one from doing so.
  * **Lengths.** ASC's 4000-character limit was checked for the description only. What's New and
    the review notes have the same limit and were checked by nobody.
  * **`iap=` is a required argument with no default.** The submit gate cannot tell "this release
    sells nothing" from "somebody forgot to wire the purchase up", and those must not be the same
    keystroke. This is v1.24 §C's move — making `resolves:` required rather than defaulted —
    applied to the release path for the same reason.

WHAT A RELEASE SCRIPT LOOKS LIKE NOW. Config, a docstring recording that release's decisions, and
one call:

    from asc_release import Release, main
    main(Release(version="1.31", targets=[...], whats_new={...}, description_edits={...},
                 review_notes=..., iap=None, numbers=N))

`iap=None` is a statement, not a default.
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# Constant across every release of this app. Overridable so a test never has to reach for the
# real identifiers, and so a second app could reuse the module without editing it.
APP = "6777469778"
CONTACT = {"contactFirstName": "Yuhe", "contactLastName": "Ye",
           "contactPhone": "+81 80-3526-7088", "contactEmail": "yyyyy.yeyuhe@gmail.com"}

# ASC's limits on the fields this module writes.
MAX_WHATS_NEW = 4000
MAX_DESCRIPTION = 4000
MAX_REVIEW_NOTES = 4000

# The one glyph this repo has measured App Store Connect rejecting in What's New.
FORBIDDEN_WHATS_NEW_GLYPHS = ("★",)   # BLACK STAR

# A version that can still accept a build and a submission.
SUBMITTABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
               "METADATA_REJECTED", "INVALID_BINARY"}
# A version that must not be touched, and is not an error either.
ALREADY_SUBMITTED = {"READY_FOR_SALE", "IN_REVIEW", "WAITING_FOR_REVIEW",
                     "PENDING_DEVELOPER_RELEASE"}
# States a version reads back as after a successful submit.
SUBMITTED_STATES = {"WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE",
                    "READY_FOR_SALE"}

# States an in-app purchase can be in, split by what a release must do about each. Anything
# outside both sets is a state this module does not understand, and continuing past it is how a
# run submits nothing and exits 0.
IAP_READY = {"READY_TO_SUBMIT"}
IAP_ALREADY_IN = {"WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_BINARY_APPROVAL", "APPROVED",
                  "READY_FOR_SALE"}


class Release:
    """One release's configuration, plus the machinery that ships it.

    Every field a release actually varies is a required keyword argument. Nothing here has a
    default that could stand in for a decision.
    """

    def __init__(self, *, version, targets, whats_new, description_edits, review_notes, iap,
                 app=APP, contact=None, numbers=None):
        self.version = version
        self.targets = list(targets)
        self.whats_new = dict(whats_new)
        self.description_edits = dict(description_edits)
        self.review_notes = review_notes
        # None, or {"id": "<numeric ASC id>", "product_id": "<bundle-style product id>"}.
        self.iap = dict(iap) if iap else None
        self.app = app
        self.contact = dict(contact if contact is not None else CONTACT)
        # Only for the dry run's printout; the copy itself has already been interpolated by the
        # release script, which is where `release_numbers` belongs.
        self.numbers = numbers
        # Every skip and every error lands here, and a non-empty ledger is a non-zero exit.
        self.failures = []

    # --- the ledger --------------------------------------------------------------------------

    def fail(self, message):
        print(f"  FAIL: {message}")
        self.failures.append(message)

    def report(self):
        """Non-zero if anything at all went wrong. The whole point of the ledger."""
        if self.failures:
            print(f"\n{len(self.failures)} FAILURE(S):")
            for f in self.failures:
                print(f"  - {f}")
            return 1
        print("\nclean.")
        return 0

    # --- preflight ---------------------------------------------------------------------------

    def preflight(self):
        """Check the config against every contract the old scripts stated only in comments.

        Raises SystemExit listing every problem at once. It reaches nothing outside this process,
        so it is safe to run before a dry run, and it runs before every mode.
        """
        problems = []

        if not self.version or not self.targets:
            problems.append("a release needs a version and at least one target")

        seen_platforms = set()
        for t in self.targets:
            for key in ("name", "platform", "build_num"):
                if not t.get(key):
                    problems.append(f"target {t!r} is missing {key!r}")
            platform = t.get("platform")
            if platform in seen_platforms:
                problems.append(f"two targets share platform {platform!r} — build numbers are "
                                "per-platform and a duplicate is how v1.25 crossed them")
            seen_platforms.add(platform)
            if t.get("build_num") is not None and not str(t["build_num"]).isdigit():
                problems.append(f"target {t.get('name')!r} build_num {t.get('build_num')!r} is "
                                "not a plain integer string")

        if not self.whats_new:
            problems.append("no What's New copy — every locale would silently keep the previous "
                            "release's notes")
        for locale, text in self.whats_new.items():
            for glyph in FORBIDDEN_WHATS_NEW_GLYPHS:
                if glyph in text:
                    problems.append(f"What's New [{locale}] contains {glyph!r}, which App Store "
                                    "Connect rejects (docs/ASC_METADATA.md records it twice)")
            if len(text) > MAX_WHATS_NEW:
                problems.append(f"What's New [{locale}] is {len(text)} chars, over the "
                                f"{MAX_WHATS_NEW} limit")
            if not text.strip():
                problems.append(f"What's New [{locale}] is empty")

        if self.review_notes is None or not str(self.review_notes).strip():
            problems.append("review notes are empty — App Review reads them")
        elif len(self.review_notes) > MAX_REVIEW_NOTES:
            problems.append(f"review notes are {len(self.review_notes)} chars, over the "
                            f"{MAX_REVIEW_NOTES} limit")

        for locale, pair in self.description_edits.items():
            if not isinstance(pair, (tuple, list)) or len(pair) != 2:
                problems.append(f"description edit [{locale}] is not an (old, new) pair")
                continue
            old, new = pair
            if not old or not new:
                problems.append(f"description edit [{locale}] has an empty half")
                continue
            if old == new:
                problems.append(f"description edit [{locale}] replaces a sentence with itself")
            if old in new:
                # The already-applied branch is `new present once AND old absent`. An edit that
                # only appends leaves `old` inside `new`, so every later run reads the corrected
                # text as un-corrected and applies the replace again, growing the paragraph.
                problems.append(
                    f"description edit [{locale}]: the OLD sentence is a substring of the NEW "
                    "one, so the edit would re-apply on every run and the paragraph would grow. "
                    "Rewrite the pair so the corrected sentence does not contain the old one.")
            if locale not in self.whats_new:
                problems.append(f"description edit [{locale}] has no What's New for that locale "
                                "— set_whats_new would fail the run anyway")

        if self.iap is not None:
            for key in ("id", "product_id"):
                if not self.iap.get(key):
                    problems.append(f"iap is declared but missing {key!r}; both are needed "
                                    "because the numeric id is what the API takes and the "
                                    "product id is what a human can recognise")

        if problems:
            raise SystemExit("preflight FAILED, nothing was sent:\n" +
                             "\n".join(f"  - {p}" for p in problems))
        print(f"preflight: OK ({len(self.whats_new)} What's New locales, "
              f"{len(self.description_edits)} description edits, "
              f"iap={'none' if self.iap is None else self.iap['product_id']})")

    # --- the API -----------------------------------------------------------------------------

    def asc(self, method, ep, body=None, allow_empty=False):
        """One ASC call. An empty or non-JSON response is a FAILURE, not an empty success.

        Every submit script from 1.10 to 1.21 returned `{}` here when the helper exited non-zero
        — a missing key, a locked keychain, a network blip. `{}` has no "errors" key, and every
        call site reads a missing "errors" key as OK, so a run in which nothing at all reached
        Apple printed OK at every step. Raising here means a broken run stops at the first call
        instead of congratulating itself through twelve.
        """
        env = dict(os.environ)
        body_path = None
        try:
            if body is not None:
                # A fixed /tmp path (what the old scripts used) is shared by every concurrent run
                # and survives a crash, so a later run can send a body it did not write. One
                # private file per call, removed afterwards.
                fd, body_path = tempfile.mkstemp(prefix="asc_body_", suffix=".json")
                with os.fdopen(fd, "w") as handle:
                    json.dump(body, handle, ensure_ascii=False)
                env["ASC_BODY_FILE"] = body_path
            proc = subprocess.run([str(REPO / "scripts/asc_api.sh"), method, ep],
                                  capture_output=True, text=True, env=env, cwd=str(REPO))
        finally:
            if body_path:
                try:
                    os.unlink(body_path)
                except OSError:
                    pass
        out = proc.stdout
        if proc.returncode != 0:
            raise SystemExit(
                f"ASC call FAILED: {method} {ep}\n"
                f"  exit={proc.returncode}\n"
                f"  stdout={out.strip()[:400]!r}\n"
                f"  stderr={proc.stderr.strip()[:400]!r}\n"
                "Nothing was assumed to have succeeded. Fix the call and re-run; the script "
                "is idempotent up to this point.")
        if not out.strip():
            # Exactly TWO calls here answer with no body on success: the PATCH on a version's
            # build relationship, and the POST that submits the in-app purchase. Every other
            # endpoint returns a payload, so an empty body from any of them is a failure that
            # must not be read as an empty success. Emptiness is permitted per call site, never
            # globally.
            if allow_empty:
                return {}
            raise SystemExit(
                f"ASC returned an EMPTY body for {method} {ep}, which this call does not "
                "expect. Treating that as success is how a failed run reports OK twelve times.")
        try:
            return json.loads(out)
        except Exception:
            raise SystemExit(f"ASC returned non-JSON for {method} {ep}:\n{out[:400]}")

    @staticmethod
    def detail(response):
        """The whole of what ASC said went wrong, not just the headline.

        ASC's `detail` is a summary and its `meta.associatedErrors` is the evidence, and they can
        say very different things. On 2026-08-31 the headline was *"This in-app purchase cannot be
        reviewed, please check associated errors."* — which names no error and reads like a dead
        end — while the SAME response body carried
        `STATE_ERROR.FIRST_NON_CONSUMABLE_MUST_BE_SUBMITTED_ON_VERSION` and Apple's own sentence
        explaining the rule. Every submit script up to 1.29 prints `errors[0]['detail']` and
        discards the rest.
        """
        errors = response.get("errors") or []
        if not errors:
            return ""
        first = errors[0]
        parts = [str(first.get("detail") or first.get("title") or first.get("code"))]
        for _, associated in (first.get("meta", {}).get("associatedErrors") or {}).items():
            for a in associated:
                parts.append(f"[{a.get('code')}] {a.get('title') or a.get('detail')}")
        return " // ".join(parts)

    # --- versions ----------------------------------------------------------------------------

    def submittable(self, vid, name):
        """True only if this version can still accept a build and a submission.

        A version that is READY_FOR_SALE, IN_REVIEW or WAITING_FOR_REVIEW must not be touched.
        The v1.15 run learned this by creating an uncancellable, undeletable empty submission
        against an already-live macOS version.
        """
        d = self.asc("GET", f"/v1/appStoreVersions/{vid}")
        state = (d.get("data") or {}).get("attributes", {}).get("appStoreState")
        if state in SUBMITTABLE:
            return True
        if state in ALREADY_SUBMITTED:
            print(f"  {name}: version state is {state} — already submitted or live, nothing to do")
            return False
        self.fail(f"{name}: unrecognised version state {state!r} — refusing to guess")
        return False

    def find_version(self, platform):
        d = self.asc("GET", f"/v1/apps/{self.app}/appStoreVersions?filter[platform]={platform}"
                            f"&filter[versionString]={self.version}&limit=1")
        data = d.get("data") or []
        return data[0]["id"] if data else None

    def ensure_version(self, platform):
        vid = self.find_version(platform)
        if vid:
            print(f"  version {self.version} exists: {vid}")
            return vid
        r = self.asc("POST", "/v1/appStoreVersions", {"data": {
            "type": "appStoreVersions",
            "attributes": {"platform": platform, "versionString": self.version},
            "relationships": {"app": {"data": {"type": "apps", "id": self.app}}}}})
        if r.get("errors"):
            # Recorded, not exited: aborting mid-loop skips the OTHER platform and, in --submit,
            # skips the read-back entirely — so a platform that HAD submitted would go unverified.
            #
            # One case deserves more than Apple's sentence for it. After a withdrawal the previous
            # version sits in DEVELOPER_REJECTED and Apple refuses to create a second one, saying
            # only "You cannot create a new version of the App in the current state." That reads
            # like a permissions or timing problem and is neither: the rejected record IS the one
            # to use — DEVELOPER_REJECTED is already in SUBMITTABLE above — it just still carries
            # the OLD version string, so find_version does not recognise it.
            #
            # Not renamed automatically. Renaming a version record is how the marketing version
            # silently stops matching the uploaded build's CFBundleShortVersionString, and this
            # module should not do that on a guess. Measured 2026-09-07 while shipping macOS 1.31.
            blocked = self.detail(r)
            if "current state" in blocked:
                other = self.asc("GET", f"/v1/apps/{self.app}/appStoreVersions"
                                        f"?filter[platform]={platform}&limit=5"
                                        f"&fields[appStoreVersions]=versionString,appStoreState")
                for v in (other.get("data") or []):
                    a = v["attributes"]
                    if a["appStoreState"] in SUBMITTABLE and a["versionString"] != self.version:
                        blocked += (f" — version {a['versionString']} is {a['appStoreState']} and "
                                    f"is the record Apple wants reused. Point it at this release "
                                    f"by PATCHing its versionString to {self.version} (and make "
                                    f"sure the uploaded build's marketing version matches), then "
                                    f"run this again.")
                        break
            self.fail(f"create version {self.version}: {blocked}")
            return None
        vid = r["data"]["id"]
        print(f"  created version {self.version}: {vid}")
        return vid

    def localizations(self, vid):
        """{locale: id} for this version."""
        locs = self.asc("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations"
                               f"?fields[appStoreVersionLocalizations]=locale&limit=50"
                        ).get("data", [])
        return {l["attributes"]["locale"]: l["id"] for l in locs}

    def patch_localization(self, lid, locale, field, text):
        """PATCH one field and prove it landed, byte for byte.

        The response to a PATCH is not evidence that the text is what was sent — ASC silently
        truncates and normalises, and the star-glyph rejection lands here.
        """
        r = self.asc("PATCH", f"/v1/appStoreVersionLocalizations/{lid}", {"data": {
            "type": "appStoreVersionLocalizations", "id": lid, "attributes": {field: text}}})
        if r.get("errors"):
            self.fail(f"{field} {locale}: {self.detail(r)}")
            return
        check = self.asc("GET", f"/v1/appStoreVersionLocalizations/{lid}"
                                f"?fields[appStoreVersionLocalizations]={field}")
        stored = (check.get("data") or {}).get("attributes", {}).get(field)
        if stored != text:
            self.fail(f"{field} {locale}: stored text differs from what was sent "
                      f"({len(stored or '')} chars vs {len(text)})")
        else:
            print(f"    {field} {locale}: OK ({len(text)} chars, read back identical)")

    def set_whats_new(self, vid):
        by_locale = self.localizations(vid)
        # This loop asks "does every locale I WROTE have a destination". The other direction
        # matters more: a locale configured on the App Store that this script has no copy for is
        # never visited, so it silently ships the PREVIOUS version's What's New — claiming the
        # last release's changes as this one's.
        unwritten = sorted(set(by_locale) - set(self.whats_new))
        if unwritten:
            self.fail(f"App Store has locales this script writes no What's New for: {unwritten} "
                      f"— they would keep the previous version's copy")
        for locale, text in self.whats_new.items():
            lid = by_locale.get(locale)
            if not lid:
                self.fail(f"no localization for {locale} (have {list(by_locale)}) "
                          "— What's New unset")
                continue
            self.patch_localization(lid, locale, "whatsNew", text)

    def edited_description(self, current, locale):
        """Apply this locale's one-sentence edit, or explain why it cannot be applied.

        Returns (new_text, note). `new_text` is None when nothing should be written, and `note`
        says which of the three cases that is — the distinction the whole design turns on:

          * the old sentence is present exactly once             -> edit
          * the NEW sentence is already there and the old is not -> already done, write nothing
          * anything else                                        -> FAILURE, refuse to guess

        A count of 0 with the new sentence absent means the paragraph was rewritten somewhere
        else, and quietly doing nothing there is how a listing keeps a claim that stopped being
        true.
        """
        old, new = self.description_edits[locale]
        if current.count(new) == 1 and old not in current:
            return None, "already corrected in a previous run — read back and left alone"
        hits = current.count(old)
        if hits == 1:
            return current.replace(old, new), None
        if hits == 0:
            return None, ("FAIL: the sentence this edit expects is not in the live description, "
                          "and the corrected one is not there either. The paragraph was changed "
                          "elsewhere; re-read it and update DESCRIPTION_EDITS deliberately.")
        return None, (f"FAIL: the sentence this edit expects appears {hits} times; a replace "
                      "would touch more than the one line it was written for.")

    def set_descriptions(self, vid):
        """Correct one line per locale, surgically, and read the whole description back."""
        by_locale = self.localizations(vid)
        for locale in self.description_edits:
            lid = by_locale.get(locale)
            if not lid:
                self.fail(f"no localization for {locale} — description not corrected")
                continue
            cur = self.asc("GET", f"/v1/appStoreVersionLocalizations/{lid}"
                                  f"?fields[appStoreVersionLocalizations]=description")
            current = ((cur.get("data") or {}).get("attributes") or {}).get("description") or ""
            new_text, note = self.edited_description(current, locale)
            if new_text is None:
                if note and note.startswith("FAIL"):
                    self.fail(f"description {locale}: {note[6:]}")
                else:
                    print(f"    description {locale}: {note}")
                continue
            if len(new_text) > MAX_DESCRIPTION:
                self.fail(f"description {locale}: {len(new_text)} chars, over the "
                          f"{MAX_DESCRIPTION} limit")
                continue
            self.patch_localization(lid, locale, "description", new_text)
        untouched = sorted(set(by_locale) - set(self.description_edits))
        if untouched:
            # Not a failure. Said out loud because "we corrected the description" must never be
            # heard as "in every locale" — v1.30 deliberately left `ja` alone, because its
            # sentence was already true.
            print(f"    description: {untouched} deliberately not edited "
                  "(see DESCRIPTION_EDITS)")

    def set_review_detail(self, vid):
        cur = self.asc("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
        attrs = dict(self.contact)
        attrs["notes"] = self.review_notes
        attrs["demoAccountRequired"] = False
        existing = cur.get("data")
        if existing:
            rid = existing["id"]
            r = self.asc("PATCH", f"/v1/appStoreReviewDetails/{rid}",
                         {"data": {"type": "appStoreReviewDetails", "id": rid,
                                   "attributes": attrs}})
        else:
            r = self.asc("POST", "/v1/appStoreReviewDetails", {"data": {
                "type": "appStoreReviewDetails", "attributes": attrs,
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions",
                                                               "id": vid}}}}})
        if r.get("errors"):
            self.fail(f"review detail: {self.detail(r)}")
            return
        # Read back, for the same reason: App Review reads these notes, and a version that
        # reaches them with the PREVIOUS release's notes describes work that is not in this build.
        back = self.asc("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
        stored = ((back.get("data") or {}).get("attributes") or {}).get("notes")
        if stored != self.review_notes:
            self.fail(f"review detail: stored notes differ from what was sent "
                      f"({len(stored or '')} chars vs {len(self.review_notes)})")
        else:
            print(f"  review detail: OK ({len(self.review_notes)} chars, read back identical)")

    # --- builds ------------------------------------------------------------------------------

    def find_build(self, platform, num):
        """Match by build number AND platform — build numbers are per-platform, so mac 54 and
        iOS 54 can coexist; resolve each candidate's platform via its preReleaseVersion."""
        d = self.asc("GET", f"/v1/builds?filter[app]={self.app}&limit=50&sort=-uploadedDate"
                            f"&fields[builds]=version,processingState,usesNonExemptEncryption")
        for b in d.get("data", []):
            if b["attributes"]["version"] != num:
                continue
            bid = b["id"]
            pv = self.asc("GET", f"/v1/builds/{bid}/preReleaseVersion"
                                 f"?fields[preReleaseVersions]=platform")
            plat = (pv.get("data") or {}).get("attributes", {}).get("platform")
            if plat == platform:
                return bid, b["attributes"]
        return None, None

    # --- review submissions ------------------------------------------------------------------

    def open_submission(self, platform):
        """An existing un-submitted reviewSubmission for this platform, if any.

        Reuse a container rather than POSTing a second one. Orphans accumulate precisely because
        every failed run leaves one behind that no API call can remove.
        """
        d = self.asc("GET", f"/v1/apps/{self.app}/reviewSubmissions?filter[platform]={platform}"
                            f"&filter[state]=READY_FOR_REVIEW&limit=10")
        for s in (d.get("data") or []):
            return s["id"]
        return None

    def iap_is_in_a_live_submission(self):
        """Is the purchase actually inside a submission that is going to Apple?

        **This replaces reading the purchase's own state, which is not the same question and
        answers it wrongly at the one moment it matters.** `IAP_ALREADY_IN` contains `IN_REVIEW`,
        and Apple's cancel is asynchronous: for a window after a submission is withdrawn the
        purchase still reads `IN_REVIEW` while belonging to nothing. In that window the old
        expression concluded "carried", skipped staging, satisfied the phase-3 gate, and submitted
        a version whose release notes advertise a purchase that is in no review at all — printing
        OK and exiting 0.

        That is not hypothetical: it is the shape of the 2026-08-31 double-cancel, and this path
        is reached exactly when somebody withdraws a stuck submission to replace it, which is when
        the release is already under pressure.

        So this asks the containment question directly, over every non-terminal submission on
        every platform, and returns the submission id that holds the purchase (or None).
        """
        subs = self.asc("GET", f"/v1/apps/{self.app}/reviewSubmissions?limit=50"
                               f"&fields[reviewSubmissions]=state,platform")
        for sub in (subs.get("data") or []):
            if sub["attributes"]["state"] in ("COMPLETE", "CANCELING"):
                continue
            items = self.asc("GET", f"/v1/reviewSubmissions/{sub['id']}/items?limit=20"
                                    f"&include=inAppPurchaseVersion")
            for obj in (items.get("included") or []):
                if obj["type"] == "inAppPurchaseVersions":
                    return sub["id"]
        return None

    def add_item(self, sid, vid):
        return self.asc("POST", "/v1/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})

    # --- the in-app purchase -----------------------------------------------------------------

    def iap_state(self):
        d = self.asc("GET", f"/v2/inAppPurchases/{self.iap['id']}"
                            f"?fields[inAppPurchases]=state,productId,inAppPurchaseType,"
                            f"familySharable")
        return (d.get("data") or {}).get("attributes", {})

    def iap_version_id(self):
        """The reviewable unit of an in-app purchase, which is NOT the purchase itself.

        `reviewSubmissionItems` takes an `inAppPurchaseVersion` relationship pointing here.
        Asking it for an `inAppPurchase` or an `inAppPurchaseV2` gets `RELATIONSHIP.UNKNOWN`,
        which is what led the first version of v1.30's script to the wrong endpoint entirely.
        """
        d = self.asc("GET", f"/v2/inAppPurchases/{self.iap['id']}/versions?limit=10")
        versions = d.get("data") or []
        if len(versions) != 1:
            self.fail(f"expected exactly one inAppPurchaseVersion, found {len(versions)} — "
                      "refusing to guess which one App Review should see")
            return None
        return versions[0]["id"]

    def stage_iap(self, sid, name):
        """Put the purchase into an OPEN review submission. Returns True if it is in one.

        Apple requires an app's first non-consumable to be reviewed with a version, and this is
        the only way to express that: `POST /v1/inAppPurchaseSubmissions` refuses it with
        `FIRST_NON_CONSUMABLE_MUST_BE_SUBMITTED_ON_VERSION` regardless of when it is called.
        """
        attrs = self.iap_state()
        if attrs.get("productId") != self.iap["product_id"]:
            self.fail(f"IAP {self.iap['id']} has productId {attrs.get('productId')!r}, expected "
                      f"{self.iap['product_id']!r} — refusing to stage a product this script "
                      "cannot identify")
            return False
        state = attrs.get("state")
        if state in IAP_ALREADY_IN:
            # "Already in review" is only a reason to skip staging if it is IN something. After a
            # withdrawal the state lags the truth, and believing it here submits a version whose
            # notes advertise a purchase that no longer rides any submission.
            holder = self.iap_is_in_a_live_submission()
            if holder:
                print(f"  IAP is already {state} in submission {holder} — not staged again")
                return True
            self.fail(f"IAP reads {state!r} but is in NO live review submission. That is the "
                      "window right after a cancel, where Apple's state lags. Refusing to submit "
                      "a version whose notes describe a purchase nobody is reviewing — wait for "
                      "the state to settle to READY_TO_SUBMIT and run again.")
            return False
        if state not in IAP_READY:
            self.fail(f"IAP state is {state!r}, which is neither submittable nor already "
                      "submitted — refusing to guess (MISSING_METADATA means a required field "
                      "or the review screenshot is absent)")
            return False
        vid = self.iap_version_id()
        if not vid:
            return False
        r = self.asc("POST", "/v1/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
                "inAppPurchaseVersion": {"data": {"type": "inAppPurchaseVersions",
                                                  "id": vid}}}}})
        if r.get("errors"):
            # Not a failure by itself: one purchase can only be an item in ONE submission, so the
            # second platform is EXPECTED to be refused. The caller decides, because only it
            # knows whether the purchase is already carried somewhere.
            print(f"  IAP not staged on {name}: {self.detail(r)}")
            return False
        print(f"  IAP staged on {name} (item {r['data']['id'][:12]}…)")
        return True

    # --- the two phases a release actually runs -----------------------------------------------

    def do_metadata(self):
        for t in self.targets:
            print(f"\n===== {t['name']} metadata =====")
            vid = self.ensure_version(t["platform"])
            if not vid:
                continue
            self.set_whats_new(vid)
            self.set_descriptions(vid)
            self.set_review_detail(vid)

    def do_submit(self):
        """Attach, stage, then submit — and submit NOTHING unless the purchase is accounted for.

        The ordering is the safety property and it lives here rather than in a comment. The first
        run of v1.30's script had it in prose only: the purchase failed, the guard was not in the
        control flow, and both platforms went to Apple carrying release notes for a purchase
        nobody could make. Both submissions had to be cancelled and rebuilt.
        """
        # PHASE 1 — attach every build. The attach is the real gate; a submission container
        # created after a failed attach is exactly how the v1.15 orphan came to exist.
        attached = {}
        for t in self.targets:
            print(f"\n===== {t['name']} attach (build {t['build_num']}) =====")
            vid = self.find_version(t["platform"])
            if not vid:
                print(f"  !! no {self.version} version — run --metadata first")
                sys.exit(1)
            if not self.submittable(vid, t["name"]):
                continue
            bid, battr = self.find_build(t["platform"], t["build_num"])
            if not bid:
                print(f"  !! {t['name']} build {t['build_num']} not found")
                sys.exit(1)
            if battr.get("processingState") != "VALID":
                print(f"  !! build {t['build_num']} state={battr.get('processingState')} "
                      "(not VALID)")
                sys.exit(1)
            print(f"  build {bid} VALID")
            if battr.get("usesNonExemptEncryption") is None:
                self.asc("PATCH", f"/v1/builds/{bid}", {"data": {"type": "builds", "id": bid,
                         "attributes": {"usesNonExemptEncryption": False}}})
            r = self.asc("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build",
                         {"data": {"type": "builds", "id": bid}}, allow_empty=True)
            if r.get("errors"):
                self.fail(f"{t['name']}: attach build — {self.detail(r)}")
                continue
            print("  attach build: OK")
            attached[t["name"]] = vid

        # PHASE 2 — build the containers and their items, and submit NONE of them yet.
        #
        # A declared purchase goes into whichever container will take it: it is app-level under
        # Universal Purchase, so exactly one submission carries it and the other is refused.
        # `carried` is what phase 3 checks, and it is a fact read back from Apple rather than an
        # intention. With no purchase declared, nothing here touches the IAP endpoints at all.
        staged = {}
        # Read back WHERE the purchase is, not what its state string says. See
        # `iap_is_in_a_live_submission` for why those differ, and for the release this would
        # otherwise have shipped without its purchase.
        carried = False
        if self.iap is not None:
            holder = self.iap_is_in_a_live_submission()
            if holder:
                print(f"  purchase already carried by submission {holder}")
                carried = True
        for t in self.targets:
            vid = attached.get(t["name"])
            if not vid:
                continue
            print(f"\n===== {t['name']} stage =====")
            sid = self.open_submission(t["platform"])
            if sid:
                print(f"  reusing open submission {sid}")
            else:
                sub = self.asc("POST", "/v1/reviewSubmissions", {"data": {
                    "type": "reviewSubmissions",
                    "attributes": {"platform": t["platform"]},
                    "relationships": {"app": {"data": {"type": "apps", "id": self.app}}}}})
                if sub.get("errors"):
                    self.fail(f"{t['name']}: create submission — {self.detail(sub)}")
                    continue
                sid = sub["data"]["id"]
                print(f"  created submission {sid}")
            it = self.add_item(sid, vid)
            if it.get("errors"):
                self.fail(f"{t['name']}: no version item attached — {self.detail(it)}")
                continue
            print("  version item: OK")
            if self.iap is not None and not carried:
                carried = self.stage_iap(sid, t["name"])
            staged[t["name"]] = sid

        # PHASE 3 — the gate, in code. A version may go to Apple only once the purchase it
        # advertises is accounted for.
        if self.iap is not None and not carried:
            self.fail("the in-app purchase is in no review submission, so NOTHING was submitted "
                      "— the release notes describe a purchase that would not exist")
            return
        if len(staged) != len(attached):
            self.fail(f"only {sorted(staged)} could be staged out of {sorted(attached)} — "
                      "submitting a subset would split the release across two reviews")
            return

        for t in self.targets:
            sid = staged.get(t["name"])
            if not sid:
                continue
            print(f"\n===== {t['name']} submit =====")
            fin = self.asc("PATCH", f"/v1/reviewSubmissions/{sid}", {"data": {
                "type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}})
            if fin.get("errors"):
                self.fail(f"{t['name']}: submit — {self.detail(fin)}")
                continue
            print(f"  SUBMIT: OK ({fin['data']['attributes']['state']})")

        # --- read everything BACK ------------------------------------------------------------
        #
        # Every step above reports on the response to its own call. This asks Apple, afterwards,
        # what state things are in.
        print("\n===== reading back =====")
        for t in self.targets:
            vid = self.find_version(t["platform"])
            if not vid:
                self.fail(f"{t['name']}: version {self.version} is gone after submitting")
                continue
            d = self.asc("GET", f"/v1/appStoreVersions/{vid}")
            state = (d.get("data") or {}).get("attributes", {}).get("appStoreState")
            mark = "OK" if state in SUBMITTED_STATES else "NOT SUBMITTED"
            print(f"  {t['name']}: {state} [{mark}]")
            if state not in SUBMITTED_STATES:
                self.fail(f"{t['name']}: after submitting, state is {state!r}, not a submitted "
                          "state")
        if self.iap is not None:
            final_iap = self.iap_state().get("state")
            iap_ok = final_iap in IAP_ALREADY_IN
            print(f"  IAP {self.iap['product_id']}: {final_iap} "
                  f"[{'OK' if iap_ok else 'NOT SUBMITTED'}]")
            if not iap_ok:
                self.fail(f"the in-app purchase is {final_iap!r} after this run — the version "
                          "would ship release notes describing a purchase nobody can make")

    def do_dry_run(self):
        """Print the derived copy and the exact description diff WITHOUT touching Apple.

        The description half reads the LIVE text, because the whole point of a surgical edit is
        that the result depends on what is actually there — a dry run that showed a diff against
        a hardcoded "before" would be checking this file against itself.
        """
        print(f"VERSION {self.version}")
        for t in self.targets:
            print(f"  {t['name']:6s} platform={t['platform']:6s} build={t['build_num']}")
        if self.numbers:
            print("\nderived numbers:")
            for k, v in self.numbers.items():
                print(f"  {k:24s} {v}")
        for locale, text in self.whats_new.items():
            print(f"\n--- What's New [{locale}] ({len(text)} chars) ---\n{text}")
        print(f"\n--- Review notes ({len(self.review_notes)} chars) ---\n{self.review_notes}")

        print("\n--- description edits, against the LIVE text ---")
        if not self.description_edits:
            print("  (this release edits no description text)")
        for t in self.targets:
            vid = self.find_version(t["platform"])
            if not vid:
                # Expected before --metadata: this version does not exist yet, so compare against
                # what is live now, which is what it will inherit.
                d = self.asc("GET", f"/v1/apps/{self.app}/appStoreVersions"
                                    f"?filter[platform]={t['platform']}"
                                    f"&limit=1&fields[appStoreVersions]=versionString")
                data = d.get("data") or []
                if not data:
                    print(f"  {t['name']}: no version to read")
                    continue
                vid = data[0]["id"]
                print(f"  {t['name']}: {self.version} does not exist yet; reading "
                      f"{data[0]['attributes']['versionString']}, which it will inherit from")
            by_locale = self.localizations(vid)
            for locale in sorted(by_locale):
                lid = by_locale[locale]
                cur = self.asc("GET", f"/v1/appStoreVersionLocalizations/{lid}"
                                      f"?fields[appStoreVersionLocalizations]=description")
                current = ((cur.get("data") or {}).get("attributes") or {}).get("description") or ""
                if locale not in self.description_edits:
                    print(f"  {t['name']} {locale}: NOT EDITED by design ({len(current)} chars)")
                    continue
                new_text, note = self.edited_description(current, locale)
                if new_text is None:
                    print(f"  {t['name']} {locale}: {note}")
                    continue
                old, new = self.description_edits[locale]
                print(f"  {t['name']} {locale}: {len(current)} -> {len(new_text)} chars")
                print(f"      - {old}")
                print(f"      + {new}")


def main(release, argv=None, doc=None):
    """The three phases, and preflight before all of them.

    A release script's whole body is its config plus one call to this.
    """
    argv = list(sys.argv if argv is None else argv)
    mode = argv[1] if len(argv) > 1 else ""
    if mode not in ("--metadata", "--submit", "--dry-run"):
        print(doc or __doc__)
        sys.exit(2)
    release.preflight()
    if mode == "--metadata":
        release.do_metadata()
    elif mode == "--submit":
        release.do_submit()
    else:
        release.do_dry_run()
        sys.exit(0)
    sys.exit(release.report())
