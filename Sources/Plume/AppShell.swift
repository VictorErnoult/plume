import AppKit
import PlumeKit
import SwiftUI
import UniformTypeIdentifiers

struct PageHeader<Subtitle: View, Trailing: View>: View {
    var title: String
    @ViewBuilder var subtitle: () -> Subtitle
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(UI.sans(24, .medium)).tracking(-0.4).foregroundStyle(UI.text)
                subtitle().font(UI.sans(14)).foregroundStyle(UI.text2)
            }
            Spacer()
            trailing()
        }
    }
}

extension PageHeader where Subtitle == Text?, Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: { subtitle.map { Text($0) } }, trailing: { EmptyView() })
    }
}

extension PageHeader where Subtitle == Text? {
    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(title: title, subtitle: { subtitle.map { Text($0) } }, trailing: trailing)
    }
}

/// Plume's window: four pages, and a floating bar at the bottom to switch between them,
/// change the theme and mute the sound, the same as on the portfolio.
struct AppShell: View {
    @ObservedObject var app: AppModel
    @ObservedObject var session: SessionController
    @State private var dropTargeted = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                switch app.page {
                case .home: HomePage(app: app, session: session, settings: app.settings).transition(pageTransition)
                case .history: HistoryPage(app: app, library: app.library).transition(pageTransition)
                case .vocabulary: VocabularyPage(settings: app.settings).transition(pageTransition)
                case .apps: ApplicationsPage(settings: app.settings).transition(pageTransition)
                case .settings: SettingsPage(settings: app.settings).transition(pageTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(UI.ease, value: app.page)

            Dock(app: app, settings: app.settings)
                .padding(.bottom, 18)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 12) {
                ChangelogButton()
                UpdatePill()
                StatusPill(session: session, settings: app.settings)
            }
            .padding(.top, 11)
            .padding(.trailing, 14)
        }
        .frame(minWidth: 880, minHeight: 560)
        // Changing the language redraws the whole window: every text is read again from the table.
        .id(app.settings.language)
        .background(UI.window)
        .foregroundStyle(UI.text)
        .tracking(-0.15)
        .ignoresSafeArea()
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(UI.text, style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(UI.text.opacity(0.05)))
                    .padding(10)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(UI.quick, value: dropTargeted)
        // An audio file dropped anywhere in the window is transcribed.
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { app.importFiles([url]) }
                }
            }
            return true
        }
    }

    /// The incoming page rises slightly as it appears; the outgoing one fades out.
    private var pageTransition: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity)
    }
}

// MARK: - Floating bar

private struct Dock: View {
    @ObservedObject var app: AppModel
    @ObservedObject var settings: SettingsModel
    @Environment(\.colorScheme) private var scheme
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(Page.allCases.enumerated()), id: \.element) { index, page in
                DockItem(
                    glyph: page.glyph, label: page.title, key: "\(index + 1)", selected: app.page == page,
                    namespace: selection
                ) {
                    withAnimation(UI.spring) { app.page = page }
                }
            }
            Rectangle().fill(UI.active).frame(width: 1, height: 18).padding(.horizontal, 7)
            // The sun enters and leaves on the left, the moon on the right, as on the portfolio.
            DockItem(
                glyph: scheme == .dark ? .sun : .moon, label: scheme == .dark ? tr("Light theme") : tr("Dark theme"),
                key: "T", slide: scheme == .dark ? -1 : 1, namespace: selection
            ) {
                Sounds.play(.tab)
                settings.appearance = scheme == .dark ? "light" : "dark"
            }
            DockItem(
                glyph: settings.sounds ? .speakerOn : .speakerOff, label: settings.sounds ? tr("Mute") : tr("Unmute"),
                key: "S", namespace: selection
            ) {
                settings.sounds.toggle()
                if settings.sounds { Sounds.play(.confirm) }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(UI.line, lineWidth: 1))
        .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.10), radius: 18, y: 8)
    }
}

/// Blurred slide of an icon that replaces another.
private struct SlideBlur: ViewModifier {
    var offset: CGFloat
    var hidden: Bool

    func body(content: Content) -> some View {
        content
            .offset(x: hidden ? offset : 0)
            .opacity(hidden ? 0 : 1)
            .blur(radius: hidden ? 3 : 0)
    }
}

