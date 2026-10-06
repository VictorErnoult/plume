# Plume — consignes pour les assistants IA

Ce fichier s'adresse aux agents de code (Claude Code, Codex, Cursor…). Les humains trouveront
l'essentiel dans le README.

## Le projet

App macOS (barre de menus + « île » dans l'encoche) de dictée vocale et de transcription de
réunions, entièrement locale. Swift 6 (mode de langage 5), SwiftPM seul : **pas de projet
Xcode**, tout se compile avec les Command Line Tools. Mac Apple Silicon, macOS 15+.

- `Sources/PlumeKit/` : cœur sans interface (moteur FluidAudio/CoreML, pipeline, bibliothèque,
  réglages). Testé dans `Tests/PlumeKitTests`.
- `Sources/Plume/` : l'app (interface SwiftUI/AppKit, raccourcis, capture audio, sons, CLI,
  serveur MCP, mises à jour Sparkle). Ce qui s'en isole se teste dans `Tests/PlumeTests`.
- Carte fichier par fichier : `docs/DEVELOPPEMENT.md` ; choix techniques : `docs/PLAN.md` ;
  fonctionnalités : `docs/GUIDE.md` ; publication : `docs/PUBLIER.md`.

## Commandes

```sh
swift build -c release          # compile (sans Xcode, SDK macOS 27 : voir docs/DEVELOPPEMENT.md)
./scripts/test.sh               # tests (Swift Testing ; le script règle les chemins sans Xcode)
./scripts/build.sh --install    # app complète dans /Applications, relancée
.build/release/Plume doctor     # état des autorisations, du modèle, des écrans
.build/release/Plume render <dossier> --demo   # captures de l'interface, données inventées
```

Avant de dire qu'une modification marche : compiler, lancer les tests, et si l'interface
change, regarder un rendu `plume render … --demo`.

## Conventions

- Code, commentaires et messages **en français**. Les textes de l'interface s'écrivent en
  français dans le code, enveloppés dans `tr("…")`, avec leur traduction anglaise dans
  `PlumeKit/L10nTable.swift` : l'anglais est la langue par défaut de l'app, le français se
  choisit dans les réglages. Tutoiement en français. Commentaires en `///`, qui expliquent
  le pourquoi. Calque-toi sur le style du fichier.
- Pas de nouvelle dépendance sans en discuter dans une issue.
- Les réglages passent par `PlumeSettings` (PlumeKit) et `SettingsModel` (app).
- Les sons : `Sounds.swift` (synthèse) et `SoundPack` (packs enregistrés, `Resources/Sounds`).
- Variables d'environnement d'essai (`PLUME_LIBRARY`, `PLUME_DEFAULTS`, `PLUME_SUPPORT`,
  `PLUME_CHANNEL`, `PLUME_HEADLESS`, `PLUME_FAKE_MIC`, `PLUME_FAKE_SYSTEM`, `PLUME_FAKE_CALL`,
  `PLUME_NO_PASTE`, `PLUME_VERBOSE`…) : voir `docs/DEVELOPPEMENT.md`, section « Essais sans
  micro ». Elles permettent de tout tester sans toucher à l'app installée, à ses réglages ni à
  la vraie bibliothèque. Toujours mettre `PLUME_DEFAULTS` pour un essai : sans lui, le binaire
  de développement écrit dans les réglages de l'app installée.
- Chaque PR ajoute une ligne en haut de `CHANGELOG.md` :
  `- Domaine : effet, en quelques mots (#numéro)`, sous le `### <date>` du jour (à créer s'il
  manque). L'effet, pas la façon ; une PR sans effet notable (coquille, refacto) n'en ajoute
  pas. La ligne va dans la version du haut tant qu'elle n'est pas publiée (pas de tag
  `v<version>`) ; sinon, dans une nouvelle section `## <version suivante>`. On publie la
  version du haut, et son titre prend alors la date de publication : `## <version> — <date>`.

## Tests

Toujours `./scripts/test.sh`, jamais `swift test` seul (la CI lance `swift test` avec les mêmes
variables) : le script met à part réglages, bibliothèque, dossier de support et canal de
commande. Tout passe en quelques secondes, sans modèle ni micro ; la CI fait de même à chaque
push et à chaque PR, et `scripts/release.sh` s'arrête si un test échoue. Un changement de
comportement ajoute ou adapte un test ; une correction de bug commence par un test qui échoue.

