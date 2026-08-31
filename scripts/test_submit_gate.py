#!/usr/bin/env python3
"""The one rule in `submit_1_30.py` that a mistake can only break once: no version reaches App
Review unless the in-app purchase it advertises is in a review submission.

WHY THIS FILE EXISTS. The rule was in the script from the start — as a sentence. `do_submit`'s
comment said the purchase "is submitted only if every attach succeeded", and then the loop that
submitted the versions did not look at whether it had. On 2026-08-31 the purchase failed with
`FIRST_NON_CONSUMABLE_MUST_BE_SUBMITTED_ON_VERSION` and both platforms went to Apple anyway,
carrying release notes describing a purchase nobody could make. Both submissions had to be
cancelled and rebuilt. **A guard in prose and no guard look identical from outside**, which is
this repo's oldest rule; a check run once by hand protects exactly one release, which is why it
is a file.

WHAT MAKES THIS A TEST AND NOT A DEMONSTRATION. It has a **paired control that must fire**. The
mutation half asserts zero submissions go out when the purchase cannot be staged — and that
assertion would also pass on a `do_submit` that submits nothing under any circumstances, or on a
harness whose stubs never reach the submit at all. The control half runs the identical fake with
one variable changed and requires exactly two submissions and no failures. Without it the
experiment proves nothing, which is the shape recorded in STATE under v1.26 §B and again under
`RideMoment.openedANewOffer`.

The fake App Store Connect is stateful: submitting a container advances the states of the items
in it, so the read-back at the end of `do_submit` is exercised too rather than stubbed into
always agreeing.

    python3 scripts/test_submit_gate.py        # exits non-zero if either half fails
"""
import contextlib
import importlib.util
import io
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "submit_1_30.py"


def load():
    spec = importlib.util.spec_from_file_location("submit_under_test", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run(module, iap_stageable):
    """Drive `do_submit` against a stateful fake, and report what actually reached the API."""
    state = {
        "ver": {"ver-MAC_OS": "PREPARE_FOR_SUBMISSION", "ver-IOS": "PREPARE_FOR_SUBMISSION"},
        "iap": "READY_TO_SUBMIT",
        "sub_items": {},
    }
    calls = []

    def fake(method, ep, body=None, allow_empty=False):
        calls.append((method, ep, body))
        if method == "GET" and "appStoreVersions?filter" in ep:
            return {"data": [{"id": "ver-MAC_OS" if "MAC_OS" in ep else "ver-IOS"}]}
        if method == "GET" and ep.startswith("/v1/appStoreVersions/ver-"):
            vid = ep.split("/")[3].split("?")[0]
            return {"data": {"attributes": {"appStoreState": state["ver"][vid]}}}
        if method == "GET" and ep.startswith("/v1/builds?"):
            return {"data": [
                {"id": "b54", "attributes": {"version": "54", "processingState": "VALID",
                                             "usesNonExemptEncryption": False}},
                {"id": "b55", "attributes": {"version": "55", "processingState": "VALID",
                                             "usesNonExemptEncryption": False}}]}
        if method == "GET" and "/preReleaseVersion" in ep:
            return {"data": {"attributes": {"platform": "MAC_OS" if "b54" in ep else "IOS"}}}
        if method == "PATCH" and ep.endswith("/relationships/build"):
            return {}
        if method == "GET" and "inAppPurchases" in ep and "/versions" in ep:
            return {"data": [{"id": "iapv-1"}]}
        if method == "GET" and ep.startswith("/v2/inAppPurchases/"):
            return {"data": {"attributes": {"state": state["iap"],
                                            "productId": module.IAP_PRODUCT_ID}}}
        if method == "GET" and "reviewSubmissions?" in ep:
            return {"data": []}
        if method == "POST" and ep == "/v1/reviewSubmissions":
            sid = "sub-" + body["data"]["attributes"]["platform"]
            state["sub_items"][sid] = []
            return {"data": {"id": sid}}
        if method == "POST" and ep == "/v1/reviewSubmissionItems":
            rels = body["data"]["relationships"]
            sid = rels["reviewSubmission"]["data"]["id"]
            if "inAppPurchaseVersion" in rels:
                if not iap_stageable:
                    return {"errors": [{"detail": "This resource cannot be reviewed."}]}
                state["sub_items"][sid].append("iap")
                return {"data": {"id": "item-iap"}}
            state["sub_items"][sid].append(rels["appStoreVersion"]["data"]["id"])
            return {"data": {"id": "item-ver"}}
        if method == "PATCH" and ep.startswith("/v1/reviewSubmissions/"):
            # Submitting a container is what advances everything inside it — so a version only
            # reads back as submitted if it was actually an item in something that was sent.
            for item in state["sub_items"].get(ep.rsplit("/", 1)[1], []):
                if item == "iap":
                    state["iap"] = "WAITING_FOR_REVIEW"
                else:
                    state["ver"][item] = "WAITING_FOR_REVIEW"
            return {"data": {"attributes": {"state": "WAITING_FOR_REVIEW"}}}
        raise AssertionError(f"the fake was asked something it does not stub: {method} {ep}")

    module.FAILURES.clear()
    module.asc = fake
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        module.do_submit()
    submits = [c for c in calls
               if c[0] == "PATCH" and c[1].startswith("/v1/reviewSubmissions/")
               and (c[2] or {}).get("data", {}).get("attributes", {}).get("submitted")]
    return len(submits), list(module.FAILURES), state, buf.getvalue()


def main():
    problems = []

    # --- the control, which must FIRE -------------------------------------------------------
    module = load()
    n, failures, state, out = run(module, iap_stageable=True)
    print(f"control  : submitted={n} iap={state['iap']} versions={sorted(state['ver'].values())}")
    if n != 2:
        problems.append(f"control submitted {n} times, not 2 — the harness never reaches the "
                        "submit, so the mutation below would prove nothing\n" + out)
    if failures:
        problems.append(f"control recorded failures on a clean run: {failures}")

    # --- the mutation ------------------------------------------------------------------------
    module = load()
    n, failures, state, out = run(module, iap_stageable=False)
    print(f"mutation : submitted={n} iap={state['iap']} versions={sorted(state['ver'].values())}")
    if n != 0:
        problems.append(f"THE GATE DID NOT HOLD: {n} review submissions were sent with the "
                        "in-app purchase in none of them\n" + out)
    if any(v != "PREPARE_FOR_SUBMISSION" for v in state["ver"].values()):
        problems.append(f"a version advanced anyway: {state['ver']}")
    if not failures:
        problems.append("the gate stopped the submit but recorded no failure — a run that did "
                        "nothing would exit 0, which is the defect this script's ledger exists for")

    if problems:
        print()
        for p in problems:
            print(f"FAIL  {p}")
        return 1
    print("\nboth halves fire: the control reaches the submit, the mutation is stopped by the gate.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
