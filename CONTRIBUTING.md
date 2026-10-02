# Contribuer à Plume

Merci de passer par ici ! Plume est une petite app : toute aide compte, d'un signalement de
bug à une nouvelle fonctionnalité.

## Signaler un problème ou proposer une idée

Ouvre une [issue](https://github.com/soyAkil/plume/issues/new/choose) : un formulaire te
guide (bug ou idée). Si tu joins le journal de Plume, relis-le avant : il peut contenir des
extraits de tes dictées.

## Proposer une modification

1. Forke le dépôt et crée une branche (`git switch -c ma-fonctionnalite`).
2. Compile et essaie : `./scripts/build.sh --install` (Mac Apple Silicon, macOS 15+, Command
   Line Tools ; Xcode n'est pas nécessaire).
3. Lance les tests : `./scripts/test.sh`. La même vérification (compilation + tests) tourne
   automatiquement sur chaque pull request.
4. Ouvre une pull request qui explique le pourquoi du changement, avec une capture ou une
   courte vidéo si l'interface change.

Pour une grosse fonctionnalité, ouvre d'abord une issue : on en discute avant que tu y
passes du temps.

## Repères dans le code

- `Sources/PlumeKit` : le cœur, indépendant de l'interface (moteur, pipeline, bibliothèque).
- `Sources/Plume` : l'app macOS (île de l'encoche, fenêtre, raccourcis, sons, CLI, MCP).
- La carte complète des fichiers est dans [docs/DEVELOPPEMENT.md](docs/DEVELOPPEMENT.md#carte-du-code).

Le code, les commentaires et l'interface sont en français : garde ce style, et calque-toi
sur le code qui entoure ce que tu modifies.

## Idées pour commencer

- une app iOS qui réutilise `PlumeKit` (voir `docs/PLAN.md`) ;
- de nouveaux packs de sons (voir `SoundPack` dans `Sources/Plume/Sounds.swift`) ;
- la prise en charge d'autres modèles de transcription ;
- des traductions de l'interface.
