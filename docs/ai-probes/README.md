# On-device model probes (2026-07-26)

The four programs behind §1 of `PLAN-V1.15-AI.md`. They exist so the plan's claims can be
re-checked rather than believed — the model ships with the OS and its behaviour will drift.

    xcrun swiftc -target arm64-apple-macos26.0 -parse-as-library probe2.swift -o /tmp/p2 && /tmp/p2

- `probe.swift`  — availability + a first Japanese sentence.
- `probe2.swift` — guided generation of japanese/kana/english for five target words.
                   **All five kana fields were defective.** This is the result the whole
                   design turns on: 落ち着いて came back as てきじゅうていて.
- `probe3.swift` — open-ended mistake analysis (EN and ZH) and a grounded word explanation.
                   Analysis was generic or wrong; the ZH session answered in English; the
                   grounded explanation was usable.
- `probe4.swift` — constrained classification into named patterns: 2 of 4 correct, and the
                   advice was nonsense even when the label was right.

Re-run them before extending any AI surface. If a future model authors correct kana for all
five words in `probe2`, the constraint in §2 of the plan can be revisited — but that has to
be MEASURED, not assumed, and the validation gates in §AI-3 stay regardless.
