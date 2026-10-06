import AppKit
import PlumeKit
import SwiftUI

/// Off-screen rendering of the interface to PNG (`plume render <folder>`), to check
/// the look without a screenshot. With `--demo`, the window shows an invented library
/// and a fictional first name: enough to make publishable screenshots.
@MainActor
enum UIRender {
    static func run(directory: String, demo: Bool = false) {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        if demo { DemoLibrary.install() }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        Fonts.register()

        islandStates(output)
        drawerSteps(output)

        let session = SessionController()
        session.debugSet(phase: .idle)
        let app = AppModel(session: session)
        app.refreshNow()
        if let meeting = app.library.transcripts.first(where: { $0.speakers.count > 1 }) {
            app.library.selection = meeting.id
        }
        // The full Settings page, in a very tall window, to see every section.
        app.page = .settings
        window(
            AppShell(app: app, session: session), size: NSSize(width: 1040, height: 2500),
            name: "app-settings-full", in: output, appearance: .darkAqua)
        for (suffix, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            for page in Page.allCases {
                app.page = page
                window(
                    AppShell(app: app, session: session), size: NSSize(width: 1040, height: 680),
                    name: "app-\(page.rawValue)-\(suffix)", in: output, appearance: appearance)
            }
        }
        // Home during a dictation: the button shows the incoming voice.
        app.page = .home
        session.debugSet(
            phase: .recording, elapsed: 12,
            levels: (0..<SessionController.levelCount).map { Float(0.25 + 0.6 * abs(sin(Double($0) * 0.9))) })
        window(
            AppShell(app: app, session: session), size: NSSize(width: 1040, height: 680),
            name: "app-home-dictation-dark", in: output, appearance: .darkAqua)
        session.debugSet(phase: .idle)
        // The changelog, as it opens from "What's new".
        window(
            ChangelogView(releases: ChangelogFile.releases), size: NSSize(width: 420, height: 460),
            name: "whats-new-dark", in: output, appearance: .darkAqua)
        // Cancelled recordings, still recoverable.
        app.page = .history
        app.library.filter = .cancelled
        window(
            AppShell(app: app, session: session), size: NSSize(width: 1040, height: 680),
            name: "app-history-cancelled-dark", in: output, appearance: .darkAqua)
    }

    private static func islandStates(_ output: URL) {
        let session = SessionController()
        let levels: [Float] = (0..<SessionController.levelCount).map { i in
            Float(0.25 + 0.75 * abs(sin(Double(i) * 0.9) * cos(Double(i) * 0.37)))
        }
        let meeting = Transcript(id: "x", createdAt: Date(), mode: .meeting, duration: 60, engine: "", text: "", rawText: "")
        // (name, visible commands, state setting)
        let states: [(String, Bool, () -> Void)] = [
            ("island-1-start", true, { session.debugSet(phase: .recording, elapsed: 2, levels: levels) }),
            ("island-2-compact", false, { session.debugSet(phase: .recording, elapsed: 21, levels: levels) }),
            (
                "island-3-live", false,
                {
                    session.debugSet(
                        phase: .recording, elapsed: 14, levels: levels,
                        committed: "Hi Alex, I wanted to talk to you about this morning's deployment.",
                        volatile: "We have an issue with the Shopify webhook, we should check the logs before")
                }
            ),
            (
                "island-4-meeting-hover", true,
                {
                    session.debugSet(
                        phase: .recording, mode: .meeting, elapsed: 754, levels: levels,
                        committed: "Yes, we're sticking to the budget we planned at the start.",
                        volatile: "And for delivery, we're aiming for the end of October", systemActive: true)
                }
            ),
            ("island-5-processing", false, { session.debugSet(phase: .processing(tr("Transcript"))) }),
            ("island-6-pasted", false, { session.debugSet(phase: .done(tr("Pasted"))) }),
            (
                "island-7-meeting-done", false,
                { session.debugSet(phase: .done(tr("Meeting saved")), mode: .meeting, transcript: meeting) }
            ),
            ("island-8-error", false, { session.debugSet(phase: .failed(tr("Nothing heard"))) }),
            ("island-9-pause", true, { session.debugSet(phase: .recording, mode: .meeting, elapsed: 312, paused: true) }),
            ("island-10-call-detected", false, { session.debugSet(phase: .suggestion("Zoom")) }),
            (
                "island-11-instruction", false,
                { session.debugSet(phase: .recording, intent: .transform, elapsed: 2, levels: levels) }
            ),
            ("island-12-clean-up", false, { session.debugSet(phase: .processing(tr("Cleaning up"))) }),
            (
                "island-13-mic-muted", false,
                { session.debugSet(phase: .recording, elapsed: 24, quietMic: true, levels: [Float](repeating: 0, count: SessionController.levelCount)) }
            ),
        ]
        let geometries: [(String, NotchGeometry)] = [
            ("notch", NotchGeometry(notchWidth: 185, topHeight: 32)),
            ("external-display", NotchGeometry(notchWidth: 0, topHeight: 25)),
        ]
        for (name, controls, configure) in states {
            configure()
            for (suffix, geometry) in geometries {
                let model = IslandModel()
                model.shown = true
                model.geometry = geometry
                model.pinnedControls = controls
                let view = IslandView(session: session, model: model)
                    .frame(width: 620, height: 230)
                    .background(FakeScreenTop(geometry: geometry))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                write(renderer.nsImage, to: output.appendingPathComponent("\(name)-\(suffix).png"))
            }
        }
    }

