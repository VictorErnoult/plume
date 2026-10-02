import AppKit
import PlumeKit
import SwiftUI

// MARK: - Historique

struct HistoryPage: View {
    @ObservedObject var app: AppModel
    @ObservedObject var library: LibraryModel

    var body: some View {
        HStack(spacing: 0) {
            list.frame(width: 324)
            Rectangle().fill(UI.line).frame(width: 1)
            ZStack {
                if let transcript = library.selected {
                    TranscriptDetail(transcript: transcript, library: library, player: library.player)
                        .id(transcript.id)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                } else {
                    emptyState.transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(UI.ease, value: library.selection)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Historique").font(UI.sans(24, .medium)).tracking(-0.4)
                    Spacer()
                    if library.importing > 0 {
                        ProgressView().controlSize(.small).transition(.opacity)
                    }
                    PlumeButton(icon: .plus, help: "Transcrire un fichier audio") { app.chooseFiles() }
                }
                HStack(spacing: 7) {
                    Icon(.search, size: 14).foregroundStyle(UI.text2)
                    TextField("Rechercher", text: $library.query)
                        .textFieldStyle(.plain)
                        .font(UI.sans(14))
                    if !library.query.isEmpty {
                        Button(action: { library.query = "" }) {
                            Icon(.circleX, size: 14).foregroundStyle(UI.text3)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(UI.hover))

                FilterBar(selection: $library.filter)
            }
            .padding(.horizontal, 16)
            .padding(.top, 58)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(library.sections, id: \.title) { section in
                        Text(section.title)
                            .font(UI.sans(12, .medium))
                            .foregroundStyle(UI.text2)
                            .padding(.horizontal, 10)
                            .padding(.top, 12)
                            .padding(.bottom, 3)
                        ForEach(section.items) { transcript in
                            HistoryRow(transcript: transcript, selected: library.selection == transcript.id) {
                                library.selection = transcript.id
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, UI.dockClearance)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Icon(library.query.isEmpty ? .audioLines : .search, size: 28)
                .foregroundStyle(UI.text3)
            Text(library.query.isEmpty ? "Aucune transcription" : "Aucun résultat")
                .font(UI.sans(15, .medium))
            if library.query.isEmpty {
                Text("Dicte quelque chose, ou dépose un fichier audio dans cette fenêtre.")
                    .font(UI.sans(13))
                    .foregroundStyle(UI.text2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Filtres de l'historique ; le fond de l'onglet actif glisse de l'un à l'autre.
private struct FilterBar: View {
    @Binding var selection: HistoryFilter
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HistoryFilter.allCases) { filter in
                let active = selection == filter
                Button {
                    Sounds.play(.tab)
                    withAnimation(UI.spring) { selection = filter }
                } label: {
                    Text(filter.title)
                        .font(UI.sans(13, active ? .semibold : .regular))
                        .foregroundStyle(active ? UI.text : UI.text2)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(UI.selected)
                                    .matchedGeometryEffect(id: "filter", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
    }
}

private struct HistoryRow: View {
    var transcript: Transcript
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var glyph: Glyph {
        if transcript.device == "iphone" { return .smartphone }
        switch transcript.mode {
        case .dictation: return .mic
        case .meeting: return .users
        case .imported: return .fileAudio
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Icon(glyph, size: 13)
                    .foregroundStyle(selected ? UI.onText : UI.text2)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? UI.text : UI.hover))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(Self.time.string(from: transcript.createdAt))
                            .font(UI.mono(12))
                            .foregroundStyle(UI.text)
                        Text(transcript.mode.label)
                            .font(UI.sans(13))
                            .foregroundStyle(UI.text2)
                        Spacer(minLength: 4)
                        Text(Format.clock(transcript.duration))
                            .font(UI.mono(11))
                            .foregroundStyle(UI.text3)
                    }
                    Text(transcript.preview)
                        .font(UI.sans(13))
                        .foregroundStyle(UI.text2)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: UI.radius, style: .continuous)
                    .fill(selected ? UI.selected : (hovering ? UI.hover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.985))
        .onHover {
            hovering = $0
            if $0, !selected { Sounds.hover(.hoverRow) }
        }
        .animation(UI.quick, value: hovering)
        .animation(UI.quick, value: selected)
    }
}

private struct TranscriptDetail: View {
    var transcript: Transcript
    @ObservedObject var library: LibraryModel
    @ObservedObject var player: AudioPlayerModel

    @State private var renaming: String?
    @State private var newName = ""
    @State private var confirmingDelete = false

    private var audio: [URL] { library.audioURLs(for: transcript) }
    private var reprocessing: Bool { library.reprocessing == transcript.id }

    private var meta: String {
        var parts = [Format.duration(transcript.duration)]
        if transcript.speakers.count > 1 { parts.append("\(transcript.speakers.count) interlocuteurs") }
        parts.append("\(HomePage.number(Double(LibraryStats.wordCount(transcript.text)))) mots")
        if let app = transcript.app { parts.append(app) }
        if transcript.device == "iphone" { parts.append("iPhone") }
        return parts.joined(separator: "  ·  ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(TranscriptStore.title(for: transcript))
                            .font(UI.sans(20, .medium))
                            .tracking(-0.3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(meta)
                            .font(UI.sans(13))
                            .foregroundStyle(UI.text2)
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 6) {
                        CopyButton(text: transcript.text, prominent: true)
                        PlumeButton(icon: .folder, help: "Afficher les fichiers dans le Finder") { library.reveal(transcript) }
                        PlumeButton(icon: .trash, help: "Mettre à la corbeille") { confirmingDelete = true }
                    }
                }

                if audio.isEmpty {
                    Text("L'enregistrement audio n'a pas été conservé.")
                        .font(UI.sans(13))
                        .foregroundStyle(UI.text3)
                        .padding(.top, 14)
                } else {
                    PlayerBar(player: player, id: transcript.id, urls: audio, length: transcript.duration)
                        .padding(.top, 16)
                }

                if transcript.mode != .dictation, !audio.isEmpty {
                    voices.padding(.top, 12)
                }

                Rectangle().fill(UI.line).frame(height: 1).padding(.vertical, 18)

                if transcript.speakers.count > 1 {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(transcript.segments) { segment in
                            row(segment)
                        }
                    }
                    .opacity(reprocessing ? 0.35 : 1)
                } else {
                    Text(transcript.text)
                        .font(UI.sans(15))
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: 640, alignment: .leading)
                        .opacity(reprocessing ? 0.35 : 1)
                }
            }
            .padding(.horizontal, UI.pagePadding)
            .padding(.top, 58)
            .padding(.bottom, UI.dockClearance)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(UI.ease, value: reprocessing)
        }
        .confirmationDialog("Supprimer cette transcription ?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Mettre à la corbeille", role: .destructive) {
                Sounds.play(.refuse)
                library.delete(transcript)
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le texte et l'audio partent dans la corbeille du Mac.")
        }
        .alert(
            "Renommer l'interlocuteur",
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField("Nom", text: $newName)
            Button("Renommer") {
                if let renaming { library.rename(renaming, to: newName, in: transcript) }
                renaming = nil
            }
            Button("Annuler", role: .cancel) { renaming = nil }
        } message: {
            Text("Le nouveau nom remplace « \(renaming ?? "") » dans toute la transcription.")
        }
    }

    /// Refaire la séparation des voix, en précisant au besoin combien de personnes parlaient.
    private var voices: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Détection automatique") { library.reprocess(transcript, speakers: nil) }
                Divider()
                ForEach(1...8, id: \.self) { count in
                    Button(count == 1 ? "1 personne" : "\(count) personnes") { library.reprocess(transcript, speakers: count) }
                }
            } label: {
                HStack(spacing: 6) {
                    Icon(.users, size: 13)
                    Text("Refaire la séparation des voix").font(UI.sans(13, .medium))
                    Icon(.chevronDown, size: 12).foregroundStyle(UI.text2)
                }
                .foregroundStyle(UI.text)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(UI.hover))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
            .disabled(reprocessing)
            .help("Si les voix sont mal séparées, indique combien de personnes parlaient.")
            if reprocessing {
                ProgressView().controlSize(.small)
                Text("Nouvelle écoute en cours…").font(UI.sans(13)).foregroundStyle(UI.text2)
            }
        }
    }

