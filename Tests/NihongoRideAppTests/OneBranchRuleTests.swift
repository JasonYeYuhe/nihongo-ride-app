import Testing
import Foundation

// MARK: - Three "do not refactor this" rules that nothing enforced
//
// Three shipped types say, in a doc comment, that a decision and its side effect must stay on one
// line of control flow:
//
// * `EntitlementLedger.apply(_:savingTo:key:)` — "Do not refactor this into an `apply` that
//   returns and a caller that saves."
// * `UnlockOfferLedger.purchasing(lifetimeMetres:isolation:buy:)` — "Do not refactor this into a
//   call that returns and a caller that records."
// * `ReviewPromptLedger.requestIfEarned(...)` — "Do not refactor this into a `decide()` that
//   returns and a caller that acts."
//
// Each type's behavioural tests prove the method keeps its promise. None of them can see the
// refactor the comment forbids, because that refactor keeps the method and moves the work to a
// CALL SITE — and a call site added afterwards is invisible to a test of the method. A comment
// that nothing enforces is the defect shape this project keeps finding, so these read the shipped
// source and fail on the forbidden shapes.
//
// All three rules run through ONE scanner (`CallSiteScanner`, in CallSiteScanner.swift), and every
// planted-sample control runs through the same rule functions the real assertions use —
// `EntitlementSeamTests` records what happened when a control certified a parser that was not the
// one doing the work.
//
// This lives in `NihongoRideAppTests` because the call sites are the app's. Reading files by
// `#filePath` imports nothing, so no target dependency was added.
//
// ## What these scans cannot see — stated so nobody reads green as more than it is
//
// * Types are not resolved. A receiver counts as an entitlement ledger or record only when its
//   name is DECLARED as one in the same file (`var ledger: EntitlementLedger`, `var r =
//   ledger.record`, …), or it is reached through another object (`entitlements.ledger`). A copy
//   bound with an inferred type from a function's return value is not recognised.
// * Calls are found by NAME. A call written with a space before its parenthesis (`foo (x)`), a
//   trailing closure that starts on the next line, or a regex literal containing braces is misread;
//   both sides of a `#if` are scanned as plain text.
// * "Inside the closure handed to X" treats the `{` after a call as a trailing closure unless an
//   `if`/`guard`/`while`/`switch` opens EARLIER ON THE SAME LINE. A condition that wraps before
//   the call (`if a,\n b.purchasing(...) {`) would have its body mistaken for a closure.
// * The review request is found as a call named `requestReview`. Renaming the environment value
//   would hide it — today that drops `reviewRequests` to zero and trips its floor, but only because
//   there is exactly one such call.
// * Only `Sources/` is scanned. Tests may call `decide()` and the record-level `apply` freely —
//   that is what those APIs are public for.

// MARK: - The three rules

/// Each rule is a pure function of a set of files, so the real sources and the planted samples go
/// through exactly the same code.
enum OneBranchRules {
    typealias File = CallSiteScanner.File

    struct Report {
        var violations: [String] = []
        var counts: [String: Int] = [:]
    }

    // MARK: 1. EntitlementLedger.apply mutates and saves in one branch

