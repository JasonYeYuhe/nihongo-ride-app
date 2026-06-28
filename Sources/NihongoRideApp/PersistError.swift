import Foundation
import os

/// A **user-initiated** data write that failed to persist — e.g. creating/renaming a
/// list, starring a word. Surfaced once via a RootView alert so the user knows their
/// change may not have been saved. (Background / automatic writes never alert — an
/// alert there could loop on a persistently-failing disk; they only log. PLAN-V1.7 §D.)
enum PersistError: Equatable {
    case saveFailed

    func message(zh: Bool) -> String {
        switch self {
        case .saveFailed:
            return zh
                ? "保存更改时出错,改动可能未能保存。请重试。"
                : "Couldn't save your change — it may not have been kept. Please try again."
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
}