private struct DockItem: View {
    var glyph: Glyph
    var label: String
    var key: String
    var selected = false
    /// Direction of the slide when the icon changes (0: plain fade).
    var slide: CGFloat = 0
    var namespace: Namespace.ID
    var action: () -> Void
    @State private var hovering = false
    @State private var tip = false
    @State private var tipTask: DispatchWorkItem?

    private static let side: CGFloat = 40
    private static let iconSize: CGFloat = 19

    var body: some View {
        Button {
            showTip(false)
            action()
        } label: {
            ZStack {
                Icon(glyph, size: Self.iconSize)
                    .id(glyph)
                    .transition(
                        .modifier(
                            active: SlideBlur(offset: slide * Self.iconSize * 0.7, hidden: true),
                            identity: SlideBlur(offset: 0, hidden: false)))
            }
            .foregroundStyle(selected || hovering ? UI.text : UI.text2)
            // On hover, the icon grows a little, as on the portfolio.
            .scaleEffect(hovering && !selected ? 1.12 : 1)
            .frame(width: Self.side, height: Self.side)
            .clipped()
            .background {
                if selected {
                    // The active entry's background slides from one page to the other.
                    RoundedRectangle(cornerRadius: UI.radius, style: .continuous)
                        .fill(UI.active)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(UI.hover)
                }
            }
            .contentShape(Rectangle())
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.28), value: glyph)
        }
        .buttonStyle(PressStyle(scale: 0.92))
        .onHover { inside in
            hovering = inside
            if inside { Sounds.hover(.hoverNav) }
            showTip(inside)
        }
        // The label and its key come out above the bar, once the pointer has settled.
        .overlay(alignment: .top) {
            if tip {
                HStack(spacing: 6) {
                    Text(label).font(UI.sans(12, .medium)).foregroundStyle(UI.text)
                    Keycap(key)
                }
                .padding(.leading, 9)
                .padding(.trailing, 5)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(UI.card))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(UI.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 8)
                .fixedSize()
                .offset(y: -40)
                .transition(.opacity.combined(with: .offset(y: 4)))
                .allowsHitTesting(false)
            }
        }
        .animation(UI.quick, value: hovering)
        .animation(.easeOut(duration: 0.14), value: tip)
    }

    private func showTip(_ show: Bool) {
        tipTask?.cancel()
        guard show else {
            tip = false
            return
        }
        let work = DispatchWorkItem { tip = true }
        tipTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
    }
}

/// An update found in the background: a discreet button that opens the details.
/// "What's new": the changelog (`CHANGELOG.md`), with a dot while there is something
/// new that hasn't been opened.
private struct ChangelogButton: View {
    @State private var open = false
    @State private var seen = PlumeSettings.shared.changelogSeen
    @State private var hovering = false
    private let releases = ChangelogFile.releases

    private var unseen: Bool { Changelog.signature(of: releases) != seen }

    var body: some View {
        if !releases.isEmpty {
            Button {
                Sounds.play(.tab)
                open.toggle()
                seen = Changelog.signature(of: releases)
                PlumeSettings.shared.changelogSeen = seen
            } label: {
                // A plain icon; a dot while there is something new.
                Icon(.sparkles, size: 13)
                    .foregroundStyle(hovering || open ? UI.text : UI.text2)
                    .frame(width: 26, height: 24)
                    .overlay(alignment: .topTrailing) {
                        if unseen {
                            Circle().fill(Theme.recording).frame(width: 6, height: 6).offset(x: -3, y: 3)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering || open ? UI.hover : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .onHover { hovering = $0 }
            .help(tr("What's new"))
            .animation(UI.quick, value: hovering)
            .animation(UI.spring, value: unseen)
            .popover(isPresented: $open, arrowEdge: .bottom) { ChangelogView(releases: releases) }
        }
    }
}

/// The changelog, version by version.
struct ChangelogView: View {
    var releases: [Changelog.Release]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(tr("What's new")).font(UI.sans(18, .medium)).tracking(-0.3)
                ForEach(releases) { release in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Plume \(release.version)").font(UI.sans(14, .semibold))
                            Text(release.date.map(ChangelogFile.format) ?? tr("in progress"))
                                .font(UI.sans(12))
                                .foregroundStyle(UI.text3)
                        }
                        ForEach(release.entries, id: \.self) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle().fill(UI.text3).frame(width: 4, height: 4).offset(y: -2)
                                (Text(entry.domain.map { $0 + " · " } ?? "").foregroundColor(UI.text2)
                                    + Text(entry.text).foregroundColor(UI.text))
                                    .font(UI.sans(13))
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(width: 420, alignment: .leading)
        }
        .frame(width: 420, height: 460)
        .background(UI.window)
    }
}

/// The `CHANGELOG.md` shipped with the app (or the repo's, for a development binary).
enum ChangelogFile {
    static let releases: [Changelog.Release] = {
        let bundled = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md")
        let development = Bundle.repositoryResource("../CHANGELOG.md")?.standardizedFileURL
        guard let url = [bundled, development].compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return Changelog.parse(text)
    }()