Ce qu'on teste :
- Ce dont dépendent l'utilisateur et les scripts (fichiers enregistrés, sorties de la ligne de
  commande et du serveur MCP, texte d'une dictée, presse-papiers), pas la mise en page.
- La logique se teste seule : dans PlumeKit, ou dans une fonction qui reçoit ses dépendances ;
  les vues restent minces. Le code de l'app se teste dans `Tests/PlumeTests`
  (`@testable import Plume`). Quand un changement de comportement touche une logique de l'app
  qui s'isole en une fonction sans déplacer le reste, on l'isole avec son test ; sinon, on ne
  force pas.
- Fichiers enregistrés (transcriptions, annulés, vocabulaire, règles, empreinte vocale,
  sauvegarde des réglages) : un fichier écrit par une version publiée doit se relire sans rien
  perdre. Un nouveau champ est optionnel (`T?`), ou lu par `decodeIfPresent(…) ?? valeur` dans
  un `init(from:)` écrit à la main, comme `AppRule` ; une valeur par défaut sur la propriété ne
  suffit pas. Ne jamais retoucher un échantillon de `Tests/Fixtures/` : un changement de format
  ajoute le dossier de la version qui le publie
  (`FIXTURES_VERSION=<version> ./scripts/test.sh --filter FixtureGenerator`) ; celui d'une
  version pas encore publiée (sans tag `v<version>`) se supprime et se régénère. Un champ ou un
  réglage retiré exprès s'inscrit dans `removedOnPurpose` (`SavedFormatTests`), avec sa ligne
  de `CHANGELOG.md`.
- Ligne de commande (`--json`), outils du serveur MCP, `index.jsonl` et `dernier.md` : des
  scripts et des IA les lisent. Ajouter une clé ou un outil, oui ; en renommer ou en retirer un
  les casse : à noter dans `CHANGELOG.md` et `docs/GUIDE.md`, et à refléter dans les tests
  (`CommandLineTests`, `MCPServerTests` ; le binaire ne se lance que par `PlumeBinary.run`).
- Texte des dictées (nettoyage, commandes vocales, vocabulaire, styles) : chaque correction ou
  nouvelle commande ajoute des lignes au tableau `DictationCorpusTests`, le cas traité et la
  phrase ordinaire la plus proche, qui ne doit pas bouger. Un défaut connu s'y note avec
  `withKnownIssue`, autour de la seule attente qui échoue.

Pour que les tests restent sûrs et fiables :
- Jamais les vraies données. Dans un test : des dossiers temporaires ; pas de
  `PlumeSettings.shared`, ni directement, ni par un paramètre `settings:` laissé à sa valeur par
  défaut, ni par `SettingsModel` ; pas de `load`/`save` de `ReplacementStore`, `AppRuleStore` ou
  `VoiceprintStore` (leurs fonctions pures et `read(from:)`/`write(_:to:)` restent permises) ;
  `replacements:` toujours explicite avec `Pipeline.format` ; pas de `TranscriptStore.delete`
  (vraie corbeille).
- Pas le presse-papiers général (un presse-papiers nommé, libéré à la fin), pas d'événement
  clavier, pas de `Remote.send`. Le binaire ne se lance qu'avec une commande de lecture
  (`path`, `last`, `list`, `show`, `search`, `export` sans `-o`, `mcp` sans ses outils `listen` et
  `summarize_transcript`) : sans argument ou avec une commande inconnue, il lance l'app.
- Rien d'implicite : ni l'heure, ni le fuseau, ni la disposition du clavier, ni la langue de
  l'interface. On passe les dates ; pour la langue, `L10n.$override.withValue(.english) { … }`,
  jamais `L10n.current = …` (les tests tournent en parallèle).

## À ne jamais faire

- Committer un enregistrement, une transcription ou le contenu de `~/Plume` : ce sont des
  données personnelles. Les tests utilisent des phrases inventées.
- Publier un rendu `plume render` sans `--demo` : il montre la vraie bibliothèque.
- Modifier `scripts/release.env` (dépôt, clé publique des mises à jour) ou l'identifiant
  `studio.brigode.plume` : les apps déjà installées ne recevraient plus de mises à jour.
- Lancer `scripts/release.sh` ou `scripts/publish.sh` sans qu'on te le demande : ils signent
  et mettent en ligne une version.
