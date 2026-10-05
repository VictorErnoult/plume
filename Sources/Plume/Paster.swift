import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Insère le texte dans le champ actif : presse-papiers + ⌘V simulé, puis restauration.
enum Paster {
    /// Convention nspasteboard.org : contenu éphémère, à ne pas garder dans un historique.
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// macOS n'autorise la simulation de touches qu'aux apps cochées dans « Accessibilité ».
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// - Parameter transient: le texte ne fait que passer. Il est écrit avec sa marque en une
    ///   seule fois : un gestionnaire qui lirait entre les deux le garderait sans la voir.
    static func copy(_ text: String, transient: Bool = false) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if transient { item.setData(Data(), forType: transientType) }
        pasteboard.writeObjects([item])
    }

    /// - Returns: `true` si le collage a été lancé, `false` si le texte est seulement copié
    ///   (autorisation Accessibilité manquante).
    @discardableResult
    static func paste(_ text: String, restoreClipboard: Bool) -> Bool {
        let pasteboard = NSPasteboard.general
        guard isTrusted else {
            copy(text)
            return false
        }
        let saved = restoreClipboard ? snapshot(pasteboard) : nil
        // Rétabli juste après : les gestionnaires de presse-papiers (Maccy, Raycast…) ne retiennent
        // pas un contenu marqué éphémère, la dictée ne s'ajoute pas à leur historique.
        copy(text, transient: saved != nil)
        let marker = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            postCommandV()
            guard let saved else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                // Si l'utilisateur a copié autre chose entre-temps, on ne touche à rien.
                guard pasteboard.changeCount == marker else { return }
                pasteboard.clearContents()
                if !saved.isEmpty { pasteboard.writeObjects(saved) }
            }
        }
        return true
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // La touche « V » n'est pas au même endroit sur toutes les dispositions (Bépo, Dvorak).
        let key = CGKeyCode((0..<50).first { HotkeyManager.keyName($0) == "V" } ?? kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