    /// "Oct 5, 2026" from "2026-10-05".
    static func format(_ date: String) -> String {
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        guard let parsed = input.date(from: date) else { return date }
        let output = DateFormatter()
        output.locale = L10n.current.locale
        output.dateStyle = .medium
        return output.string(from: parsed)
    }
}

private struct UpdatePill: View {
    @ObservedObject private var updates = Updates.shared

    var body: some View {
        if let version = updates.pending {
            Button(action: { updates.check() }) {
                HStack(spacing: 6) {
                    Icon(.download, size: 12)
                    Text("Plume \(version) " + tr("is available")).font(UI.sans(12, .medium))
                }
                .foregroundStyle(UI.onText)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(UI.text))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .hoverSound(.hoverButton)
            .transition(.opacity.combined(with: .offset(y: -4)))
        }
    }
}

/// The transcription model is downloaded just once, at first launch: we say what is
/// happening, how big it is, and how far along it is.
private struct ModelCard: View {
    @ObservedObject var session: SessionController

    private var state: (title: String, detail: String, fraction: Double?, failed: Bool)? {
        switch session.modelStatus {
        case .loading(let fraction?) where fraction < 1:
            return (
                tr("Downloading the transcription model"),
                tr("Just once, about 600 MB. After that everything happens on this Mac, offline."), fraction, false
            )
        case .failed(let reason):
            return (tr("The transcription model could not be loaded"), reason, nil, true)
        default:
            return nil
        }
    }

    var body: some View {
        if let state {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(state.title).font(UI.sans(14, .medium))
                            Text(state.detail).font(UI.sans(13)).foregroundStyle(UI.text2).lineLimit(2)
                        }
                        Spacer()
                        if let fraction = state.fraction {
                            Text("\(Int(fraction * 100)) %").font(UI.mono(13)).foregroundStyle(UI.text2)
                        } else if state.failed {
                            PlumeButton(title: tr("Retry"), kind: .primary) { session.loadModel() }
                        }
                    }
                    if let fraction = state.fraction {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(UI.active)
                                Capsule().fill(UI.text).frame(width: max(4, proxy.size.width * fraction))
                            }
                        }
                        .frame(height: 4)
                        .animation(UI.ease, value: fraction)
                    }
                }
            }
            .transition(.opacity)
        }
    }
}

/// Engine state and shortcut reminder, at the top right of the window.
private struct StatusPill: View {
    @ObservedObject var session: SessionController
    @ObservedObject var settings: SettingsModel

    private var state: (color: Color, text: String, ready: Bool) {
        switch session.phase {
        case .recording: return (Theme.recording, session.mode == .meeting ? tr("Recording a meeting") : tr("Dictating"), false)
        case .processing: return (UI.text, tr("Transcribing…"), false)
        default:
            switch session.modelStatus {
            case .loading(let fraction?) where fraction < 1: return (UI.text, tr("Model:") + " \(Int(fraction * 100)) %", false)
            case .loading: return (UI.text, tr("Loading the model…"), false)
            case .failed: return (Theme.recording, tr("Model unavailable"), false)
            case .ready: return (UI.success, tr("Ready"), true)
            }
        }
    }

    var body: some View {
        let state = state
        // Ready is the normal state: nothing to report. The pill only appears when something is
        // going on (model loading, dictation, transcription).
        if !state.ready {
        HStack(spacing: 7) {
            Circle()
                .fill(state.color)
                .frame(width: 6, height: 6)
                .shadow(color: state.color.opacity(0.7), radius: 3)
            Text(state.text).font(UI.sans(12)).foregroundStyle(UI.text2).contentTransition(.opacity)

        }
        .frame(height: 22)
        .animation(UI.quick, value: state.text)
        .transition(.opacity)
        }
    }
}