    /// Four steps of the drawer opening on hover, side by side.
    private static func drawerSteps(_ output: URL) {
        let session = SessionController()
        let levels: [Float] = (0..<SessionController.levelCount).map { i in
            Float(0.25 + 0.75 * abs(sin(Double(i) * 0.9) * cos(Double(i) * 0.37)))
        }
        session.debugSet(phase: .recording, elapsed: 21, levels: levels)
        let geometry = NotchGeometry(notchWidth: 185, topHeight: 32)
        let steps: [CGFloat] = [0, 0.3, 0.65, 1]
        let strip = HStack(spacing: 0) {
            ForEach(steps, id: \.self) { fraction in
                let model = IslandModel()
                let _ = {
                    model.shown = true
                    model.geometry = geometry
                    model.pinnedControls = true
                    model.openFraction = fraction
                }()
                IslandView(session: session, model: model)
                    .frame(width: 420, height: 130)
                    .background(FakeScreenTop(geometry: geometry))
            }
        }
        let renderer = ImageRenderer(content: strip)
        renderer.scale = 2
        write(renderer.nsImage, to: output.appendingPathComponent("island-drawer-steps.png"))
    }

    /// Renders a real AppKit window off-screen.
    private static func window<V: View>(
        _ view: V, size: NSSize, name: String, in output: URL, appearance: NSAppearance.Name
    ) {
        let host = NSHostingController(rootView: view)
        let window = UnconstrainedWindow(contentViewController: host)
        window.appearance = NSAppearance(named: appearance)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(2.2))
        guard let frame = window.contentView?.superview ?? window.contentView else { return }
        guard let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: output.appendingPathComponent("\(name).png"))
        }
        window.orderOut(nil)
    }

    private static func write(_ image: NSImage?, to url: URL) {
        guard let tiff = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url)
    }
}

/// Render window that the system doesn't resize to the screen's dimensions.
private final class UnconstrainedWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Fake top of the screen for mockups: a background, the menu bar and the notch.
private struct FakeScreenTop: View {
    var geometry: NotchGeometry

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(red: 0.36, green: 0.45, blue: 0.62), Color(red: 0.78, green: 0.70, blue: 0.72)],
                startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Color.white.opacity(0.28)).frame(height: geometry.topHeight)
            if geometry.hasNotch {
                UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                    .fill(Color.black)
                    .frame(width: geometry.notchWidth, height: geometry.topHeight)
            }
        }
    }
}