    private func color(for speaker: String) -> Color {
        if speaker == "Moi" { return UI.text }
        let index = transcript.speakers.filter { $0 != "Moi" }.firstIndex(of: speaker) ?? 0
        return Theme.speakers[index % Theme.speakers.count]
    }

    private func row(_ segment: Segment) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    newName = segment.speaker
                    renaming = segment.speaker
                } label: {
                    Text(segment.speaker)
                        .font(UI.sans(13, .medium))
                        .foregroundStyle(color(for: segment.speaker))
                        .lineLimit(1)
                }
                .buttonStyle(PressStyle())
                .help("Renommer cet interlocuteur")
                Button {
                    player.play(id: transcript.id, urls: audio, from: segment.start)
                } label: {
                    Text(Format.clock(segment.start))
                        .font(UI.mono(11))
                        .foregroundStyle(UI.text3)
                }
                .buttonStyle(PressStyle())
                .help("Écouter à partir d'ici")
            }
            .frame(width: 118, alignment: .leading)
            Text(segment.text)
                .font(UI.sans(15))
                .lineSpacing(6)
                .textSelection(.enabled)
                .frame(maxWidth: 560, alignment: .leading)
        }
    }
}

/// Lecteur de l'enregistrement d'origine : lecture, position, durée.
private struct PlayerBar: View {
    @ObservedObject var player: AudioPlayerModel
    var id: String
    var urls: [URL]
    /// Durée connue de la transcription, affichée tant que l'audio n'est pas ouvert.
    var length: TimeInterval
    @State private var hovering = false