// MARK: - Home

struct HomePage: View {
    @ObservedObject var app: AppModel
    @ObservedObject var session: SessionController
    @ObservedObject var settings: SettingsModel
    private let refresh = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private var firstName: String {
        // PLUME_FIRST_NAME: forced first name, for demo screenshots.
        let name = ProcessInfo.processInfo.environment["PLUME_FIRST_NAME"] ?? NSFullUserName()
        return name.split(separator: " ").first.map(String.init) ?? ""
    }

    private var stats: LibraryStats { app.stats }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: firstName.isEmpty ? tr("Hello") : tr("Hello") + " \(firstName)") {
                    HStack(spacing: 6) {
                        Text(tr("Press"))
                        Keycaps(shortcut: HotkeyManager.describe(settings.dictationShortcut))
                        Text(tr("to dictate; the text is pasted where your cursor is."))
                    }
                } trailing: {
                    HStack(spacing: 8) {
                        PlumeButton(title: tr("Transcribe a file"), icon: .download) { app.chooseFiles() }
                        // With no shortcut: the window steps aside and dictation starts in the notch.
                        DictateButton(session: session) { app.onStartFromWindow() }
                    }
                }
                .padding(.bottom, 10)
                .rise(0)

                if settings.permissionsMissing {
                    PermissionsCard(settings: settings).rise(1)
                }
                ModelCard(session: session)

                HStack(spacing: 10) {
                    TodayTile(stats: stats).rise(2)
                    StreakTile(stats: stats).rise(3)
                    StatTile(
                        value: stats.timeSaved / 60, format: HomePage.span, label: tr("saved over typing"),
                        detail: "\(HomePage.number(Double(stats.words))) " + tr("words in total")
                    ).rise(4)
                    StatTile(
                        value: Double(stats.wordsPerMinute), format: { $0 < 1 ? "—" : HomePage.number($0) },
                        label: tr("words per minute"), detail: tr("typing: 40")
                    ).rise(5)
                }
                .fixedSize(horizontal: false, vertical: true)

                // Activity and latest transcriptions side by side, at the same height.
                HStack(alignment: .top, spacing: 10) {
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(tr("Activity")).font(UI.sans(14, .medium))
                                Text(tr("words dictated per day")).font(UI.sans(13)).foregroundStyle(UI.text2)
                            }
                            ActivityHeatmap(days: stats.days)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(maxHeight: .infinity)
                    RecentCard(app: app)
                        .frame(maxHeight: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
                .rise(6)
            }
            .padding(.horizontal, UI.pagePadding)
            .padding(.top, 58)
            .padding(.bottom, UI.dockClearance)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .onReceive(refresh) { _ in settings.refreshPermissions() }
    }

    static func number(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.locale = L10n.current.locale
        return formatter.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value))"
    }

    /// Duration in minutes, written `12 min` or `3 h 20`.
    static func span(_ minutes: Double) -> String {
        let whole = Int(minutes.rounded())
        if whole < 60 { return "\(whole) min" }
        return String(format: "%d h %02d", whole / 60, whole % 60)
    }
}

/// "Dictate", next to "Transcribe a file". During a dictation, the button shows the
/// incoming voice (the same wave as in the notch) and a square to finish.
private struct DictateButton: View {
    @ObservedObject var session: SessionController
    var action: () -> Void
    @State private var hovering = false

    private var recording: Bool { session.phase == .recording }

