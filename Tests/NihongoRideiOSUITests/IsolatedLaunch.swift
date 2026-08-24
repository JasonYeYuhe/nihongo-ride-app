import XCTest

/// **Every UI-test launch goes through here, and none of them may call `app.launch()` directly.**
///
/// These tests are not renders. They launch the real app and complete a real run, which writes
/// SRS progress, the ride journal, the odometer and the home-screen widget snapshot — and
/// pushes all of it to CloudKit if the device is signed in.
///
/// v1.24's App Group incident is the near-miss this exists to prevent repeating. That one
/// stamped fourteen days of zeros onto the owner's real widget from a unit test, and it was
/// recoverable because the damage was a local file. This is the same shape with a bigger blast
/// radius: a phantom ride pushed into the owner's real CloudKit database cannot be cleaned up
/// from the simulator that created it.
///
/// `NIHONGO_UITEST` redirects Application Support, the App Group container and UserDefaults
/// into a throwaway directory, and refuses to start sync at all. The property is asserted in
/// `AppModelTests.uiTestLaunchIsIsolated`, over the whole isolation value rather than over the
/// doors somebody remembered — with a negative control, because a function that isolated EVERY
/// launch would satisfy the assertion and silently disable sync in the shipping app.
///
/// It is also what lets these tests run against an unsigned build: without entitlements
/// `CKContainer.init(identifier:)` traps, and the app dies inside `AppModel.init` before any UI
/// appears. Not starting the sync controller is what keeps it alive.
extension XCUIApplication {
    /// Launches with every store redirected and CloudKit off.
    func launchIsolated(_ extraEnvironment: [String: String] = [:]) {
        launchEnvironment["NIHONGO_UITEST"] = "1"
        for (key, value) in extraEnvironment { launchEnvironment[key] = value }
        launch()
    }
}
