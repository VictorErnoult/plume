import AppKit
import PlumeKit

let arguments = CommandLine.arguments

if CLI.handles(arguments) {
    // Mode ligne de commande : pas d'interface, on sort avec le code de la commande.
    // Les bibliothèques de modèles écrivent des traces sur la sortie standard : on les
    // renvoie vers la sortie d'erreur pour que seul notre résultat reste sur stdout.
    CLI.isolateStandardOutput()
    Task.detached {
        let code = await CLI.run(arguments)
        exit(code)
    }
    // Boucle d'événements sur le vrai thread principal (AppKit en a besoin pour `render`).
    while true { RunLoop.main.run(mode: .default, before: .distantFuture) }
} else {
    // Une seule instance : si Plume tourne déjà, on la laisse faire. Une instance d'essai,
    // sur son propre canal de commande, peut tourner à côté.
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: PlumeSettings.bundleID)
        .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    let trial = ProcessInfo.processInfo.environment["PLUME_CHANNEL"] != nil
    if Bundle.main.bundleIdentifier == PlumeSettings.bundleID, !others.isEmpty, !trial {
        others.first?.activate()
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.delegate = delegate
    app.run()
}
