import Foundation
import Testing

/// `./scripts/test.sh` et la CI mettent à part réglages, bibliothèque, dossier de support et
/// canal de commande. Sans eux, un test qui lirait les réglages ouvrirait ceux de l'app
/// installée (le lanceur des tests n'a pas l'identifiant de Plume) : un `swift test` nu échoue
/// donc exprès.
@Suite("Isolation des tests")
struct IsolationTests {
    @Test func lesTestsSontÀPartDeLAppInstallée() {
        let environment = ProcessInfo.processInfo.environment
        for name in ["PLUME_DEFAULTS", "PLUME_SUPPORT", "PLUME_LIBRARY", "PLUME_CHANNEL"] {
            #expect(environment[name]?.isEmpty == false, "\(name) manque : lancer ./scripts/test.sh")
        }
    }
}
