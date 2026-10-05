# Développer Plume

Compiler, tester, comprendre le code et publier une version. Pour contribuer, voir aussi
[CONTRIBUTING.md](../CONTRIBUTING.md).

## Commandes

```sh
./scripts/build.sh             # compile et assemble build/Plume.app
./scripts/build.sh --install   # … puis installe dans /Applications et relance
./scripts/test.sh              # tests de la logique
./scripts/release.sh 1.0.1     # version publiable, ou pour testeurs (voir docs/PUBLIER.md)
./scripts/icon.sh              # refait l'icône de l'app à partir de Resources/Icone.jpg
```

Aucun Xcode requis : SwiftPM et les Command Line Tools suffisent. Il faut un Mac Apple
Silicon sous macOS 15 ou plus récent.

Avec le SDK macOS 27, les macros de SwiftUI (`@State`) ne sont livrées qu'avec Xcode : sans lui,
les scripts se rabattent tout seuls sur un SDK macOS 26 installé (`scripts/sdk.sh`). Pour un
`swift build` lancé à la main :
`SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift build -c release`.

## Carte du code

```
Sources/PlumeKit/      cœur indépendant de l'interface (réutilisable pour une app iOS)
  Engine.swift           moteur local : transcription + séparation des voix (FluidAudio / CoreML)
  LiveTranscriber.swift  transcription en direct par fenêtre glissante
  Pipeline.swift         traitement final : dictée, réunion multi-canaux, empreinte vocale
  TranscriptBuilder.swift mots horodatés + diarisation → tours de parole
  TextCleanup.swift      nettoyage léger (hésitations, mots bégayés)
  Replacements.swift     vocabulaire : remplacements de mots
  Library.swift          bibliothèque sur disque (md + json + index)
  Stats.swift            chiffres de la page d'accueil
  Recovery.swift         reprise des enregistrements interrompus
  Importer.swift         transcription d'un fichier existant
Sources/Plume/         l'app macOS
  SessionController.swift chef d'orchestre d'un enregistrement (dont la bascule dictée ↔ réunion)
  AudioCapture.swift     micro et son système, lus directement par Core Audio
  AudioDevices.swift     liste des micros, choix de celui à utiliser
  Hotkeys.swift          raccourcis globaux
  Island.swift           l'île de l'encoche
  Sounds.swift           les sons : synthèse (kit « Bois ») et packs enregistrés
  Design.swift           couleurs, typographie (Geist, Geist Mono), composants et mouvements
  Icons.swift            icônes du portfolio (Lucide au trait de 1,6) et lecteur de tracés SVG
  Updates.swift          mises à jour automatiques (Sparkle)
  Integrations.swift     commande `plume`, connexion à Claude Code et Claude Desktop
  AppShell.swift, AppPages.swift, AppModels.swift   la fenêtre : accueil, historique, vocabulaire, réglages
  AppDelegate.swift      barre de menus, fenêtre, câblage
  MCPServer.swift, CLI.swift, Remote.swift, Doctor.swift   côté IA et scripts
```

## Publier

`./scripts/release.sh <version>` fabrique l'app signée (et notarisée, une fois le compte Apple
Developer en place), l'image disque et le flux de mises à jour ; `./scripts/publish.sh
<version>` les met en ligne dans les releases de ce dépôt. Les mises à jour
automatiques passent par Sparkle. Marche à suivre complète : [PUBLIER.md](PUBLIER.md).

## Changer ou mettre à jour le modèle

Le modèle se choisit dans Réglages. Pour profiter d'un nouveau modèle publié par FluidAudio :
monter la version dans `Package.swift`, ajouter un cas à `EngineModel` (`Engine.swift`), puis
`./scripts/build.sh --install`. Les modèles sont mis en cache dans
`~/Library/Application Support/FluidAudio/Models`.

## Essais sans micro

Des variables d'environnement rejouent des fichiers à la place des entrées réelles, sur un
canal de commande séparé de l'app installée :

```sh
export PLUME_LIBRARY=/tmp/essai PLUME_CHANNEL=essai PLUME_HEADLESS=1   # invisible, sans raccourcis
PLUME_FAKE_MIC=moi.wav PLUME_FAKE_SYSTEM=eux.wav PLUME_NO_PASTE=1 PLUME_VERBOSE=1 .build/release/Plume &
.build/release/Plume toggle dictee    # démarre
.build/release/Plume toggle reunion   # passe en réunion
.build/release/Plume stop
```

`plume transcribe micro.wav --system ordinateur.wav` traite une réunion à deux canaux à
partir de deux fichiers ; `plume aec micro.wav ordinateur.wav propre.wav` isole l'annulation
d'écho. `plume live fichier.wav` rejoue un fichier dans la transcription en direct ;
`plume diarize fichier.wav` affiche les voix détectées ; `plume render dossier/` produit des
aperçus PNG de l'interface. Le journal de l'app est dans `~/Library/Logs/Plume/plume.log`.

## Captures pour le README

`plume render <dossier> --demo` dessine l'interface hors écran avec une bibliothèque inventée et
un prénom fictif : rien de personnel n'apparaît. Les images du README sont dans `docs/assets/`.
Sans `--demo`, le rendu montre ta vraie bibliothèque : ne le publie pas.