    var body: some View {
        Button {
            Sounds.play(.click)
            action()
        } label: {
            HStack(spacing: 8) {
                if recording {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .frame(width: 9, height: 9)
                    Waveform(levels: session.levels, tint: .white)
                        .scaleEffect(0.8)
                        .frame(height: 18)
                    Text(Format.clock(session.elapsed))
                        .font(UI.mono(12.5, .medium))
                        .monospacedDigit()
                } else {
                    Icon(.mic, size: 14)
                    Text(tr("Dictate")).font(UI.sans(13, .medium))
                }
            }
            .foregroundStyle(recording ? Color.white : UI.onText)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: UI.radius, style: .continuous)
                    .fill(recording ? Theme.recording : UI.text.opacity(hovering ? 0.86 : 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover {
            hovering = $0
            if $0 { Sounds.hover(.hoverButton) }
        }
        .animation(UI.quick, value: hovering)
        .animation(UI.spring, value: recording)
        .help(recording ? tr("Finish the dictation") : tr("The window steps aside and the notch listens; the text is pasted where your cursor was."))
        .disabled(session.modelStatus != .ready && !recording)
    }
}

/// The three latest transcriptions, next to the activity.
private struct RecentCard: View {
    @ObservedObject var app: AppModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(tr("Latest transcriptions")).font(UI.sans(14, .medium))
                    Spacer()
                    Button {
                        withAnimation(UI.spring) { app.page = .history }
                    } label: {
                        Text(tr("See all")).font(UI.sans(13)).foregroundStyle(UI.text2)
                    }
                    .buttonStyle(PressStyle())
                }
                if app.recent.isEmpty {
                    Text(tr("Nothing yet: your first dictation will show up here."))
                        .font(UI.sans(13))
                        .foregroundStyle(UI.text2)
                        .padding(.top, 6)
                } else {
                    VStack(spacing: 2) {
                        ForEach(app.recent) { transcript in
                            RecentRow(transcript: transcript) { app.open(transcript) }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct RecentRow: View {
    var transcript: Transcript
    var action: () -> Void
    @State private var hovering = false
    @State private var copied = false

    /// "42 words · 18 s".
    private var summary: String {
        let words = LibraryStats.wordCount(transcript.text)
        return "\(HomePage.number(Double(words))) " + tr(words > 1 ? "words" : "word") + " · " + Format.duration(transcript.duration)
    }

    private var when: String {
        let calendar = Calendar.current
        let time = DateFormatter()
        time.locale = L10n.current.locale
        time.timeStyle = .short
        if calendar.isDateInToday(transcript.createdAt) { return time.string(from: transcript.createdAt) }
        return LibraryModel.dayTitle(calendar.startOfDay(for: transcript.createdAt)) + ", " + time.string(from: transcript.createdAt)
    }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: action) {
                HStack(alignment: .top, spacing: 10) {
                    Icon(transcript.mode == .meeting ? .users : transcript.mode == .imported ? .fileAudio : .mic, size: 12)
                        .foregroundStyle(UI.text2)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(UI.hover))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            // What is spoken: how many words, how much speaking time (and the
                            // title, if there is one).
                            if let title = transcript.title {
                                Text(title).font(UI.sans(13, .medium)).lineLimit(1)
                                Text(summary).font(UI.sans(12)).foregroundStyle(UI.text3).lineLimit(1).fixedSize()
                            } else {
                                Text(summary).font(UI.sans(13, .medium)).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text(when).font(UI.sans(12)).foregroundStyle(UI.text3).lineLimit(1)
                        }
                        Text(transcript.preview)
                            .font(UI.sans(13))
                            .foregroundStyle(UI.text2)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.985))
            // Copy in one click, without opening the transcription.
            Button {
                Sounds.play(.confirm)
                Paster.copy(transcript.text)
                withAnimation(UI.spring) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation(UI.spring) { copied = false } }
            } label: {
                Icon(copied ? .check : .copy, size: 13)
                    .foregroundStyle(copied ? UI.text : UI.text2)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? UI.selected : UI.hover))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .help(tr("Copy the text"))
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(hovering ? UI.hover : .clear))
        .onHover {
            hovering = $0
            if $0 { Sounds.hover(.hoverRow) }
        }
        .animation(UI.quick, value: hovering)
    }
}

/// Common template for the home tiles: they lift slightly on hover, with
/// a lighter edge and a note.
private struct Tile<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(UI.card))
            .overlay(
                RoundedRectangle(cornerRadius: UI.radius, style: .continuous)
                    .strokeBorder(hovering ? UI.text3 : UI.line, lineWidth: 1)
            )
            .shadow(color: .black.opacity(hovering ? 0.18 : 0), radius: 14, y: 6)
            .offset(y: hovering ? -2 : 0)
            .onHover {
                hovering = $0
                if $0 { Sounds.hover(.hoverCard) }
            }
            .animation(UI.spring, value: hovering)
    }
}

