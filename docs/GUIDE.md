# Guide d'utilisation

Tout ce que Plume sait faire, en détail. Pour l'essentiel, voir le [README](../README.md).

## Les gestes

| Geste | Effet |
|---|---|
| `⌃⇧` (appui bref) | Démarre un enregistrement. Second appui : le texte est collé dans le champ actif. |
| `⌃⇧` (maintenu) | Parle tant que les touches sont tenues ; relâche pour coller. |
| Survol de l'encoche | La touche **Réunion** (elle s'enclenche et reste allumée), annuler, terminer. |
| `⌃⇧⌘` | Démarre directement une réunion (ou y passe en cours de dictée). |
| `Échap` | Annule la dictée en cours. |
| Clic sur l'icône de la barre de menus | Ouvre la fenêtre de Plume (clic droit : menu court). |
| `1` `2` `3` `4`, `T`, `S` dans la fenêtre | Accueil, historique, vocabulaire, réglages ; thème clair / sombre ; sons. |

Les raccourcis se changent dans **Réglages**. Un raccourci peut être un accord de
modificateurs seuls (`⌃⇧`) ou une touche avec modificateurs (`⌥Espace`). Un accord ne se
déclenche que s'il est « propre » : `⌃⇧Tab` ou `⌃⇧` + clic ne lancent rien.

En mode réunion, Plume capte aussi le son de l'ordinateur, sépare les voix à la fin, et
range le dialogue dans l'historique au lieu de le coller. Sans casque, le son des
haut-parleurs repasse dans le micro : Plume le détecte et retire cet écho avant de
transcrire, sinon les voix distantes apparaîtraient en double et masqueraient la tienne.
Si les voix restent mal séparées, « Refaire la séparation des voix » (dans l'historique)
réécoute l'audio en imposant le nombre de personnes. « Moi » désigne ta voix : Plume
l'apprend à partir de tes dictées (une empreinte vocale stockée localement). Dans
l'historique, un clic sur un nom le renomme partout ; un clic sur un horodatage lance
l'écoute à cet endroit.

Plume n'écoute pas l'entrée audio par défaut du système mais le micro choisi dans
**Réglages › Micro** — par défaut celui du Mac. Connecter des écouteurs ou une enceinte
Bluetooth ne change donc rien ; pour dicter avec leur micro, il faut le choisir soi-même.

## Sons

Un son au début et à la fin de chaque enregistrement, au choix dans **Réglages › Sons ›
Pack de sons** : Pluck (par défaut), Bips, Clics, Mélodie, Glisse, ou Bois. Les packs sont des
sons enregistrés (`Resources/Sounds`), raccourcis et adoucis par l'app ; Bois est synthétisé à
la volée avec la recette du kit du portfolio (marimba très sobre, gamme pentatonique). Les
gestes dans la fenêtre (survols, onglets, interrupteurs) ont leurs propres notes synthétisées.
Volume et coupure dans **Réglages › Sons** ou avec la touche `S`. `plume sounds <dossier>`
écrit tous les sons en WAV, un sous-dossier par pack.

## Autorisations macOS

| Autorisation | Pourquoi | Quand |
|---|---|---|
| Microphone | T'entendre | Première dictée, ou depuis l'accueil |
| Accessibilité | Simuler ⌘V pour coller le texte | Depuis l'accueil ; sans elle le texte est seulement copié |
| Enregistrement audio du système | Capter le son de l'ordinateur en réunion | Première réunion |

L'app est signée avec un certificat local stable : les autorisations survivent aux mises à jour.

## La bibliothèque : `~/Plume`

```
~/Plume/
  LISEZMOI.md                          mode d'emploi du dossier, pour les IA
  dernier.md                           la transcription la plus récente
  index.jsonl                          une ligne JSON par transcription
  2026-10/
    2026-10-02_14-31-05_dictee.md      texte, avec en-tête (date, durée, interlocuteurs)
    2026-10-02_14-31-05_dictee.json    données complètes (segments horodatés, texte brut)
    2026-10-02_14-31-05_mic.m4a        audio d'origine (mic = micro, sys = son de l'ordinateur)
```

## Accès pour une IA

1. **Le dossier.** « Lis `~/Plume/dernier.md` » suffit à tout agent qui a accès aux fichiers.
2. **La ligne de commande** `plume` :
   ```sh
   plume last                 # dernière transcription
   plume last --mode reunion  # dernière réunion
   plume list -n 10           # les dix dernières
   plume search budget site   # recherche plein texte
   plume show 2026-10-02_14-31-05
   plume transcribe audio.m4a --mode reunion --save
   ```
   Ajoute `--json` pour une sortie structurée.
3. **Le serveur MCP** (`plume mcp`), déclaré dans Claude Code. Outils : `get_latest_transcript`,
   `list_transcripts`, `get_transcript`, `search_transcripts`.

`plume toggle dictee|reunion`, `plume stop`, `plume cancel` et `plume open` pilotent l'app
ouverte depuis un script, Raycast ou un Stream Deck. `plume doctor` affiche l'état des
autorisations, du modèle et des écrans.