    static func entitlementApply(_ files: [File]) -> Report {
        var report = Report()

        // The home: the one `apply` whose parameters include `savingTo`.
        var homes: [(file: File, declaration: CallSiteScanner.Declaration)] = []
        for file in files {
            for declaration in file.functions(named: "apply")
            where declaration.body != nil && declaration.parameters.map({ file.text($0).contains("savingTo") }) == true {
                homes.append((file, declaration))
            }
        }
        report.counts["homes"] = homes.count
        if homes.count != 1 {
            report.violations.append("expected exactly ONE apply(_:savingTo:) with a body, found \(homes.count) — the rule's home moved or was duplicated")
        }
        let home = homes.first
        let homePath = home?.file.path
        func isInHome(_ file: File, _ offset: Int) -> Bool {
            guard let home, let body = home.declaration.body else { return false }
            return file.path == home.file.path && body.contains(offset)
        }
        func isSaveTo(_ file: File, _ call: CallSiteScanner.Call) -> Bool {
            call.arguments.map { file.text($0).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("to:") } ?? false
        }

        if let home, let body = home.declaration.body {
            let file = home.file
            let mutations = file.calls(named: "apply").filter {
                body.contains($0.nameOffset) && !($0.arguments.map { file.text($0).contains("savingTo:") } ?? false)
            }
            let saves = file.calls(named: "save").filter { body.contains($0.nameOffset) && isSaveTo(file, $0) }
            if mutations.isEmpty {
                report.violations.append("\(file.location(body.lowerBound)) apply(_:savingTo:) no longer applies the signal to the record itself")
            }
            if saves.isEmpty {
                report.violations.append("\(file.location(body.lowerBound)) apply(_:savingTo:) no longer saves — an apply that returns leaves the save to a caller")
            }
            if let mutation = mutations.first, let save = saves.first, save.nameOffset < mutation.nameOffset {
                report.violations.append("\(file.location(save.nameOffset)) apply(_:savingTo:) saves before it mutates")
            }
        }

        // Names this code base binds to a ledger or to a record. Per file, because a bare `ledger`
        // in one file (AppModel's copy of the UNLOCK-OFFER ledger) is not the entitlement ledger
        // in another.
        let ledgerPatterns = [
            #"\b(?:var|let)\s+(\w+)\s*:\s*EntitlementLedger\b"#,
            #"\b(?:var|let)\s+(\w+)\s*=\s*EntitlementLedger\s*[.(]"#,
        ]
        let recordPatterns = [
            #"\b(?:var|let)\s+(\w+)\s*:\s*EntitlementRecord\b"#,
            #"\b(?:var|let)\s+(\w+)\s*=\s*EntitlementRecord\s*[.(]"#,
            #"\b(?:var|let)\s+(\w+)\s*=\s*[\w.?!]*\.record\b"#,
        ]
        var ledgerNames: [String: Set<String>] = [:]
        var recordNames: [String: Set<String>] = [:]
        for file in files {
            let text = file.allCode
            ledgerNames[file.path] = ledgerPatterns.reduce(into: Set<String>()) { $0.formUnion(CallSiteScanner.captures($1, in: text)) }
            recordNames[file.path] = recordPatterns.reduce(into: Set<String>()) { $0.formUnion(CallSiteScanner.captures($1, in: text)) }
        }
        let allLedgerNames = ledgerNames.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        let allRecordNames = recordNames.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        report.counts["ledgerNames"] = allLedgerNames.count

        /// A bare name resolves only in its own file; a chain (`entitlements.ledger`) resolves
        /// against every file, because it reached the object through another type.
        func resolves(_ receiver: String, in file: File, local: [String: Set<String>], global: Set<String>) -> Bool {
            let parts = CallSiteScanner.receiverComponents(receiver)
            guard let last = parts.last else { return false }
            return parts.count == 1 ? (local[file.path]?.contains(last) ?? false) : global.contains(last)
        }

        var ledgerLevelCalls = 0
        for file in files {
            // (a) the RECORD mutated outside the home.
            for call in file.calls(named: "apply") {
                let arguments = call.arguments.map(file.text) ?? ""
                if arguments.contains("savingTo:") {
                    if !isInHome(file, call.nameOffset) { ledgerLevelCalls += 1 }
                    continue
                }
                guard !isInHome(file, call.nameOffset) else { continue }
                let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
                let signal = [".entitled(", ".revoked(", ".silent", "StoreEntitlementSignal."].contains { trimmed.hasPrefix($0) }
                    || arguments.contains("readStore(")
                let parts = CallSiteScanner.receiverComponents(call.receiver)
                let onRecord = parts.last == "record"
                    || resolves(call.receiver, in: file, local: recordNames, global: allRecordNames)
                if signal || onRecord {
                    report.violations.append("\(file.location(call.nameOffset)) mutates the entitlement record without saving it in the same call: \(file.excerpt(call))")
                }
            }
            // (b) the ledger or record SAVED outside the home.
            for call in file.calls(named: "save") where isSaveTo(file, call) {
                guard !isInHome(file, call.nameOffset) else { continue }
                let onLedger = resolves(call.receiver, in: file, local: ledgerNames, global: allLedgerNames)
                    || resolves(call.receiver, in: file, local: recordNames, global: allRecordNames)
                    || CallSiteScanner.receiverComponents(call.receiver).last == "record"
                let implicitInsideLedger = call.receiver.isEmpty && !call.dotPrefixed
                    && (file.typeBodies(named: "EntitlementLedger") + file.typeBodies(named: "EntitlementRecord"))
                        .contains { $0.contains(call.nameOffset) }
                if onLedger || implicitInsideLedger {
                    report.violations.append("\(file.location(call.nameOffset)) saves the entitlement record apart from the apply that changed it: \(file.excerpt(call))")
                }
            }
            // (c) the record's storage written around save(to:) altogether.
            if file.path != homePath {
                if file.allCodeWithStrings.contains("NihongoRide.entitlement.v1")
                    || !file.mentions(of: "EntitlementLedger").filter({ offset in
                        file.text(offset..<min(file.code.count, offset + 30)).hasPrefix("EntitlementLedger.defaultsKey")
                    }).isEmpty {
                    report.violations.append("\(file.path) names the entitlement record's defaults key — a second writer of the record is a caller that saves")
                }
            }
        }
        report.counts["ledgerLevelCalls"] = ledgerLevelCalls
        return report
    }

    // MARK: 2. UnlockOfferLedger.purchasing records inside, not at the call site

