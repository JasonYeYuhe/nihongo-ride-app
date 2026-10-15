#!/usr/bin/env bash
# Nihongo Ride — flags for local, non-release builds. Sourced, never run. Bash 3.2 (macOS /bin/bash).
#
#   . "$REPO/scripts/lib/build_env.sh"
#   swift test --scratch-path "$scratch" ${SWIFTPM_ARGS[@]+"${SWIFTPM_ARGS[@]}"}
#   xcodebuild test … ${XCODEBUILD_ARGS[@]+"${XCODEBUILD_ARGS[@]}"}
#
# (A bare "${a[@]}" of an EMPTY array is an unbound-variable error under bash 3.2's `set -u`; the `+`
# form expands to nothing instead.)
#
# WHAT IT SETS, AND WHY (measured 2026-10-15)
# -------------------------------------------
# SWIFTPM_ARGS=(--disable-index-store) and XCODEBUILD_ARGS=(COMPILER_INDEX_STORE_ENABLE=NO). The index
# store is for an IDE's jump-to-definition, and no IDE opens these build roots: nothing in this repo
# reads it. It was 55 MB (out/v5) of the main checkout's 605 MB SwiftPM root, every agent root wrote it
# again, and command-line xcodebuild writes one too (DerivedData/Index.noindex). ~/.claude/CLAUDE.md's
# "Build roots" rule 5 asks every agent and CLI build for the same flags.
#
# ONE SPELLING PER ROOT. The flag is part of every compile command, so a root built with it and then
# without it (or the reverse) should be expected to recompile every module — not measured here. A
# `swift test` run by hand or by a workflow into a root run_all_gates.sh also uses
# ("$(bash scripts/build_root.sh)/swiftpm") should source this file and pass the same array.
#
# EMPTY — the build runs exactly as it did before this file — when:
#   CI=true                 CI builds on a fresh runner; its command lines stay as they were.
#   NIHONGO_BUILD_ENV=off   the opt-out.
#
# WHO SOURCES IT: run_all_gates.sh (swift test), run_store_gates.sh and run_ios_placement_tests.sh
# (xcodebuild test). NOT the release path: build-appstore.sh and build-appstore-ios.sh archive exactly
# as before, and scripts/test_build_root.py fails if either starts sourcing this.
#
# WHAT IS DELIBERATELY NOT HERE
# -----------------------------
# * A shared Swift package checkout (-clonedSourcePackagesDirPath into one directory resolved once).
#   This project has no remote package: Package.swift declares no dependencies, project.yml's only
#   package is the repo itself (`path: .`), there is no Package.resolved to key one by, and the
#   SourcePackages of a NihongoRide DerivedData is 4 KB with an empty dependency list. If a remote
#   package is ever added, do not put its checkout directly under NihongoRide-build/ as
#   "SourcePackages-<8 hex>": that is the "<name>-<8 hex>" shape sweep_build_roots.py moves to the Trash
#   when no checkout maps to it.
# * A persistent DerivedData for the two xcodebuild gates. Each run builds a fresh copy of the tree in a
#   fresh directory on purpose: the copy because of com.apple.provenance and the nested Package.swift of
#   a leftover agent worktree, the fresh directory because clearing a fixed one raced an earlier run's
#   xcodebuild, which keeps writing for a while after it is signalled (run_store_gates.sh, "WHY THIS
#   COPIES THE TREE FIRST" and "A fresh directory per run"). The price, measured 2026-10-15 on a copy
#   made the same way: a cold macOS app build is 0.95 GB, 0.7 GB of it SDK module caches, written and
#   removed again on every run.
# * One SwiftPM root shared by several checkouts. build_root.sh gives each checkout its own, so two that
#   build at once never queue on one lock; a step that starts after its predecessor has returned can
#   reuse that root with NIHONGO_BUILD_ROOT.

SWIFTPM_ARGS=()
XCODEBUILD_ARGS=()
if [ "${CI:-}" != "true" ] && [ "${NIHONGO_BUILD_ENV:-}" != "off" ]; then
  SWIFTPM_ARGS=(--disable-index-store)
  XCODEBUILD_ARGS=(COMPILER_INDEX_STORE_ENABLE=NO)
fi