private struct TileFigure: View {
    var value: Double
    var format: (Double) -> String

    var body: some View {
        CountingText(value: value, format: format)
            .font(UI.sans(28, .medium))
            .tracking(-0.6)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// A key figure: the value in large type (it scrolls in on appearance), what it measures, a detail.
private struct StatTile: View {
    var value: Double
    var format: (Double) -> String
    var label: String
    var detail: String
    @State private var shown: Double = 0

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 4) {
                TileFigure(value: shown, format: format)
                Text(label).font(UI.sans(13, .medium))
                Text(detail).font(UI.sans(12)).foregroundStyle(UI.text2).lineLimit(1)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { shown = value } }
        .onChange(of: value) { _, new in withAnimation(.easeOut(duration: 0.6)) { shown = new } }
    }
}

/// Today's words, with a ring that fills toward the best day.
private struct TodayTile: View {
    var stats: LibraryStats
    @State private var shown: Double = 0
    @State private var progress: Double = 0

    private var record: Int { stats.bestDay?.words ?? 0 }
    private var isRecord: Bool { stats.wordsToday > 0 && stats.wordsToday >= record }
    private var target: Double { record > 0 ? min(1, Double(stats.wordsToday) / Double(record)) : 0 }

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 4) {
                TileFigure(value: shown, format: HomePage.number)
                Text(tr("words today")).font(UI.sans(13, .medium)).lineLimit(1)
                Text(isRecord ? tr("Best day") : tr("record:") + " \(HomePage.number(Double(record)))")
                    .font(UI.sans(12))
                    .foregroundStyle(isRecord ? UI.text : UI.text2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                ZStack {
                    Circle().stroke(UI.active, lineWidth: 3.5)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(UI.text, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 26, height: 26)
                .padding(.top, 4)
            }
        }
        .onAppear { animate() }
        .onChange(of: stats.wordsToday) { _, _ in animate() }
    }

    private func animate() {
        withAnimation(.easeOut(duration: 0.9)) { shown = Double(stats.wordsToday) }
        withAnimation(.spring(duration: 1.0, bounce: 0.2).delay(0.15)) { progress = target }
    }
}

/// The run of consecutive days, flame lit while it is ongoing.
private struct StreakTile: View {
    var stats: LibraryStats
    @State private var shown: Double = 0
    @State private var lit = false

    var body: some View {
        Tile {
            VStack(alignment: .leading, spacing: 4) {
                TileFigure(value: shown, format: HomePage.number)
                Text(stats.streak > 1 ? tr("days in a row") : tr("day in a row")).font(UI.sans(13, .medium)).lineLimit(1)
                Text(tr("record:") + " \(stats.bestStreak) " + tr(stats.bestStreak > 1 ? "days" : "day"))
                    .font(UI.sans(12))
                    .foregroundStyle(UI.text2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                Icon(.flame, size: 24, filled: stats.streak > 0)
                    .foregroundStyle(stats.streak > 0 ? UI.text : UI.text3)
                    .shadow(color: UI.text.opacity(stats.streak > 0 ? 0.3 : 0), radius: lit ? 8 : 2)
                    .scaleEffect(lit ? 1.06 : 0.96)
                    .padding(.top, 3)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { shown = Double(stats.streak) }
            guard stats.streak > 0 else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { lit = true }
        }
        .onChange(of: stats.streak) { _, new in withAnimation(.easeOut(duration: 0.6)) { shown = Double(new) } }
    }
}

/// Activity calendar: one cell per day, the brighter the chattier the day was.
private struct ActivityHeatmap: View {
    var days: [LibraryStats.Day]
    @State private var hovered: Date?
    @State private var revealed = false

    private static var dayFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = L10n.current.locale
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f
    }

    /// Weeks from Monday to Sunday, the last one possibly incomplete.
    private var weeks: [[LibraryStats.Day?]] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        var columns: [[LibraryStats.Day?]] = []
        var current: [LibraryStats.Day?] = []
        for day in days {
            let weekday = (calendar.component(.weekday, from: day.date) + 5) % 7  // Monday = 0
            if current.isEmpty, weekday > 0 { current = Array(repeating: nil, count: weekday) }
            current.append(day)
            if current.count == 7 {
                columns.append(current)
                current = []
            }
        }
        if !current.isEmpty { columns.append(current + Array(repeating: nil, count: 7 - current.count)) }
        return columns
    }

