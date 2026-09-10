import Testing
import Foundation
import CloudKit
import ReviewKit
import ConjugationReviewKit
import JournalKit
import SyncKit
import WordListsKit
@testable import NihongoRideApp

/// The six `CKRecord` ↔ model converter pairs: 756 lines, and until now zero tests (v1.32 §D2).
///
/// Both reviewers of `PLAN-V1.32` ranked this above the entitlement seam, for a reason worth
/// restating: **a converter that wrote the wrong type or dropped a field would corrupt user data
/// across every device the account owns, and it would pass every gate in this repo.**
/// `scripts/check_prod_schema.sh` proves the field NAMES exist in Production — it matches a name
/// followed by any type token and never compares that token to what the app writes — and nothing
/// anywhere exercises a value.
///
/// # The instrument, and what it cannot see
///
/// Each test round-trips a value through the real converters and compares **the whole value**,
/// not a list of fields. That is deliberate: a field-by-field assertion is a list somebody has to
/// remember to extend, and the defect under examination is precisely a field somebody forgot.
/// Whole-value equality has no such list — add a stored property, and the test fails until the
/// converter carries it.
///
/// It only works if **every field differs from what the decoder would fall back to**. A field set
/// to its own default is invisible to this instrument: drop it, and the fallback reproduces it.
/// So each fixture below sets every field to a distinct non-default value, and `sampleIsUsable`
/// checks that claim against a freshly-defaulted value rather than asserting it in a comment.
///
/// **What falls outside this file**, said plainly rather than implied away: the `.unknownItem`
/// cache-drop, the zone-deleted rebuild and the `serverRecordChanged` re-enqueue all arrive as
/// `CKSyncEngine.Event` values, which have no public initialiser. They are not reachable from any
/// test without a seam that does not exist, and §D2's plan text lists them as though they were.
@Suite("CKRecord ↔ model: every field survives the wire")
struct CloudKitCodecTests {

    static let zone = CKRecordZone.ID(zoneName: "test", ownerName: CKCurrentUserDefaultName)

    static func record(_ type: String, _ key: String) -> CKRecord {
        CKRecord(recordType: type, recordID: CKRecord.ID(recordName: "\(type):\(key)", zoneID: zone))
    }

    // MARK: The fixtures — every field distinct from the decoder's fallback

    static func srsCard() -> SRSCard {
        var card = SRSCard(id: "n5-042")
        card.easeFactor = 1.77
        card.interval = 13
        card.repetitions = 4
        card.dueDate = Date(timeIntervalSince1970: 1_700_000_000)
        card.lapses = 3
        card.lastReviewed = Date(timeIntervalSince1970: 1_600_000_000)
        card.totalReviews = 21
        card.totalMistakes = 8
        return card
    }

    static func conjugationCard() -> ConjugationSRSCard {
        var card = ConjugationSRSCard(id: "n5-042#te")
        card.easeFactor = 1.91
        card.interval = 7
        card.repetitions = 2
        card.dueDate = Date(timeIntervalSince1970: 1_710_000_000)
        card.lapses = 5
        card.lastReviewed = Date(timeIntervalSince1970: 1_610_000_000)
        card.totalReviews = 17
        card.totalMistakes = 6
        return card
    }

    static func ride() -> RideRecord {
        RideRecord(id: UUID(uuidString: "1B4E28BA-2FA1-11D2-883F-0016D3CCA427")!,
                   date: Date(timeIntervalSince1970: 1_720_000_000),
                   mode: "timeAttack", level: "N2", score: 651, wpm: 37.5, accuracy: 0.93,
                   wordsCompleted: 44, lapsed: 3, distanceMeters: 812.5, duration: 121.25)
    }

    static func wordList() -> WordList {
        WordList(id: "list-7", name: "Kanji I keep missing", ids: ["a", "b", "c"],
                 nameUpdatedAt: Date(timeIntervalSince1970: 1_730_000_000),
                 deleted: true, deletedAt: Date(timeIntervalSince1970: 1_731_000_000),
                 isDefault: false,
                 wordMeta: ["a": WordMeta(a: Date(timeIntervalSince1970: 1_732_000_000),
                                          r: Date(timeIntervalSince1970: 1_733_000_000))])
    }

