import Foundation
import Testing

/// `./scripts/test.sh` and CI set aside settings, library, support folder and command
/// channel. Without them, a test that read the settings would open those of the installed
/// app (the test runner does not have Plume's identifier): a bare `swift test` therefore
/// fails on purpose.
@Suite("Test isolation")
struct IsolationTests {
    @Test func testsAreSeparateFromTheInstalledApp() {
        let environment = ProcessInfo.processInfo.environment
        for name in ["PLUME_DEFAULTS", "PLUME_SUPPORT", "PLUME_LIBRARY", "PLUME_CHANNEL"] {
            #expect(environment[name]?.isEmpty == false, "\(name) is missing: run ./scripts/test.sh")
        }
    }
}