    private var active: Bool { player.isLoaded(id) }
    private var playing: Bool { active && player.isPlaying }
    private var progress: Double {
        guard active, player.duration > 0 else { return 0 }
        return min(1, player.currentTime / player.duration)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { player.toggle(id: id, urls: urls) }) {
                Icon(playing ? .pause : .play, size: 14, filled: true)
                    .foregroundStyle(UI.onText)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(UI.text))
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle(scale: 0.9))
            .keyboardShortcut(.space, modifiers: [])
            .help("Écouter l'enregistrement")
            .animation(UI.spring, value: playing)

            Text(Format.clock(active ? player.currentTime : 0))
                .font(UI.mono(11.5))
                .foregroundStyle(UI.text2)
                .frame(width: 40, alignment: .trailing)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(UI.active).frame(height: hovering ? 6 : 4)
                    Capsule().fill(UI.text).frame(width: max(4, proxy.size.width * progress), height: hovering ? 6 : 4)
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .frame(width: 12, height: 12)
                        .offset(x: max(0, proxy.size.width * progress - 6))
                        .opacity(hovering || playing ? 1 : 0)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        guard proxy.size.width > 0 else { return }
                        player.seek(id: id, urls: urls, fraction: Double(max(0, min(1, value.location.x / proxy.size.width))))
                    }
                )
            }
            .frame(height: 20)
            .onHover { hovering = $0 }
            .animation(UI.quick, value: hovering)

            Text(Format.clock(active ? player.duration : length))
                .font(UI.mono(11.5))
                .foregroundStyle(UI.text2)
                .frame(width: 40, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(UI.card))
        .overlay(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).strokeBorder(UI.line, lineWidth: 1))
    }
}

// MARK: - Vocabulaire

