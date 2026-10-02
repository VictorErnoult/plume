<div align="center">

<img src="docs/assets/icone.png" width="128" alt="Icône de Plume">

# Plume

**Tu parles, ça s'écrit.** Dictée vocale et transcription de réunions pour Mac.<br>
Gratuit, open source, et 100 % sur ton Mac.

[![Dernière version](https://img.shields.io/github/v/release/soyAkil/plume?label=version&color=1f1f1f)](https://github.com/soyAkil/plume/releases/latest)
[![CI](https://github.com/soyAkil/plume/actions/workflows/ci.yml/badge.svg)](https://github.com/soyAkil/plume/actions/workflows/ci.yml)
[![Licence MIT](https://img.shields.io/badge/licence-MIT-1f1f1f)](LICENSE)

### [⬇︎ Télécharger Plume](https://github.com/soyAkil/plume/releases/latest/download/Plume.dmg)

<sub>Mac M1 ou plus récent · macOS 15 ou plus récent · se met à jour tout seul</sub>

<br>

<img src="docs/assets/encoche.png" width="560" alt="Plume dans l'encoche du Mac, pendant une réunion">

</div>

## Pourquoi Plume

- ⚡️ **Rapide** : 5 minutes de voix transcrites en moins de 2 secondes.
- 🔒 **Privé** : tout tourne sur ton Mac. Rien n'est envoyé nulle part, aucun compte.
- 🎙️ **Réunions** : Plume écoute ton micro *et* le son de l'ordi (Meet, Zoom, Teams…), puis
  sépare qui a dit quoi.
- ✍️ **En direct** : les mots apparaissent dans l'encoche pendant que tu parles.
- 🪶 **Léger** : il vit dans l'encoche et la barre de menus, et ne se montre que quand tu parles.
- 🤖 **Prêt pour l'IA** : tes transcriptions sont des fichiers texte, lisibles par Claude, ChatGPT
  et compagnie (dossier, ligne de commande, serveur MCP).

<p align="center">
  <img src="docs/assets/historique.png" width="800" alt="L'historique de Plume, avec une réunion à trois">
</p>

## Installer

1. [Télécharge Plume](https://github.com/soyAkil/plume/releases/latest/download/Plume.dmg) et glisse-le dans **Applications**.
2. La première fois, macOS le bloque (l'app n'est pas encore validée par Apple) : ouvre
   **Réglages Système › Confidentialité et sécurité**, puis **« Ouvrir quand même »**.
3. Autorise le micro (et l'accessibilité, pour que Plume colle le texte), et c'est parti. Le modèle de transcription (~600 Mo) se télécharge une
   seule fois.

## Utiliser

| | |
|---|---|
| `⌃` `⇧` | Lance la dictée. Encore `⌃` `⇧` : le texte se colle là où est ton curseur. |
| `⌃` `⇧` maintenus | Parle tant que tu tiens, lâche pour coller. |
| `⌃` `⇧` `⌘` | Lance une réunion. |
| `Échap` | Annule. |

Tout se règle dans la fenêtre de Plume (clic sur la plume dans la barre de menus) : raccourcis,
micro, sons, modèle. Le détail est dans le [guide](docs/GUIDE.md).

## Contribuer

Plume est jeune et toute aide est la bienvenue : bugs, idées, code, traductions.
Commence par [CONTRIBUTING.md](CONTRIBUTING.md), puis [docs/DEVELOPPEMENT.md](docs/DEVELOPPEMENT.md)
pour compiler en deux commandes (pas besoin de Xcode).

Pistes ouvertes : une app iPhone, d'autres modèles, de nouveaux packs de sons. Voir la
[feuille de route](docs/PLAN.md).

## Licence

Code sous licence [MIT](LICENSE). Polices, icônes, modèles et sons : voir
[Resources/LICENCES.md](Resources/LICENCES.md).