    private func color(_ words: Int, peak: Int) -> Color {
        guard words > 0 else { return UI.hover }
        let ratio = Double(words) / Double(max(peak, 1))
        let step = ratio > 0.75 ? 3 : (ratio > 0.45 ? 2 : (ratio > 0.2 ? 1 : 0))
        return UI.activity[step]
    }

    private static let cell: CGFloat = 15
    private static let gap: CGFloat = 4

    var body: some View {
        let peak = days.map(\.words).max() ?? 0
        let all = weeks
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                // We show as many weeks as the card can hold, the most recent ones.
                let fit = max(1, Int((proxy.size.width + Self.gap) / (Self.cell + Self.gap)))
                let columns = Array(all.suffix(fit))
                HStack(alignment: .top, spacing: Self.gap) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { index, week in
                        VStack(spacing: Self.gap) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(day.map { color($0.words, peak: peak) } ?? Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .strokeBorder(UI.text.opacity(hovered != nil && hovered == day?.date ? 0.7 : 0), lineWidth: 1.5)
                                    )
                                    .frame(width: Self.cell, height: Self.cell)
                                    .onHover { inside in
                                        guard let day else { return }
                                        hovered = inside ? day.date : (hovered == day.date ? nil : hovered)
                                        if inside, day.words > 0 { Sounds.hover(.hoverRow) }
                                    }
                            }
                        }
                        // Columns appear in a cascade, from the oldest to the most recent.
                        .opacity(revealed ? 1 : 0)
                        .offset(y: revealed ? 0 : 6)
                        .animation(UI.ease.delay(Double(index) * 0.012), value: revealed)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: Self.cell * 7 + Self.gap * 6)

            HStack(spacing: 6) {
                if let hovered, let day = days.first(where: { $0.date == hovered }) {
                    Text(Self.dayFormatter.string(from: day.date).capitalizedFirst)
                        .foregroundStyle(UI.text)
                    Text(day.words == 0 ? tr("nothing dictated") : "\(HomePage.number(Double(day.words))) " + tr("words"))
                } else {
                    Text(tr("Hover a cell to see a day's details."))
                }
                Spacer()
                Text(tr("Less"))
                ForEach(0..<4, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(UI.activity[step]).frame(width: 11, height: 11)
                }
                Text(tr("More"))
            }
            .font(UI.sans(12))
            .foregroundStyle(UI.text2)
            .animation(UI.quick, value: hovered)
        }
        .onAppear { revealed = true }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// "Copy" button that confirms with a check mark and a note.
struct CopyButton: View {
    var text: String
    var prominent = false
    @State private var copied = false

    var body: some View {
        PlumeButton(
            title: copied ? tr("Copied") : tr("Copy"), icon: copied ? .check : .copy,
            kind: prominent ? .primary : .secondary, sound: .confirm
        ) {
            Paster.copy(text)
            withAnimation(UI.spring) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation(UI.spring) { copied = false } }
        }
    }
}

/// The two essential permissions, until they are granted.
struct PermissionsCard: View {
    @ObservedObject var settings: SettingsModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("Two permissions to get started")).font(UI.sans(14, .medium))
                PermissionRow(
                    title: tr("Microphone access"), detail: tr("To hear your voice."), granted: settings.microphoneGranted,
                    action: settings.requestMicrophone)
                Rectangle().fill(UI.line).frame(height: 1)
                PermissionRow(
                    title: tr("Accessibility"), detail: tr("To paste the text into the active field."),
                    granted: settings.accessibilityGranted, action: settings.requestAccessibility)
            }
        }
    }
}

struct PermissionRow: View {
    var title: String
    var detail: String
    var granted: Bool
    var action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(UI.sans(14))
                Text(detail).font(UI.sans(13)).foregroundStyle(UI.text2)
            }
            Spacer()
            if granted {
                HStack(spacing: 6) {
                    Icon(.circleCheck, size: 15)
                    Text(tr("Granted")).font(UI.sans(13, .medium))
                }
                .foregroundStyle(UI.success)
                .transition(.scale.combined(with: .opacity))
            } else {
                PlumeButton(title: tr("Allow"), kind: .primary, action: action)
            }
        }
        .animation(UI.spring, value: granted)
    }
}