struct VocabularyPage: View {
    @ObservedObject var settings: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: "Vocabulaire",
                    subtitle: "Les mots que le modèle écrit mal, et ce qu'il faut écrire à la place."
                ) {
                    PlumeButton(title: "Ajouter", icon: .plus, kind: .primary) {
                        withAnimation(UI.spring) { settings.addReplacement() }
                    }
                }
                .rise(0)

                Card(padding: 6) {
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            Text("Entendu").frame(maxWidth: .infinity, alignment: .leading)
                            Spacer().frame(width: 14)
                            Text("Écrit").frame(maxWidth: .infinity, alignment: .leading)
                            Spacer().frame(width: 24)
                        }
                        .font(UI.sans(12, .medium))
                        .foregroundStyle(UI.text2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                        if settings.replacements.isEmpty {
                            Rectangle().fill(UI.line).frame(height: 1)
                            Text("Aucun remplacement pour l'instant.")
                                .font(UI.sans(13))
                                .foregroundStyle(UI.text2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        ForEach($settings.replacements) { $item in
                            VStack(spacing: 0) {
                                Rectangle().fill(UI.line).frame(height: 1)
                                HStack(spacing: 10) {
                                    TextField("ce que tu dis", text: $item.original)
                                        .textFieldStyle(.plain)
                                        .frame(maxWidth: .infinity)
                                    Icon(.arrowRight, size: 13)
                                        .foregroundStyle(UI.text3)
                                        .frame(width: 14)
                                    TextField("ce qui doit s'écrire", text: $item.with)
                                        .textFieldStyle(.plain)
                                        .frame(maxWidth: .infinity)
                                    Button {
                                        Sounds.play(.toggleOff)
                                        withAnimation(UI.spring) { settings.replacements.removeAll { $0.id == item.id } }
                                    } label: {
                                        Icon(.x, size: 12)
                                            .foregroundStyle(UI.text3)
                                            .frame(width: 24, height: 24)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PressStyle())
                                    .help("Supprimer")
                                }
                                .font(UI.sans(14))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                            }
                            .transition(.opacity.combined(with: .offset(y: -6)))
                        }
                    }
                }
                .rise(1)

                Text("Le remplacement se fait sur des mots entiers, sans tenir compte des majuscules, à la fin de chaque dictée ou réunion.")
                    .font(UI.sans(13))
                    .foregroundStyle(UI.text2)
                    .rise(2)
            }
            .padding(.horizontal, UI.pagePadding)
            .padding(.top, 58)
            .padding(.bottom, UI.dockClearance)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Réglages

struct SettingsPage: View {
    @ObservedObject var settings: SettingsModel
    @ObservedObject private var updates = Updates.shared
    private let refresh = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Réglages").rise(0)

                SettingsSection("Raccourcis", footer: "Appui bref : démarrer, puis arrêter. Maintenir le raccourci de dictée : parler tant qu'il est tenu. Échap annule une dictée.") {
                    SettingRow("Dicter") {
                        ShortcutRecorder(shortcut: $settings.dictationShortcut, onRecording: settings.onRecordingShortcut)
                    }
                    SettingRow("Enregistrer une réunion", detail: "Le mode réunion s'active aussi en survolant l'encoche.") {
                        ShortcutRecorder(shortcut: $settings.meetingShortcut, optional: true, onRecording: settings.onRecordingShortcut)
                    }
                    SettingRow("Ouvrir Plume") {
                        ShortcutRecorder(shortcut: $settings.openShortcut, optional: true, onRecording: settings.onRecordingShortcut)
                    }
                }
                .rise(1)

