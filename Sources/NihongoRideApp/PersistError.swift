import Foundation
import os

/// A **user-initiated** data write that failed to persist — e.g. creating/renaming a
/// list, starring a word. Surfaced once via a RootView alert so the user knows their
/// change may not have been saved. (Background / automatic writes never alert — an
/// alert there could loop on a persistently-failing disk; they only log. PLAN-V1.7 §D.)
enum PersistError: Equatable {
    case saveFailed
    /// The word-list file could not be READ at launch, so the app is running on an empty
    /// stand-in and refuses to write anything over the original. Distinct from `saveFailed`
    /// because the user's data is probably FINE and the honest advice is different: don't
    /// edit, and retry. (v1.16 §C.)
    case listsUnreadable

    func message(zh: Bool) -> String {
        switch self {
        case .saveFailed:
            return zh
                ? "保存更改时出错,改动可能未能保存。请重试。"
                : "Couldn't save your change — it may not have been kept. Please try again."
        case .listsUnreadable:
            return zh
                ? "这次启动读不到你的词单文件,所以词单暂时是空的——你的数据很可能还在。"
                  + "为避免覆盖它,词单编辑已停用。请点「重试」,或重启应用。"
                : "Your word lists couldn't be read this launch, so they're showing empty — "
                  + "your data is most likely still there. Editing is disabled so nothing "
                  + "overwrites it. Tap Retry, or relaunch the app."
        }
    }
}

/// Lightweight logger for persistence failures (visible in Console.app; no stdout
/// spam, no alert). Used by both user-initiated and background write paths so a
/// failure is never *fully* silent — only the user-initiated path also alerts.
enum PersistLog {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.jasonye.nihongoride",
        category: "persist")

    static func failure(_ what: String, _ error: Error) {
        logger.error("persist failed [\(what, privacy: .public)]: \(error.localizedDescription, privacy: .public)")
    }

    /// A write deliberately NOT performed because the store could not be read at launch.
    /// Loud, because the app is running on an empty store the user's real data may contradict.
    static func skipped(_ what: String, reason: String) {
        logger.error("persist SKIPPED [\(what, privacy: .public)]: \(reason, privacy: .public)")
    }

    /// What each store's load reported. Logged once at launch so a support question about
    /// vanished progress has something to look at.
    static func loadOutcome(_ what: String, _ outcome: String) {
        logger.info("loaded [\(what, privacy: .public)]: \(outcome, privacy: .public)")
    }
}