    /// The instrument's own precondition, checked rather than asserted in prose.
    ///
    /// Whole-value equality can only detect a dropped field if the field's value differs from what
    /// the decoder substitutes when it is absent. This compares each fixture against a
    /// freshly-defaulted value of the same type and requires them to differ everywhere it can see.
    @Test("the fixtures differ from a default value — otherwise a dropped field is invisible")
    func sampleIsUsable() {
        let fresh = SRSCard(id: "n5-042")
        let card = Self.srsCard()
        #expect(card.easeFactor != fresh.easeFactor)
        #expect(card.interval != fresh.interval)
        #expect(card.repetitions != fresh.repetitions)
        #expect(card.dueDate != fresh.dueDate)
        #expect(card.lapses != fresh.lapses)
        #expect(card.lastReviewed != fresh.lastReviewed)
        #expect(card.totalReviews != fresh.totalReviews)
        #expect(card.totalMistakes != fresh.totalMistakes)

        let freshConj = ConjugationSRSCard(id: "n5-042#te")
        let conj = Self.conjugationCard()
        #expect(conj.easeFactor != freshConj.easeFactor)
        #expect(conj.interval != freshConj.interval)
        #expect(conj.repetitions != freshConj.repetitions)
        #expect(conj.dueDate != freshConj.dueDate)
        #expect(conj.lapses != freshConj.lapses)
        #expect(conj.lastReviewed != freshConj.lastReviewed)
        #expect(conj.totalReviews != freshConj.totalReviews)
        #expect(conj.totalMistakes != freshConj.totalMistakes)

        // `rideRecord(from:)`'s fallbacks are all zero, and `wordList(from:)`'s are ""/[]/false/
        // nil/epoch — so every non-zero, non-empty field above is visible to the round trip.
        let r = Self.ride()
        #expect(r.score != 0 && r.wpm != 0 && r.accuracy != 0 && r.wordsCompleted != 0)
        #expect(r.lapsed != 0 && r.distanceMeters != 0 && r.duration != 0)
        #expect(!r.mode.isEmpty && !r.level.isEmpty)
        let l = Self.wordList()
        #expect(!l.name.isEmpty && !l.ids.isEmpty && l.deleted && l.deletedAt != nil)
        #expect(!l.wordMeta.isEmpty)
        #expect(l.nameUpdatedAt != Date(timeIntervalSince1970: 0))
    }

    // MARK: The six pairs

    @Test("SRSCard survives the wire, whole")
    func srsCardRoundTrips() throws {
        let original = Self.srsCard()
        let record = Self.record("SRSCard", original.id)
        CloudKitSyncController.fill(record, from: original)
        let decoded = try #require(CloudKitSyncController.srsCard(from: record))
        #expect(decoded == original)
    }

    @Test("ConjugationSRSCard survives the wire, whole")
    func conjugationCardRoundTrips() throws {
        let original = Self.conjugationCard()
        let record = Self.record("ConjugationSRSCard", original.id)
        CloudKitSyncController.fill(record, from: original)
        let decoded = try #require(CloudKitSyncController.conjSrsCard(from: record))
        #expect(decoded == original)
    }

    /// The two SRS types share a field shape and NOT a record type or a key field
    /// (`vocabID` vs `cardID`). A conjugation card decoded as a vocabulary card would put a
    /// `sourceID#form` id into the flat review store, which red line §1 forbids structurally.
    @Test("the two SRS record types do not decode as each other")
    func theTwoSRSTypesDoNotCross() {
        let conjRecord = Self.record("ConjugationSRSCard", "n5-042#te")
        CloudKitSyncController.fill(conjRecord, from: Self.conjugationCard())
        #expect(CloudKitSyncController.srsCard(from: conjRecord) == nil,
                "a conjugation card decoded as a vocabulary card — red line §1 is structural")

