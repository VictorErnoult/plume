import Testing
@testable import Plume

/// The command words the running app understands, and the ones `plume` forwards to it.
/// Pure mapping only: nothing is sent to the real app.
@Suite("Remote commands")
struct RemoteTests {
    @Test func everyWordMapsToItsAction() {
        let expected: [String: Remote.Action] = [
            "toggle-dictee": .toggleDictation, "toggle-reunion": .toggleMeeting,
            "toggle-capture": .toggleCapture, "toggle-transform": .toggleTransform,
            "stop": .stop, "cancel": .cancel, "pause": .pause, "paste-last": .pasteLast,
            "restore": .restore, "open": .open, "snapshot": .snapshot,
            "selftest-system-audio": .selftestSystemAudio, "selftest-mic": .selftestMic,
        ]
        for (word, action) in expected {
            #expect(Remote.action(for: word) == action, "\(word)")
        }
    }

    @Test func drawerWordsWorkInBothLanguages() {
        for word in ["drawer-open", "tiroir-ouvert"] { #expect(Remote.action(for: word) == .drawer(open: true), "\(word)") }
        for word in ["drawer-close", "tiroir-ferme"] { #expect(Remote.action(for: word) == .drawer(open: false), "\(word)") }
    }

    @Test func unknownWordsDoNothing() {
        #expect(Remote.action(for: "") == nil)
        #expect(Remote.action(for: "toggle-meeting") == nil)
        #expect(Remote.action(for: "drawer") == nil)
    }

    /// A word missing from `CLI.commands` would launch the app instead of reaching it.
    @Test func theCommandLineForwardsAllDrawerWords() {
        for word in ["drawer-open", "drawer-close", "tiroir-ouvert", "tiroir-ferme"] {
            #expect(CLI.commands.contains(word), "\(word)")
            #expect(CLI.handles(["plume", word]), "\(word)")
        }
    }
}
