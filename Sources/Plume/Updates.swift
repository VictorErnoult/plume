import AppKit
import Sparkle

/// Mises à jour automatiques de l'app distribuée (Sparkle). Le flux et la clé de signature
/// sont inscrits dans Info.plist par `scripts/release.sh` ; une compilation locale n'en a pas
/// et ne cherche donc jamais de mise à jour.
@MainActor
final class Updates: NSObject, ObservableObject, SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    static let shared = Updates()

    /// Version trouvée lors d'une vérification en arrière-plan, pas encore présentée.
    @Published private(set) var pending: String?
    @Published var automatic = true {
        didSet {
            if let updater = controller?.updater, updater.automaticallyChecksForUpdates != automatic {
                updater.automaticallyChecksForUpdates = automatic
            }
        }
    }

    private var controller: SPUStandardUpdaterController?

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    /// Vrai dans l'app distribuée, faux dans une compilation locale.
    var isAvailable: Bool { controller != nil }

    func start() {
        let info = Bundle.main.infoDictionary ?? [:]
        guard controller == nil, info["SUFeedURL"] != nil, info["SUPublicEDKey"] != nil else { return }
        guard !TestHooks.headless || TestHooks.updates else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        automatic = controller.updater.automaticallyChecksForUpdates
        // Essai sans interface : vérification immédiate. Le téléchargement automatique est
        // demandé par l'Info.plist de l'app d'essai, pas par un réglage, pour ne rien
        // écrire dans les préférences de l'app installée.
        if TestHooks.updates { controller.updater.checkForUpdatesInBackground() }
    }

    /// Vérification demandée par l'utilisateur : Sparkle montre le résultat, quel qu'il soit.
    func check() {
        guard let controller else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    // MARK: Journal

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Log.write("update: version \(item.displayVersionString) found")
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Log.write("update: nothing new")
    }

    nonisolated func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        Log.write("update: version \(item.displayVersionString) downloaded")
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        Log.write("update: installing version \(item.displayVersionString)")
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let error = error as NSError
        // 1001 : « déjà à jour », ce n'est pas un incident.
        if error.domain == SUSparkleErrorDomain, error.code == 1001 { return }
        Log.write("update: failed — \(error.localizedDescription)")
    }

    nonisolated func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        // En usage normal, l'installation attend que l'on quitte Plume.
        guard TestHooks.updates else { return false }
        immediateInstallHandler()
        return true
    }

    // MARK: Rappels discrets

    // Plume vit dans la barre de menus : une fenêtre de mise à jour qui surgit pendant qu'on
    // dicte ailleurs serait malvenue. Une mise à jour trouvée en arrière-plan s'annonce donc
    // par un simple bouton dans la fenêtre de Plume, et ne s'ouvre que si on le demande.

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        Task { @MainActor in
            if !handleShowingUpdate { self.pending = version }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor in self.pending = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in self.pending = nil }
    }
}