                SettingsSection(
                    "Micro",
                    footer: settings.chosenMicrophoneMissing
                        ? "Le micro choisi n'est pas branché : en attendant, Plume utilise celui du Mac."
                        : "Plume garde ce micro quoi qu'il arrive : connecter des écouteurs ou un casque Bluetooth n'y change rien."
                ) {
                    SettingRow("Micro utilisé") {
                        Picker("", selection: $settings.microphoneUID) {
                            Text(settings.microphones.first(where: \.isBuiltIn).map { "\($0.name) (par défaut)" } ?? "Micro du Mac (par défaut)")
                                .tag("")
                            ForEach(settings.microphones.filter { !$0.isBuiltIn }) { device in
                                Text(device.isBluetooth ? "\(device.name) (Bluetooth)" : device.name).tag(device.uid)
                            }
                            if settings.chosenMicrophoneMissing {
                                Text("Micro choisi (non branché)").tag(settings.microphoneUID)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 270)
                    }
                }
                .rise(2)

                SettingsSection("Encoche") {
                    SettingToggle("Afficher les mots en direct", detail: "Le texte défile sous l'encoche pendant que tu parles.", isOn: $settings.liveTranscript)
                    SettingToggle("Proposer le mode réunion au démarrage", detail: "Le choix dictée / réunion s'affiche six secondes. Sinon, il apparaît au survol de l'encoche.", isOn: $settings.modeSwitchAtStart)
                }
                .rise(2)

                SettingsSection("Sons", footer: "Un son doux au début et à la fin de chaque enregistrement, et une note discrète sur les gestes dans cette fenêtre.") {
                    SettingToggle("Sons de Plume", isOn: $settings.sounds)
                    SettingRow("Pack de sons", detail: "Les sons de début et de fin d'enregistrement.") {
                        Picker("", selection: $settings.soundPack) {
                            ForEach(SoundPack.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                        // On fait entendre le pack choisi.
                        .onChange(of: settings.soundPack) { _, _ in Sounds.play(.start) }
                        .disabled(!settings.sounds)
                    }
                    SettingRow("Volume") {
                        HStack(spacing: 8) {
                            Icon(.volume, size: 14).foregroundStyle(UI.text2)
                            Slider(value: $settings.soundVolume, in: 0.1...1) { editing in
                                // Au relâchement, le son de début : c'est lui qu'on règle.
                                if !editing { Sounds.play(.start) }
                            }
                            .controlSize(.small)
                            .tint(UI.text)
                            .frame(width: 150)
                            // Un cran sonne à chaque quatorzième de la course, de plus en plus haut.
                            .onChange(of: Int((settings.soundVolume - 0.1) / 0.9 * 14)) { _, notch in
                                Sounds.play(.sliderStep(notch * 8 / 14))
                            }
                            Icon(.volumeHigh, size: 14).foregroundStyle(UI.text2)
                        }
                        .disabled(!settings.sounds)
                    }
                }
                .rise(3)

                SettingsSection("Dictée") {
                    SettingToggle("Coller dans le champ actif à la fin", isOn: $settings.pasteAfterDictation)
                    SettingToggle("Rétablir le presse-papiers après le collage", isOn: $settings.restoreClipboard)
                        .disabled(!settings.pasteAfterDictation)
                    SettingToggle("Retirer les hésitations et les mots répétés", isOn: $settings.cleanup)
                }
                .rise(3)

                SettingsSection("Réunion") {
                    SettingToggle(
                        "Capter aussi le son de l'ordinateur",
                        detail: "Les autres participants (Meet, Zoom, Teams…) sont transcrits même au casque, et chaque interlocuteur est séparé. Sans casque, l'écho des haut-parleurs est retiré du micro.",
                        isOn: $settings.systemAudio)
                }
                .rise(4)

                SettingsSection("Bibliothèque") {
                    SettingRow("Dossier", detail: (settings.libraryPath as NSString).abbreviatingWithTildeInPath) {
                        PlumeButton(title: "Modifier…") { settings.chooseLibrary() }
                    }
                    SettingToggle("Conserver l'enregistrement audio", detail: "Pour réécouter chaque dictée et chaque réunion depuis l'historique.", isOn: $settings.keepAudio)
                }

                SettingsSection("Général") {
                    SettingRow("Apparence") {
                        Picker("", selection: $settings.appearance) {
                            Text("Sombre").tag("sombre")
                            Text("Claire").tag("clair")
                            Text("Comme le système").tag("systeme")
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                    SettingRow("Modèle de transcription") {
                        Picker("", selection: $settings.model) {
                            ForEach(EngineModel.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 230)
                    }
                    SettingToggle(
                        "Ouvrir Plume à la connexion",
                        isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
                }

                SettingsSection(
                    "Accès pour une IA",
                    footer: settings.integrationMessage
                        ?? "Un assistant peut lire tes transcriptions : par le dossier de la bibliothèque, par la commande plume, ou par le serveur MCP de Plume."
                ) {
                    SettingRow(
                        "Commande plume",
                        detail: !settings.commandInstalled
                            ? "plume last, plume search… dans un terminal."
                            : (settings.commandOnPath
                                ? "Installée dans ~/.local/bin."
                                : "Installée dans ~/.local/bin — ajoute ce dossier à ton PATH pour l'appeler par son nom.")
                    ) {
                        LinkState(done: settings.commandInstalled, action: "Installer") { settings.installCommand() }
                    }
                    SettingRow("Claude Code", detail: "Déclare le serveur MCP de Plume pour tous tes projets.") {
                        HStack(spacing: 6) {
                            if !settings.claudeCodeConnected {
                                PlumeButton(icon: .copy, help: "Copier la commande à lancer soi-même", sound: .confirm) {
                                    Paster.copy(Integrations.claudeCodeCommand)
                                }
                            }
                            if settings.connectingClaudeCode {
                                ProgressView().controlSize(.small)
                            } else {
                                LinkState(done: settings.claudeCodeConnected, action: "Connecter") { settings.connectClaudeCode() }
                            }
                        }
                    }
                    if Integrations.claudeDesktopPresent {
                        SettingRow("Claude Desktop", detail: "Ajoute Plume à sa configuration, sans toucher au reste.") {
                            LinkState(done: settings.claudeDesktopConnected, action: "Connecter") { settings.connectClaudeDesktop() }
                        }
                    }
                    SettingRow("Autre assistant", detail: "La configuration MCP à coller dans son fichier de réglages.") {
                        PlumeButton(title: "Copier", icon: .copy, sound: .confirm) { Paster.copy(Integrations.configuration) }
                    }
                }

                SettingsSection("À propos") {
                    SettingRow("Plume \(Updates.version)", detail: "Dictée et transcription locales : rien ne quitte ce Mac.") {
                        if updates.isAvailable {
                            PlumeButton(title: "Rechercher une mise à jour") { updates.check() }
                        }
                    }
                    if updates.isAvailable {
                        SettingToggle("Rechercher les mises à jour automatiquement", isOn: $updates.automatic)
                    }
                    SettingRow("Licences", detail: "Modèles, polices, icônes et bibliothèques utilisés par Plume.") {
                        PlumeButton(title: "Afficher") {
                            if let url = Bundle.main.url(forResource: "LICENCES", withExtension: "md") { NSWorkspace.shared.open(url) }
                        }
                    }
                }

                SettingsSection("Autorisations") {
                    PermissionRow(title: "Microphone", detail: "Pour entendre ta voix.", granted: settings.microphoneGranted, action: settings.requestMicrophone)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    PermissionRow(title: "Accessibilité", detail: "Pour coller le texte dans le champ actif.", granted: settings.accessibilityGranted, action: settings.requestAccessibility)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    SettingRow("Enregistrement audio du système", detail: "Demandée à la première réunion, pour capter le son de l'ordinateur.") {
                        PlumeButton(title: "Ouvrir les réglages") { Permissions.openSettings(.audioCapture) }
                    }
                }
            }
            .padding(.horizontal, UI.pagePadding)
            .padding(.top, 58)
            .padding(.bottom, UI.dockClearance)
            .frame(maxWidth: 740, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onReceive(refresh) { _ in
            settings.refreshPermissions()
            settings.refreshMicrophones()
        }
        .onAppear {
            settings.refreshMicrophones()
            settings.refreshIntegrations()
        }
    }
}

/// État d'un lien avec l'extérieur : un bouton pour l'établir, une coche une fois fait.
private struct LinkState: View {
    var done: Bool
    var action: String
    var perform: () -> Void

    var body: some View {
        if done {
            HStack(spacing: 6) {
                Icon(.circleCheck, size: 15)
                Text("Fait").font(UI.sans(13, .medium))
            }
            .foregroundStyle(UI.success)
            .frame(height: 30)
            .transition(.scale.combined(with: .opacity))
        } else {
            PlumeButton(title: action, kind: .primary, action: perform)
        }
    }
}

/// Un groupe de réglages : un titre, une carte dont les lignes sont séparées d'un filet.
private struct SettingsSection<Content: View>: View {
    var title: String
    var footer: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(UI.sans(14, .medium))
            Card(padding: 0) {
                // Un filet entre chaque ligne de la section.
                VStack(spacing: 0) {
                    Group(subviews: content()) { rows in
                        ForEach(rows) { row in
                            row
                            if row.id != rows.last?.id {
                                Rectangle().fill(UI.line).frame(height: 1).padding(.leading, 14)
                            }
                        }
                    }
                }
            }
            if let footer {
                Text(footer).font(UI.sans(13)).foregroundStyle(UI.text2)
            }
        }
    }
}

private struct SettingRow<Control: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var control: () -> Control

    init(_ title: String, detail: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(UI.sans(14))
                if let detail {
                    Text(detail)
                        .font(UI.sans(13))
                        .foregroundStyle(UI.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

private struct SettingToggle: View {
    var title: String
    var detail: String?
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var enabled

    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        SettingRow(title, detail: detail) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(PlumeSwitch())
        }
        .opacity(enabled ? 1 : 0.45)
    }
}

/// Capte un raccourci : une touche avec modificateurs, ou au moins deux modificateurs
/// seuls (⌃⇧).
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    var optional = false
    var onRecording: (Bool) -> Void = { _ in }

    @State private var recording = false
    @State private var monitor: Any?
    @State private var heldMask = 0

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { recording ? finish(nil) : begin() }) {
                Group {
                    if recording {
                        Text("Tape le raccourci…").foregroundStyle(UI.text)
                    } else if shortcut.isEmpty {
                        Text(HotkeyManager.describe(shortcut)).foregroundStyle(UI.text2)
                    } else {
                        Keycaps(shortcut: HotkeyManager.describe(shortcut))
                    }
                }
                .font(UI.sans(13, .medium))
                .padding(.horizontal, 10)
                .frame(minWidth: 86)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: UI.radius, style: .continuous).fill(recording ? UI.selected : UI.hover))
                .overlay(
                    RoundedRectangle(cornerRadius: UI.radius, style: .continuous)
                        .strokeBorder(UI.text.opacity(recording ? 0.6 : 0), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .animation(UI.quick, value: recording)
            if optional, !shortcut.isEmpty, !recording {
                Button(action: { shortcut = .none }) {
                    Icon(.circleX, size: 14).foregroundStyle(UI.text3)
                }
                .buttonStyle(PressStyle())
                .help("Retirer ce raccourci")
            }
        }
        .onDisappear { finish(nil) }
    }

    private func begin() {
        recording = true
        heldMask = 0
        onRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let mask = HotkeyManager.mask(from: event.modifierFlags)
            if event.type == .keyDown {
                if event.keyCode == 53 {  // Échap : on garde l'ancien raccourci
                    finish(nil)
                } else if mask != 0 || (96...122).contains(Int(event.keyCode)) {
                    finish(Shortcut(keyCode: Int(event.keyCode), modifiers: mask))
                }
                return nil
            }
            if mask == 0 {
                // Tout est relâché : un accord d'au moins deux modificateurs est valide.
                if heldMask.nonzeroBitCount >= 2 { finish(Shortcut(keyCode: nil, modifiers: heldMask)) }
                heldMask = 0
            } else {
                heldMask |= mask
            }
            return nil
        }
    }

    private func finish(_ new: Shortcut?) {
        guard recording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        onRecording(false)
        if let new { shortcut = new }
    }
}
