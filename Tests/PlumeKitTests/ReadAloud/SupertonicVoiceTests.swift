import Foundation
import Testing
@testable import PlumeKit

@Suite("Supertonic voice")
struct SupertonicVoiceTests {
    /// Loading never downloads: without the completion marker it fails, and writes nothing.
    @Test func loadingWithoutTheVoiceFailsAndDownloadsNothing() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plume-tests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let voice = SupertonicVoice(entry: VoiceCatalog.f1, modelsDirectory: folder)
        await #expect(throws: ReadAloudError.voiceNotInstalled) { try await voice.load() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func speaksAt44kHz() {
        let voice = SupertonicVoice(entry: VoiceCatalog.f1, modelsDirectory: URL(fileURLWithPath: "/nonexistent"))
        #expect(voice.sampleRate == 44_100)
    }
}
