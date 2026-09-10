import Testing
import Foundation
import CloudKit
import VocabKit
import WordListsKit
@testable import NihongoRideApp

/// Two rules the sync layer states in prose, turned into things that can fail (v1.32 §D1).
///
/// Both were guards nothing could assert. That is not a gap in coverage so much as a category
/// error: **a rule whose violation is invisible is a comment.** `STATE-2026-08-18.md` names it as
/// this project's cheapest detector — *where a comment states a contract, check whether anything
/// enforces it* — and §A of the v1.32 plan says the survey found the shape inside the repo's own
/// gates. These are two of them.
@MainActor
@Suite("The sync rules that nothing could assert")
struct LocalChangeSeamTests {

    // MARK: A failed save must not be queued for CloudKit

    /// A recorder standing in for the sync controller.
    ///
    /// `syncController` is nil in every `swift test` process — `CloudKitSyncController.init?`
    /// requires a bundle identifier and SwiftPM's swift-testing entry point reports none — so
    /// before the seam, `announceLocalChange`'s effect was unobservable and deleting the guard
    /// left the whole suite green.
    final class Recorder: @unchecked Sendable {
        private(set) var announced: [AppModel.LocalChange] = []
        func record(_ change: AppModel.LocalChange) { announced.append(change) }
    }

    /// The paired control and the experiment differ in ONE thing: whether the file can be
    /// written. Without the control arm, "the recorder is empty" is equally consistent with a
    /// seam that is never called at all, a list mutation that was refused for some other reason,
    /// or a recorder that was never installed.
    @Test("a word-list save that fails must not queue the change for CloudKit")
    func aFailedSaveAnnouncesNothing() throws {
        // Control: the save succeeds, so the change IS announced.
        let good = AppModelTests.makeModel(vocab: VocabStore(entries: [AppModelTests.entry("a", "赤", "あか")]))
        let goodRecorder = Recorder()
        good.announceLocalChange = { goodRecorder.record($0) }
        _ = good.addWord("a", to: WordList.defaultID)
        #expect(good.lastPersistError == nil, "the control's save must succeed")
        #expect(goodRecorder.announced == [AppModel.LocalChange(listIDs: [WordList.defaultID])],
                "the control must announce, or the experiment below proves nothing")

        // Experiment: same model shape, but the destination is now a DIRECTORY, so the write
        // throws. Created AFTER the model is built on purpose — do it before, and the file is
        // unreadable at launch, `wordListsReadOnly` is true, and the OTHER guard fires. The two
        // failures print the same empty recorder and are not the same fact.
        let bad = AppModelTests.makeModel(vocab: VocabStore(entries: [AppModelTests.entry("a", "赤", "あか")]))
        let badRecorder = Recorder()
        bad.announceLocalChange = { badRecorder.record($0) }
        // `AppModel.init` has already written the file, so replace it with a directory of the
        // same name — that is what makes `save` throw.
        let destination = AppModel.supportFileURL("word-lists.json")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory)
                && isDirectory.boolValue,
                "the arrangement itself is a claim: the destination must BE a directory")

        _ = bad.addWord("a", to: WordList.defaultID)
        #expect(bad.lastPersistError == .saveFailed,
                "the write must have FAILED — got \(String(describing: bad.lastPersistError))")
        #expect(badRecorder.announced.isEmpty,
                "a change that never reached disk was queued for upload: \(badRecorder.announced)")
    }

    /// The seam is only a guarantee if it is the ONLY door.
    ///
    /// This is the `EntitlementSeamTests` shape: read the shipped source, and fail if a second
    /// route to `recordLocalChanges` exists. A behavioural test cannot see a call site that was
    /// added afterwards; a source scan can. The floor matters as much as the rule — a scan that
    /// read nothing would report clean, which is how three checkers in this repo's history
    /// produced a null result from a broken instrument.
    @Test("recordLocalChanges is reachable only through announceLocalChange's default")
    func theSeamIsTheOnlyDoor() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let appDirectory = root.appendingPathComponent("Sources/NihongoRideApp")
        let files = try FileManager.default.contentsOfDirectory(atPath: appDirectory.path)
            .filter { $0.hasSuffix(".swift") }
        #expect(files.count >= 5, "only \(files.count) files — the scan is misdirected")

        var callSites: [String] = []
        var announceSites = 0
        for file in files where file != "CloudKitSyncController.swift" {
            let source = try String(contentsOf: appDirectory.appendingPathComponent(file),
                                    encoding: .utf8)
            for (index, line) in source.components(separatedBy: "\n").enumerated() {
                if line.contains("announceLocalChange(") { announceSites += 1 }
                guard line.contains("recordLocalChanges(") else { continue }
                // The default closure's body is the one legitimate call.
                let isTheDefault = line.contains("self?.syncController?.recordLocalChanges(")
                if !isTheDefault { callSites.append("\(file):\(index + 1) \(line.trimmingCharacters(in: .whitespaces))") }
            }
        }
        #expect(announceSites >= 4,
                "only \(announceSites) call(s) go through the door — the scan found too few to be reading the right file")
        #expect(callSites.isEmpty,
                "\(callSites.count) call(s) bypass announceLocalChange: \(callSites)")
    }

    // MARK: A sync failure never reads as "Off"

    /// `PLAN-V1.32` §C2 closes on the claim that a shipped app can never show the iCloud toggle
    /// ON above the word "Off". The load-bearing half of that argument is that `status(for:)`
    /// cannot return `.off` — which was true, and which nothing checked. Now it does.
    ///
    /// The enumeration is over `CKError.Code.allCases`… which does not exist, so it is over an
    /// explicit list, and the list's own completeness is the thing to be honest about: it is the
    /// codes this app can plausibly meet plus a non-CloudKit error. What falls outside it is any
    /// code Apple adds later — which `status(for:)` routes through its `default` to `.error(…)`,
    /// the same branch the unlisted codes here already exercise.
    @Test("no sync failure renders as \"Off\" — the state that would contradict the toggle")
    func statusNeverReportsOff() {
        func ck(_ code: CKError.Code) -> CKError {
            CKError(_nsError: NSError(domain: CKErrorDomain, code: code.rawValue))
        }
        let codes: [CKError.Code] = [
            .notAuthenticated, .networkUnavailable, .networkFailure, .serviceUnavailable,
            .requestRateLimited, .zoneBusy, .permissionFailure, .quotaExceeded,
            .managedAccountRestricted, .badContainer, .missingEntitlement, .internalError,
            .partialFailure, .unknownItem, .zoneNotFound, .userDeletedZone, .changeTokenExpired,
        ]
        for code in codes {
            let status = CloudKitSyncController.status(for: ck(code))
            #expect(status != .off, "\(code) rendered as Off, which contradicts an ON toggle")
        }
        // A non-CloudKit error takes the same route.
        #expect(CloudKitSyncController.status(for: CocoaError(.fileNoSuchFile)) != .off)

        // The control: this test would pass for a `status(for:)` that returned one constant, so
        // pin that it actually DISCRIMINATES — the three outcomes the close names.
        #expect(CloudKitSyncController.status(for: ck(.notAuthenticated)) == .noAccount)
        #expect(CloudKitSyncController.status(for: ck(.networkUnavailable)) == .waiting)
        if case .error = CloudKitSyncController.status(for: ck(.internalError)) {} else {
            Issue.record("an unclassified CKError must surface as .error, not be swallowed")
        }
    }
}