        let srsRecord = Self.record("SRSCard", "n5-042")
        CloudKitSyncController.fill(srsRecord, from: Self.srsCard())
        #expect(CloudKitSyncController.conjSrsCard(from: srsRecord) == nil)
    }

    @Test("RideRecord survives the wire, whole")
    func rideRoundTrips() throws {
        let original = Self.ride()
        let record = Self.record("RideRecord", original.id.uuidString)
        CloudKitSyncController.fill(record, from: original)
        let decoded = try #require(CloudKitSyncController.rideRecord(from: record))
        #expect(decoded == original)
    }

    @Test("the odometer slot survives the wire, whole")
    func odometerRoundTrips() throws {
        let original = OdometerLog.Slot(words: 4_210, distanceMeters: 93_112.5, runs: 187)
        let record = Self.record("Odometer", "device-A")
        CloudKitSyncController.fill(record, from: original, deviceID: "device-A")
        let decoded = try #require(CloudKitSyncController.odometerSlot(from: record))
        #expect(decoded == original)
    }

    /// The ONE survivor of the forty-field drop sweep, pinned so it stays a decision.
    ///
    /// `deviceID` is written and never read: the device a slot belongs to is the record's
    /// identity, recovered from the record NAME at both decode call sites. Dropping the field
    /// therefore changes nothing a test can see — which is exactly what the sweep reported, and
    /// exactly why it needs a test of its own rather than a shrug. This one fails if the decode
    /// ever starts trusting the body field, because at that point the field and the record name
    /// can disagree and a peer's odometer merges into the wrong device's slot.
    @Test("an odometer slot's device comes from the record NAME, not from the body field")
    func theOdometerDeviceComesFromTheRecordName() throws {
        // A record whose body field CONTRADICTS its name. Only one of them can be the device.
        let record = Self.record("Odometer", "device-A")
        CloudKitSyncController.fill(record, from: OdometerLog.Slot(words: 1, distanceMeters: 2, runs: 3),
                                    deviceID: "device-B-WRONG")
        #expect(record["deviceID"] as? String == "device-B-WRONG", "the arrangement must have landed")
        #expect(CloudKitSyncController.parse(record.recordID.recordName).key == "device-A",
                "the record name is the device, and it is what both decode call sites read")

        // And the slot itself carries no device at all — so nothing downstream can pick the
        // wrong one by accident.
        let decoded = try #require(CloudKitSyncController.odometerSlot(from: record))
        #expect(decoded == OdometerLog.Slot(words: 1, distanceMeters: 2, runs: 3))
    }

    @Test("WordList survives the wire, whole — including the wordMeta blob")
    func wordListRoundTrips() throws {
        let original = Self.wordList()
        let record = Self.record("WordList", original.id)
        CloudKitSyncController.fill(record, from: original)
        let decoded = try #require(CloudKitSyncController.wordList(from: record))
        #expect(decoded == original)
    }

    /// `WordList.id` and `isDefault` are the two fields that do NOT travel as record fields —
    /// they are recovered from the record name. So they are exactly the pair a field-based test
    /// would silently not cover.
    @Test("a word list's identity comes from the record NAME, not from a field")
    func wordListIdentityTravelsInTheRecordName() throws {
        let record = Self.record("WordList", WordList.defaultID)
        CloudKitSyncController.fill(record, from: Self.wordList())
        let decoded = try #require(CloudKitSyncController.wordList(from: record))
        #expect(decoded.id == WordList.defaultID)
        #expect(decoded.isDefault, "the default list lost its identity crossing the wire")
        #expect(record["id"] == nil, "if the id ever becomes a field, this test is measuring nothing")
    }

    @Test("the legacy saved-words deck survives the wire")
    func savedDeckRoundTrips() {
        let ids = ["n5-1", "n5-2", "n4-9"]
        let record = Self.record("SavedWords", "deck")
        CloudKitSyncController.fill(record, savedIDs: ids)
        #expect(CloudKitSyncController.savedIDs(from: record) == ids)
    }

    // MARK: The blob inside the blob

    /// `wordMeta` is a JSON string inside a CKRecord field, so it has its own encoder — and the
    /// nearest existing test (`SyncMergeWordMetaTests.wireRoundTrip`) warns about exactly the
    /// date-strategy coupling that would break it and then exercises a bare
    /// `JSONEncoder`/`JSONDecoder` pair instead of these functions. It cannot: its target cannot
    /// see the app module. **No mutation of the real converter can kill it** — which is §D4's
    /// class of defect, found outside §D4.
    @Test("encodeMeta / decodeMeta are exercised, not re-implemented")
    func metaBlobRoundTrips() {
        let meta: [String: WordMeta] = [
            "a": WordMeta(a: Date(timeIntervalSince1970: 1_000_000), r: nil),
            "b": WordMeta(a: nil, r: Date(timeIntervalSince1970: 2_000_000)),
        ]
        let encoded = CloudKitSyncController.encodeMeta(meta)
        #expect(encoded != nil)
        #expect(CloudKitSyncController.decodeMeta(encoded) == meta)

        // Empty meta is deliberately nil on the wire — assigning nil REMOVES the key, which is
        // the mechanism that hid the missing `deletedAt` Production field for three versions.
        #expect(CloudKitSyncController.encodeMeta([:]) == nil)

        // A blob that will not parse degrades to `[:]` rather than stranding the whole list.
        #expect(CloudKitSyncController.decodeMeta("{not json") == [:])
        #expect(CloudKitSyncController.decodeMeta(nil) == [:])
        #expect(CloudKitSyncController.decodeMeta(42) == [:], "a non-String field is not a crash")
    }

    // MARK: Record names

    /// `parse` splits on the FIRST colon and a conjugation card's key contains a `#`, not a `:` —
    /// but a word-list id is user-adjacent, so the "key may itself contain ':'" claim in its doc
    /// is the one worth pinning.
    @Test("parse keeps a colon inside the key")
    func parseKeepsColonsInTheKey() {
        #expect(CloudKitSyncController.parse("WordList:a:b").type == "WordList")
        #expect(CloudKitSyncController.parse("WordList:a:b").key == "a:b")
        #expect(CloudKitSyncController.parse("nocolon").type == "")
        #expect(CloudKitSyncController.parse("nocolon").key == "nocolon")
    }
}