    static func purchasing(_ files: [File]) -> Report {
        var report = Report()

        var homes: [(file: File, declaration: CallSiteScanner.Declaration)] = []
        for file in files {
            for declaration in file.functions(named: "purchasing") where declaration.body != nil {
                homes.append((file, declaration))
            }
        }
        report.counts["homes"] = homes.count
        if homes.count != 1 {
            report.violations.append("expected exactly ONE func purchasing with a body, found \(homes.count)")
        }
        let homePath = homes.first?.file.path

        if let (file, declaration) = homes.first, let body = declaration.body {
            let records = file.calls(named: "record").filter { body.contains($0.nameOffset) && $0.receiver.isEmpty && !$0.dotPrefixed }
            let started = records.first { $0.arguments.map { file.text($0).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(".purchaseStarted") } ?? false }
            let buys = file.calls(named: "buy").filter { body.contains($0.nameOffset) }
            if started == nil {
                report.violations.append("\(file.location(body.lowerBound)) purchasing no longer records .purchaseStarted itself")
            }
            if buys.isEmpty {
                report.violations.append("\(file.location(body.lowerBound)) purchasing no longer calls buy() — the purchase happens somewhere else")
            }
            if let started, let buy = buys.first {
                if buy.nameOffset < started.nameOffset {
                    report.violations.append("\(file.location(buy.nameOffset)) purchasing buys before it records the attempt")
                }
                if !records.contains(where: { $0.nameOffset > buy.nameOffset }) {
                    report.violations.append("\(file.location(buy.nameOffset)) purchasing no longer records the outcome after buy() — a call that returns leaves the recording to a caller")
                }
            }
        }

        for file in files {
            // The primitive recorder stays private, and no other mutating entry of the ledger
            // accepts an outcome from its caller.
            for typeBody in file.typeBodies(named: "UnlockOfferLedger") {
                for declaration in file.functions where typeBody.contains(declaration.keywordOffset) {
                    let parameters = declaration.parameters.map(file.text) ?? ""
                    if declaration.name == "record" {
                        if !(declaration.modifiers.contains("private")) {
                            report.violations.append("\(file.location(declaration.keywordOffset)) UnlockOfferLedger.record is no longer private — a caller can record an outcome itself")
                        }
                        continue
                    }
                    if declaration.modifiers.contains("mutating"),
                       parameters.range(of: #":\s*UnlockOfferEvent\b"#, options: .regularExpression) != nil {
                        report.violations.append("\(file.location(declaration.keywordOffset)) UnlockOfferLedger.\(declaration.name) records an event its caller hands it — that is recording at the call site")
                    }
                }
            }
        }

        // The adapter: the one file that declares the StoreKit answer.
        let adapters = files.filter { $0.allCode.range(of: #"\bvar\s+lastOutcome\b"#, options: .regularExpression) != nil }
        report.counts["adapters"] = adapters.count
        if adapters.count != 1 {
            report.violations.append("expected exactly ONE declaration of lastOutcome, found \(adapters.count) — the scan cannot tell the adapter from a caller")
        }
        let adapterPath = adapters.first?.path

        var callSites = 0
        var answerReads = 0
        for file in files {
            for call in file.calls(named: "purchasing") {
                callSites += 1
                let buysInside = file.calls(named: "purchase").contains { purchase in
                    call.closures.contains { $0.contains(purchase.nameOffset) }
                }
                if !buysInside {
                    report.violations.append("\(file.location(call.nameOffset)) purchasing is handed a closure that does not purchase — the purchase and its record have come apart: \(file.excerpt(call))")
                }
            }
            for purchase in file.calls(named: "purchase") {
                let isTheStoreKitCall = file.path == adapterPath
                    && file.enclosingFunction(of: purchase.nameOffset)?.name == "purchase"
                if !isTheStoreKitCall, !file.isInsideClosure(handedTo: ["purchasing"], purchase.nameOffset) {
                    report.violations.append("\(file.location(purchase.nameOffset)) purchases outside the closure handed to purchasing: \(file.excerpt(purchase))")
                }
            }
            if file.path != adapterPath {
                for offset in file.mentions(of: "lastOutcome") {
                    answerReads += 1
                    if !file.isInsideClosure(handedTo: ["purchasing"], offset) {
                        report.violations.append("\(file.location(offset)) reads StoreKit's answer outside the closure handed to purchasing — the outcome is being handled at the call site")
                    }
                }
            }
            if file.path != homePath {
                for offset in file.mentions(of: "purchaseStarted") where offset > 0 && file.code[offset - 1] == UInt8(ascii: ".") {
                    let context = file.text(max(0, offset - 40)..<offset)
                    if context.contains("count(of:") { continue }   // a READ of the count is not a record
                    report.violations.append("\(file.location(offset)) names .purchaseStarted outside the ledger — only purchasing may record the attempt")
                }
            }
        }
        report.counts["callSites"] = callSites
        report.counts["answerReads"] = answerReads
        return report
    }

    // MARK: 3. ReviewPromptLedger.requestIfEarned decides and acts together

    static func reviewPrompt(_ files: [File]) -> Report {
        var report = Report()

        var homes: [(file: File, declaration: CallSiteScanner.Declaration)] = []
        for file in files {
            for declaration in file.functions(named: "requestIfEarned") where declaration.body != nil {
                homes.append((file, declaration))
            }
        }
        report.counts["homes"] = homes.count
        if homes.count != 1 {
            report.violations.append("expected exactly ONE func requestIfEarned with a body, found \(homes.count)")
        }
        let home = homes.first
        func isInHome(_ file: File, _ offset: Int) -> Bool {
            guard let home, let body = home.declaration.body else { return false }
            return file.path == home.file.path && body.contains(offset)
        }

        if let (file, declaration) = home, let body = declaration.body {
            let decides = file.calls(named: "decide").filter { body.contains($0.nameOffset) }
            let asks = file.calls(named: "ask").filter { body.contains($0.nameOffset) && $0.receiver.isEmpty && !$0.dotPrefixed }
            let appends = file.calls(named: "append").filter {
                body.contains($0.nameOffset) && CallSiteScanner.receiverComponents($0.receiver).last == "requestDates"
            }
            if decides.isEmpty {
                report.violations.append("\(file.location(body.lowerBound)) requestIfEarned no longer decides — the decision is being made somewhere else")
            }
            if asks.isEmpty {
                report.violations.append("\(file.location(body.lowerBound)) requestIfEarned no longer calls ask() — the act is being done somewhere else")
            }
            if appends.isEmpty {
                report.violations.append("\(file.location(body.lowerBound)) requestIfEarned no longer records the request")
            }
            if let ask = asks.first, let append = appends.first {
                let askBlock = file.innermostBlock(containing: ask.nameOffset, within: body)
                let appendBlock = file.innermostBlock(containing: append.nameOffset, within: body)
                if askBlock != appendBlock || askBlock == body {
                    report.violations.append("\(file.location(ask.nameOffset)) ask() and requestDates.append are no longer in the same conditional block — the request and its record can come apart")
                }
            }
        }

        var wrappers: Set<String> = []
        var callSites = 0
        for file in files {
            for call in file.calls(named: "decide") {
                guard let arguments = call.arguments, file.text(arguments).contains("moment:") else { continue }
                if !isInHome(file, call.nameOffset) {
                    report.violations.append("\(file.location(call.nameOffset)) calls decide() outside requestIfEarned — a decision returned to a caller that acts: \(file.excerpt(call))")
                }
            }
            for call in file.calls(named: "requestIfEarned") {
                guard !isInHome(file, call.nameOffset) else { continue }
                callSites += 1
                guard let function = file.enclosingFunction(of: call.nameOffset), let body = function.body else { continue }
                wrappers.insert(function.name)
                for ask in file.calls(named: "ask") where body.contains(ask.nameOffset) && ask.receiver.isEmpty && !ask.dotPrefixed {
                    if !call.extent.contains(ask.nameOffset) {
                        report.violations.append("\(file.location(ask.nameOffset)) \(function.name) calls ask() itself around requestIfEarned — the caller is acting on the decision")
                    }
                }
            }
        }
        report.counts["callSites"] = callSites
        report.counts["wrappers"] = wrappers.count

        var requests = 0
        let handedTo = wrappers.union(["requestIfEarned"])
        for file in files {
            for call in file.calls(named: "requestReview") {
                requests += 1
                if !file.isInsideClosure(handedTo: handedTo, call.nameOffset) {
                    report.violations.append("\(file.location(call.nameOffset)) requests a review outside a closure handed to \(handedTo.sorted()) — asking without the ledger recording it: \(file.excerpt(call))")
                }
            }
        }
        report.counts["reviewRequests"] = requests
        return report
    }
}

// MARK: - Planted samples
//
// Raw strings, so `\(` and `\.` are the scanner's to read, not the compiler's. Each rule has
// today's shape (must pass) and the forbidden shapes (each must fail) — one alone proves less
// than it looks: "the scan reports a violation" is satisfied by a scan that always does.

enum OneBranchSamples {
    typealias File = CallSiteScanner.File

    // 1. Entitlement

    static let entitlementHome = File(path: "Sources/EntitlementKit/Entitlement.swift", source: #"""
        public struct EntitlementRecord {
            public mutating func apply(_ signal: StoreEntitlementSignal) -> Bool { true }
        }
        public struct EntitlementLedger {
            public static let defaultsKey = "NihongoRide.entitlement.v1"
            public private(set) var record: EntitlementRecord
            /// Do not refactor this into an `apply` that returns and a caller that saves: record.apply(signal)
            @discardableResult
            public mutating func apply(_ signal: StoreEntitlementSignal,
                                       savingTo defaults: UserDefaults?,
                                       key: String = defaultsKey) -> Bool {
                let changed = record.apply(signal)
                if changed, let defaults { save(to: defaults, key: key) }
                return changed
            }
            public func save(to defaults: UserDefaults, key: String = defaultsKey) {
                guard let data = try? JSONEncoder().encode(record) else { return }
                defaults.set(data, forKey: key)
            }
        }
        """#)

    static let entitlementAdapterToday = File(path: "Sources/NihongoRideApp/RouteStore.swift", source: #"""
        final class RouteStore {
            private(set) var ledger: EntitlementLedger
            init(defaults: UserDefaults?) {
                self.ledger = EntitlementLedger(productID: "x")
                let note = "ledger.save(to: defaults) is not code"
                ledger.apply(.revoked(id: 1, at: Date()), savingTo: nil)
            }
            func refresh() async {
                // ledger.save(to: defaults) — a comment, not a call
                ledger.apply(await Self.readStore(ledgerRevokedAt: ledger.record.revokedAt), savingTo: defaults)
            }
            func purchase() async {
                ledger.apply(.entitled(id: transaction.originalID, at: Date()),
                             savingTo: defaults)
            }
        }
        """#)

    /// Not an entitlement file at all, and full of look-alikes: a local named `ledger` holding
    /// the unlock-offer ledger, other stores' `save(to:)`, and another type's `apply`.
    static let appModelLookAlikes = File(path: "Sources/NihongoRideApp/AppModel.swift", source: #"""
        final class AppModel {
            func buy() async {
                var ledger = unlockOfferLedger
                ledger.save(to: Self.settingsStore)
                unlockOfferLedger.save(to: Self.settingsStore)
                settings.save(to: Self.settingsStore)
                let scheduled = await ReminderScheduler.apply(enabled: true, store: reviewStore)
            }
        }
        """#)

    /// The refactor the comment forbids, done the way the current API allows it.
    static let entitlementSplitInAdapter = File(path: "Sources/NihongoRideApp/RouteStore.swift", source: #"""
        final class RouteStore {
            private(set) var ledger: EntitlementLedger
            func refresh() async {
                var record = ledger.record
                if record.apply(await Self.readStore(ledgerRevokedAt: ledger.record.revokedAt)) {
                    ledger = EntitlementLedger(record: record)
                    if let defaults { ledger.save(to: defaults) }
                }
            }
        }
        """#)

    /// A differently named copy, mutated in one file and saved through another object.
    static let entitlementSplitElsewhere = File(path: "Sources/NihongoRideApp/AppModel.swift", source: #"""
        final class AppModel {
            func reconcile() {
                var copy = entitlements.ledger.record
                _ = copy.apply(.revoked(id: 1, at: Date()))
                entitlements.ledger.save(to: Self.settingsStore)
                UserDefaults.standard.set(nil, forKey: EntitlementLedger.defaultsKey)
            }
        }
        """#)

    /// The home itself turned into "an apply that returns".
    static let entitlementHomeThatReturns = File(path: "Sources/EntitlementKit/Entitlement.swift", source: #"""
        public struct EntitlementLedger {
            public private(set) var record: EntitlementRecord
            public mutating func apply(_ signal: StoreEntitlementSignal, savingTo defaults: UserDefaults?) -> Bool {
                record.apply(signal)
            }
            public func save(to defaults: UserDefaults, key: String = defaultsKey) {}
        }
        """#)

    // 2. Purchasing

    static let offerLedgerToday = File(path: "Sources/EntitlementKit/UnlockOfferLedger.swift", source: #"""
        public enum UnlockOfferEvent: String { case purchaseStarted, purchaseSucceeded, purchaseUnrecognised }
        public struct UnlockOfferLedger {
            private mutating func record(_ event: UnlockOfferEvent, at bucket: RoadBucket) {}
            public func count(of event: UnlockOfferEvent) -> Int { 0 }
            public mutating func launched(lifetimeMetres: Double) {}
            /// This app called `Product.purchase()` — a doc comment, not a call.
            @discardableResult
            public mutating func purchasing(lifetimeMetres: Double,
                                            isolation: isolated (any Actor)? = #isolation,
                                            buy: () async -> UnlockOfferEvent) async -> UnlockOfferEvent {
                let bucket = RoadBucket.forLifetimeMetres(lifetimeMetres)
                record(.purchaseStarted, at: bucket)
                let outcome = await buy()
                record(outcome, at: bucket)
                return outcome
            }
        }
        """#)

    static let routeStoreToday = File(path: "Sources/NihongoRideApp/RouteStore.swift", source: #"""
        final class RouteStore {
            private(set) var lastOutcome: UnlockOfferEvent = .purchaseUnrecognised
            func purchase() async {
                guard let product else { lastOutcome = .purchaseUnrecognised; return }
                switch try await product.purchase() {
                default: lastOutcome = .purchaseSucceeded
                }
            }
        }
        """#)

    static let appModelBuyToday = File(path: "Sources/NihongoRideApp/AppModel.swift", source: #"""
        final class AppModel {
            func buyTheRoadWest() async {
                var ledger = unlockOfferLedger
                await ledger.purchasing(lifetimeMetres: lifetimeDistanceMeters) {
                    await entitlements.purchase()
                    return entitlements.lastOutcome
                }
                unlockOfferLedger = ledger
            }
            var debug: String { "started \(unlockOfferLedger.count(of: .purchaseStarted))" }
        }
        """#)

    /// The purchase moved out of the closure: the ledger records an attempt after it finished.
    static let appModelBuyOutside = File(path: "Sources/NihongoRideApp/AppModel.swift", source: #"""
        final class AppModel {
            func buyTheRoadWest() async {
                var ledger = unlockOfferLedger
                await entitlements.purchase()
                await ledger.purchasing(lifetimeMetres: lifetimeDistanceMeters) { entitlements.lastOutcome }
                unlockOfferLedger = ledger
            }
        }
        """#)

    /// A call that returns and a caller that records, via a new public recorder.
    static let offerLedgerWithOutcomeRecorder = File(path: "Sources/EntitlementKit/UnlockOfferLedger.swift", source: #"""
        public struct UnlockOfferLedger {
            private mutating func record(_ event: UnlockOfferEvent, at bucket: RoadBucket) {}
            public mutating func recordOutcome(_ outcome: UnlockOfferEvent, lifetimeMetres: Double) {
                record(outcome, at: RoadBucket.forLifetimeMetres(lifetimeMetres))
            }
            public mutating func purchasing(lifetimeMetres: Double, buy: () async -> UnlockOfferEvent) async -> UnlockOfferEvent {
                record(.purchaseStarted, at: .nihonbashi)
                let outcome = await buy()
                record(outcome, at: .nihonbashi)
                return outcome
            }
        }
        """#)

    static let appModelRecordsOutcome = File(path: "Sources/NihongoRideApp/AppModel.swift", source: #"""
        final class AppModel {
            func buyTheRoadWest() async {
                var ledger = unlockOfferLedger
                await ledger.purchasing(lifetimeMetres: lifetimeDistanceMeters, buy: {
                    await entitlements.purchase()
                    return .purchaseUnrecognised
                })
                ledger.recordOutcome(entitlements.lastOutcome, lifetimeMetres: lifetimeDistanceMeters)
                unlockOfferLedger = ledger
            }
        }
        """#)

    /// The primitive recorder made public and used at the call site.
    static let offerLedgerPublicRecord = File(path: "Sources/EntitlementKit/UnlockOfferLedger.swift", source: #"""
        public struct UnlockOfferLedger {
            public mutating func record(_ event: UnlockOfferEvent, at bucket: RoadBucket) {}
            public mutating func purchasing(lifetimeMetres: Double, buy: () async -> UnlockOfferEvent) async -> UnlockOfferEvent {
                record(.purchaseStarted, at: .nihonbashi)
                let outcome = await buy()
                record(outcome, at: .nihonbashi)
                return outcome
            }
        }
        """#)

    static let appModelRecordsStart = File(path: "Sources/NihongoRideApp/AppModel.swift", source: #"""
        final class AppModel {
            func buyTheRoadWest() async {
                unlockOfferLedger.record(.purchaseStarted, at: .kyoto)
                var ledger = unlockOfferLedger
                await ledger.purchasing(lifetimeMetres: lifetimeDistanceMeters) {
                    await entitlements.purchase()
                    return entitlements.lastOutcome
                }
            }
        }
        """#)

    /// The home records only the attempt; the outcome is left to whoever called.
    static let offerLedgerHomeThatReturns = File(path: "Sources/EntitlementKit/UnlockOfferLedger.swift", source: #"""
        public struct UnlockOfferLedger {
            private mutating func record(_ event: UnlockOfferEvent, at bucket: RoadBucket) {}
            public mutating func purchasing(lifetimeMetres: Double, buy: () async -> UnlockOfferEvent) async -> UnlockOfferEvent {
                record(.purchaseStarted, at: .nihonbashi)
                return await buy()
            }
        }
        """#)

    // 3. Review prompt

    static let reviewLedgerToday = File(path: "Sources/StoreReviewKit/ReviewPrompt.swift", source: #"""
        public struct ReviewPromptLedger {
            public private(set) var requestDates: [Date]
            public func decide(moment: RideMoment, policy: ReviewPromptPolicy, now: Date, suppressed: Bool) -> ReviewPromptDecision {
                if suppressed { return .suppressed }
                return .asked
            }
            /// Do not refactor this into a `decide()` that returns and a caller that acts: ask()
            @discardableResult
            public mutating func requestIfEarned(moment: RideMoment,
                                                 policy: ReviewPromptPolicy = .init(),
                                                 now: Date = Date(),
                                                 suppressed: Bool = false,
                                                 ask: () -> Void) -> ReviewPromptDecision {
                let decision = decide(moment: moment, policy: policy, now: now, suppressed: suppressed)
                outcomes[decision.rawValue, default: 0] += 1
                if decision == .asked {
                    requestDates.append(now)
                    ask()
                }
                return decision
            }
        }
        """#)

    static let appModelReviewToday = File(path: "Sources/NihongoRideApp/AppModel.swift", source: #"""
        final class AppModel {
            func considerReviewPrompt(now: Date = Date(), ask: () -> Void) {
                guard let moment = pendingReviewMoment else { return }
                pendingReviewMoment = nil
                let isolated = Self.currentIsolation.touchesNothingOfTheUsers
                reviewPromptLedger.requestIfEarned(moment: moment, now: now, suppressed: isolated, ask: ask)
                if !isolated { reviewPromptLedger.save(to: Self.settingsStore) }
            }
        }
        """#)

    static let resultsViewToday = File(path: "Sources/NihongoRideApp/ResultsView.swift", source: #"""
        struct ResultsView: View {
            @Environment(\.requestReview) private var requestReview
            var body: some View {
                VStack {}
                    .onAppear {
                        model.considerReviewPrompt { requestReview() }
                    }
            }
        }
        """#)

    /// A decision returned to a caller that acts.
    static let appModelReviewSplit = File(path: "Sources/NihongoRideApp/AppModel.swift", source: #"""
        final class AppModel {
            func considerReviewPrompt(now: Date = Date(), ask: () -> Void) {
                guard let moment = pendingReviewMoment else { return }
                let isolated = Self.currentIsolation.touchesNothingOfTheUsers
                let decision = reviewPromptLedger.decide(moment: moment, policy: .init(), now: now, suppressed: isolated)
                reviewPromptLedger.requestIfEarned(moment: moment, now: now, suppressed: isolated, ask: {})
                if decision == .asked { ask() }
            }
        }
        """#)

    /// The view asks by itself.
    static let resultsViewAsksAlone = File(path: "Sources/NihongoRideApp/ResultsView.swift", source: #"""
        struct ResultsView: View {
            @Environment(\.requestReview) private var requestReview
            var body: some View {
                VStack {}
                    .onAppear {
                        model.considerReviewPrompt { }
                        if model.rideWasGood { requestReview() }
                    }
            }
        }
        """#)

    /// The act moved out of the recorded branch inside the home.
    static let reviewLedgerAskOutsideBranch = File(path: "Sources/StoreReviewKit/ReviewPrompt.swift", source: #"""
        public struct ReviewPromptLedger {
            public mutating func requestIfEarned(moment: RideMoment, now: Date = Date(), ask: () -> Void) -> ReviewPromptDecision {
                let decision = decide(moment: moment, policy: .init(), now: now, suppressed: false)
                if decision == .asked {
                    requestDates.append(now)
                }
                if decision == .asked { ask() }
                return decision
            }
        }
        """#)
}

// MARK: - Suites

private func shippedSources() throws -> [CallSiteScanner.File] {
    let files = try CallSiteScanner.shippedSources.get()
    // A scan that read nothing reports clean. 92 files today; the floor is well below that and
    // far above zero.
    #expect(files.count >= 80, "only \(files.count) Swift files under Sources/ — the scan is misdirected")
    return files
}

@Suite("EntitlementLedger.apply mutates and saves in one branch — no caller splits it")
struct EntitlementApplyOneBranchTests {
    typealias S = OneBranchSamples

    @Test("no file in Sources/ applies a store signal to the record and saves it separately")
    func theShippedSourcesKeepOneBranch() throws {
        let report = OneBranchRules.entitlementApply(try shippedSources())
        #expect(report.counts["homes"] == 1, "the rule's home was not found: \(report.counts)")
        // RouteStore's five ledger-level applies today (the seam's three, refresh, purchase).
        #expect((report.counts["ledgerLevelCalls"] ?? 0) >= 3,
                "only \(report.counts["ledgerLevelCalls"] ?? 0) apply(_:savingTo:) call(s) found — the scan is reading the wrong files")
        #expect((report.counts["ledgerNames"] ?? 0) >= 1,
                "no property is declared as an EntitlementLedger — the name resolution is exercising nothing")
        #expect(report.violations.isEmpty, "\(report.violations.count) violation(s):\n\(report.violations.joined(separator: "\n"))")
    }

    @Test("today's shape passes, including files full of look-alikes")
    func todaysShapePasses() {
        let report = OneBranchRules.entitlementApply([S.entitlementHome, S.entitlementAdapterToday, S.appModelLookAlikes])
        #expect(report.violations.isEmpty, "the scan fires on the shape it must allow: \(report.violations)")
        #expect(report.counts["ledgerLevelCalls"] == 3)
    }

    @Test("a record-level apply followed by a separate save is caught")
    func theSplitInTheAdapterIsCaught() {
        let report = OneBranchRules.entitlementApply([S.entitlementHome, S.entitlementSplitInAdapter])
        #expect(report.violations.contains { $0.contains("RouteStore.swift:5") && $0.contains("without saving") },
                "the record-level apply was not caught: \(report.violations)")
        #expect(report.violations.contains { $0.contains("RouteStore.swift:7") && $0.contains("apart from the apply") },
                "the separate save was not caught: \(report.violations)")
    }

    @Test("a copy mutated in another file and saved through another object is caught")
    func theSplitElsewhereIsCaught() {
        let report = OneBranchRules.entitlementApply([S.entitlementHome, S.entitlementAdapterToday, S.entitlementSplitElsewhere])
        #expect(report.violations.contains { $0.contains("AppModel.swift:4") }, "the copy's apply was missed: \(report.violations)")
        #expect(report.violations.contains { $0.contains("AppModel.swift:5") }, "entitlements.ledger.save was missed: \(report.violations)")
        #expect(report.violations.contains { $0.contains("defaults key") }, "the direct write of the key was missed: \(report.violations)")
    }

    @Test("an apply(_:savingTo:) that no longer saves is caught")
    func aHomeThatReturnsIsCaught() {
        let report = OneBranchRules.entitlementApply([S.entitlementHomeThatReturns, S.entitlementAdapterToday])
        #expect(report.violations.contains { $0.contains("no longer saves") }, "\(report.violations)")
    }
}

@Suite("UnlockOfferLedger.purchasing records the attempt and the answer itself — no caller records")
struct PurchasingOneBranchTests {
    typealias S = OneBranchSamples

    @Test("no file in Sources/ purchases or records a purchase outcome outside purchasing")
    func theShippedSourcesKeepOneBranch() throws {
        let report = OneBranchRules.purchasing(try shippedSources())
        #expect(report.counts["homes"] == 1 && report.counts["adapters"] == 1, "\(report.counts)")
        #expect((report.counts["callSites"] ?? 0) >= 1, "no call to purchasing found — the scan is misdirected")
        #expect((report.counts["answerReads"] ?? 0) >= 1,
                "nothing outside the adapter reads lastOutcome — the rule about reading it is exercising nothing")
        #expect(report.violations.isEmpty, "\(report.violations.count) violation(s):\n\(report.violations.joined(separator: "\n"))")
    }

    @Test("today's shape passes")
    func todaysShapePasses() {
        let report = OneBranchRules.purchasing([S.offerLedgerToday, S.routeStoreToday, S.appModelBuyToday])
        #expect(report.violations.isEmpty, "the scan fires on the shape it must allow: \(report.violations)")
        #expect(report.counts["callSites"] == 1 && report.counts["answerReads"] == 1, "\(report.counts)")
    }

    @Test("a purchase moved out of the closure is caught")
    func purchaseOutsideTheClosureIsCaught() {
        let report = OneBranchRules.purchasing([S.offerLedgerToday, S.routeStoreToday, S.appModelBuyOutside])
        #expect(report.violations.contains { $0.contains("AppModel.swift:4") && $0.contains("purchases outside") }, "\(report.violations)")
        #expect(report.violations.contains { $0.contains("AppModel.swift:5") && $0.contains("does not purchase") }, "\(report.violations)")
    }

    @Test("an outcome recorded at the call site through a new recorder is caught")
    func outcomeRecordedAtTheCallSiteIsCaught() {
        let report = OneBranchRules.purchasing([S.offerLedgerWithOutcomeRecorder, S.routeStoreToday, S.appModelRecordsOutcome])
        #expect(report.violations.contains { $0.contains("recordOutcome records an event its caller hands it") }, "\(report.violations)")
        #expect(report.violations.contains { $0.contains("AppModel.swift:8") && $0.contains("outside the closure") }, "\(report.violations)")
    }

    @Test("a public record(_:at:) used at the call site is caught")
    func aPublicRecorderIsCaught() {
        let report = OneBranchRules.purchasing([S.offerLedgerPublicRecord, S.routeStoreToday, S.appModelRecordsStart])
        #expect(report.violations.contains { $0.contains("no longer private") }, "\(report.violations)")
        #expect(report.violations.contains { $0.contains("AppModel.swift:3") && $0.contains(".purchaseStarted") }, "\(report.violations)")
    }

    @Test("a purchasing that no longer records the outcome is caught")
    func aHomeThatReturnsIsCaught() {
        let report = OneBranchRules.purchasing([S.offerLedgerHomeThatReturns, S.routeStoreToday, S.appModelBuyToday])
        #expect(report.violations.contains { $0.contains("no longer records the outcome") }, "\(report.violations)")
    }
}

@Suite("ReviewPromptLedger.requestIfEarned decides and acts together — no caller splits it")
struct RequestIfEarnedOneBranchTests {
    typealias S = OneBranchSamples

    @Test("no file in Sources/ decides outside requestIfEarned or asks for a review on its own")
    func theShippedSourcesKeepOneBranch() throws {
        let report = OneBranchRules.reviewPrompt(try shippedSources())
        #expect(report.counts["homes"] == 1, "\(report.counts)")
        #expect((report.counts["callSites"] ?? 0) >= 1 && (report.counts["wrappers"] ?? 0) >= 1,
                "no call to requestIfEarned found outside its home — the scan is misdirected: \(report.counts)")
        #expect((report.counts["reviewRequests"] ?? 0) >= 1,
                "no requestReview() call found — the rule about where it may be called is exercising nothing")
        #expect(report.violations.isEmpty, "\(report.violations.count) violation(s):\n\(report.violations.joined(separator: "\n"))")
    }

    @Test("today's shape passes")
    func todaysShapePasses() {
        let report = OneBranchRules.reviewPrompt([S.reviewLedgerToday, S.appModelReviewToday, S.resultsViewToday])
        #expect(report.violations.isEmpty, "the scan fires on the shape it must allow: \(report.violations)")
        #expect(report.counts["wrappers"] == 1 && report.counts["reviewRequests"] == 1, "\(report.counts)")
    }

    @Test("a decide() returned to a caller that acts is caught")
    func theSplitAtTheCallSiteIsCaught() {
        let report = OneBranchRules.reviewPrompt([S.reviewLedgerToday, S.appModelReviewSplit, S.resultsViewToday])
        #expect(report.violations.contains { $0.contains("AppModel.swift:5") && $0.contains("decide() outside") }, "\(report.violations)")
        #expect(report.violations.contains { $0.contains("AppModel.swift:7") && $0.contains("calls ask() itself") }, "\(report.violations)")
    }

    @Test("a view that requests a review by itself is caught")
    func aViewAskingAloneIsCaught() {
        let report = OneBranchRules.reviewPrompt([S.reviewLedgerToday, S.appModelReviewToday, S.resultsViewAsksAlone])
        #expect(report.violations.contains { $0.contains("ResultsView.swift:7") && $0.contains("requests a review outside") }, "\(report.violations)")
    }

    @Test("ask() moved out of the recorded branch is caught")
    func askOutsideTheBranchIsCaught() {
        let report = OneBranchRules.reviewPrompt([S.reviewLedgerAskOutsideBranch, S.appModelReviewToday, S.resultsViewToday])
        #expect(report.violations.contains { $0.contains("same conditional block") }, "\(report.violations)")
    }
}