/// Invented library for screenshots (`plume render <folder> --demo`): a few
/// weeks of dictations and a meeting of three, in a temporary folder.
@MainActor
enum DemoLibrary {
    static func install() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plume-demo-\(UUID().uuidString)")
        setenv("PLUME_LIBRARY", root.path, 1)
        setenv("PLUME_FIRST_NAME", "Emma", 1)
        // Vocabulary and rules invented too: nothing from the real Application Support folder.
        setenv("PLUME_SUPPORT", root.appendingPathComponent("support").path, 1)
        ReplacementStore.save([
            Replacement(original: "super whisper", with: "Superwhisper"),
            Replacement(original: "my signature", with: "Emma Clarke\nArt director · Mist Studio\n+44 20 7946 0958"),
            Replacement(original: "see tee ay", with: "CTA"),
        ])
        AppRuleStore.save([
            AppRule(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", style: .message, pressReturn: true),
            AppRule(bundleID: "com.apple.mail", name: "Mail", style: .standard, polish: true, instructions: "stay formal but warm"),
            AppRule(bundleID: "com.apple.Terminal", name: "Terminal", style: .casual, typeText: true),
            AppRule(bundleID: "*", name: tr("All other applications")),
        ])
        let store = TranscriptStore(root: root)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let sentences = [
            "Remember to send the quote to the agency before Friday.",
            "Newsletter idea: a recap of the month's new features, short and visual.",
            "Tell Mark the mockup is approved, we're going with version two.",
            "Shopping list: pasta, tomatoes, basil, parmesan and coffee.",
            "The login bug comes from the expired token, it needs a refresh at startup.",
            "Thanks for the feedback, I'll look at it tomorrow morning and get back to you.",
            "For the blog post, open with an anecdote rather than the numbers.",
            "Call the garage about the car's yearly inspection.",
        ]
        var generator = SystemRandomNumberGenerator()
        // Nearly a year of activity, increasingly regular.
        for day in stride(from: 320, through: 1, by: -1) {
            let chance = day < 30 ? 0.9 : day < 120 ? 0.6 : 0.3
            guard Double.random(in: 0..<1, using: &generator) < chance else { continue }
            let count = day < 14 ? 4 : Int.random(in: 1...3, using: &generator)
            for n in 0..<count {
                let date = calendar.date(byAdding: .minute, value: 9 * 60 + n * 95, to: calendar.date(byAdding: .day, value: -day, to: today)!)!
                let text = (0..<Int.random(in: 3...12, using: &generator)).map { _ in sentences.randomElement()! }.joined(separator: " ")
                save(store, at: date, text: text)
            }
        }
        // Today: the dictations visible at the top of the history.
        let recent: [(Int, String, String?)] = [
            (9 * 60 + 12, "Hi all, quick update on the launch: the page is live and the first feedback is very good.", "Slack"),
            (10 * 60 + 47, "Tell Mark the mockup is approved, we're going with version two and a more visible button.", "Mail"),
            (14 * 60 + 5, "Newsletter idea: a recap of the month's new features, short and visual, with one screenshot per feature.", "Notion"),
            (16 * 60 + 38, "The login bug comes from the expired token: it needs a refresh when the app starts, not only at sign-in.", "Cursor"),
        ]
        let meetingStart = calendar.date(byAdding: .minute, value: 11 * 60 + 30, to: today)!
        let lines: [(String, AudioChannel, String)] = [
            ("Nina", .system, "Okay, shall we go over the launch of the new version?"),
            (tr("Me"), .mic, "Sure. The page is ready, we still need the screenshots and the announcement text."),
            ("Sam", .system, "I can take care of the screenshots this afternoon, I just need the latest build."),
            (tr("Me"), .mic, "Great, I'll send it to you after the meeting."),
            ("Nina", .system, "For the announcement, are we aiming for Thursday morning? That's when we get the most opens."),
            ("Sam", .system, "Thursday works for me. Should we also plan a message for existing users?"),
            (tr("Me"), .mic, "Good idea, a short email with the three main new features and a link to the page."),
            ("Nina", .system, "I'll write it tomorrow and share it with you before noon."),
        ]
        var segments: [Segment] = []
        var clock = 1.0
        for (i, line) in lines.enumerated() {
            let length = Double(line.2.split(separator: " ").count) * 0.38
            segments.append(Segment(id: i, speaker: line.0, channel: line.1, start: clock, end: clock + length, text: line.2))
            clock += length + 1.2
        }
        try? store.save(
            Transcript(
                id: store.makeID(for: meetingStart), createdAt: meetingStart, mode: .meeting, duration: 1_472, engine: "demo",
                text: TranscriptBuilder.text(for: segments), rawText: "", segments: segments, speakers: [tr("Me"), "Nina", "Sam"],
                title: "Launch of the new version",
                summary: """
                    ## Key points
                    - The launch page is ready; the screenshots and the announcement text are still to do.
                    - The announcement is planned for Thursday morning, when the most emails get opened.
                    - A short email will tell existing users about the three main new features.

                    ## Decisions
                    - Announcement on Thursday morning.
                    - Email to existing users, with a link to the page.

                    ## Actions
                    - **Sam**: the screenshots, this afternoon.
                    - **\(tr("Me"))**: send the latest build to Sam after the meeting.
                    - **Nina**: write the email tomorrow and share it before noon.
                    """))
        for (minutes, text, app) in recent {
            save(store, at: calendar.date(byAdding: .minute, value: minutes, to: today)!, text: text, app: app)
        }
        // Two recordings cancelled by mistake, including a meeting not yet transcribed.
        let cancelled = CancelledStore(library: root)
        let tone = (0..<48_000).map { Float(sin(Double($0) * 2 * .pi * 220 / 16_000)) * 0.2 }
        let dictationStart = calendar.date(byAdding: .minute, value: 17 * 60 + 2, to: today)!
        try? cancelled.keep(
            CancelledRecording(
                id: store.makeID(for: dictationStart), createdAt: dictationStart, cancelledAt: dictationStart.addingTimeInterval(14),
                mode: .dictation, duration: 14, app: "Mail",
                text: "Thanks for the invite, I'll be there on Thursday. I'll send you the slides tonight.",
                rawText: "thanks for the invite i'll be there on thursday i'll send you the slides tonight"),
            mic: tone)
        let meetingCancel = calendar.date(byAdding: .minute, value: 15 * 60, to: today)!
        try? cancelled.keep(
            CancelledRecording(
                id: store.makeID(for: meetingCancel), createdAt: meetingCancel, cancelledAt: meetingCancel.addingTimeInterval(1_260),
                mode: .meeting, duration: 1_260, app: "Zoom"),
            mic: tone, system: (samples: tone, offset: 0))
    }

    private static func save(_ store: TranscriptStore, at date: Date, text: String, app: String? = nil) {
        let words = text.split(separator: " ").count
        try? store.save(
            Transcript(
                id: store.makeID(for: date), createdAt: date, mode: .dictation, duration: Double(words) / 2.4, engine: "demo",
                text: text, rawText: text.lowercased(), app: app))
    }
}
