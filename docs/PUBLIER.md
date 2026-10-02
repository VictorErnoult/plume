# Publier Plume

Plume se distribue hors du Mac App Store : une image disque `.dmg` signée et notarisée,
hébergée sur les « releases » d'un dépôt GitHub public, avec des mises à jour automatiques
(Sparkle). Aucun Xcode n'est nécessaire : les Command Line Tools suffisent.

## Avant le compte Apple : versions d'essai

Le dépôt est `soyAkil/plume` (`PLUME_REPO` dans `scripts/release.env`). Tant que
`PLUME_IDENTITY` est vide :

```sh
./scripts/release.sh 0.9.1     # → dist/mises-a-jour/Plume-0.9.1.dmg et appcast.xml
./scripts/publish.sh 0.9.1     # met en ligne sur GitHub
```

L'app est signée avec le certificat local (`Plume Local Signing`, trousseau
`plume-signing.keychain-db`), non notarisée, mais avec les mises à jour automatiques. Le
`.dmg` contient un `Lisez-moi.txt` qui explique comment passer le blocage de macOS à la
première ouverture (Réglages Système › Confidentialité et sécurité › « Ouvrir quand même »).

Sparkle accepte de changer *soit* la clé des mises à jour, *soit* le certificat de signature
d'une version à l'autre, jamais les deux à la fois : on peut donc passer au certificat
Developer ID plus tard sans perdre les testeurs. Il faut en revanche garder la clé des mises
à jour (voir plus bas) et, jusqu'au passage à Developer ID, le trousseau
`~/Library/Keychains/plume-signing.keychain-db`.

Sans `PLUME_REPO`, `release.sh` fabrique une version sans mises à jour, rangée dans
`dist/essai`.

## Une fois pour toutes

1. **Compte Apple Developer** (99 €/an) sur developer.apple.com.
2. **Certificat « Developer ID Application »** : dans Trousseaux d'accès, *Assistant de
   certification › Demander un certificat à une autorité* (enregistrer la demande sur le
   disque) ; sur developer.apple.com, *Certificates › + › Developer ID Application*, y déposer
   la demande, télécharger le certificat et l'ouvrir. `security find-identity -v -p codesigning`
   doit alors afficher une ligne `Developer ID Application: Nom (ÉQUIPE)` : c'est la valeur de
   `PLUME_IDENTITY` dans `scripts/release.env`.
3. **Notarisation** : créer un mot de passe d'app sur account.apple.com, puis
   `xcrun notarytool store-credentials plume-notary --apple-id <adresse> --team-id <ÉQUIPE> --password <mot de passe d'app>`.
4. **Dépôt GitHub public** : `soyAkil/plume`, déjà inscrit dans `PLUME_REPO`. L'adresse du
   flux de mises à jour est inscrite dans chaque app publiée : on ne change plus de dépôt
   ensuite sans laisser les anciennes versions sans mises à jour.
5. **Clé des mises à jour** : déjà créée (trousseau, « Private key for signing Sparkle
   updates » ; partie publique dans `scripts/release.env`). La sauvegarder :
   `.build/artifacts/sparkle/Sparkle/bin/generate_keys -x cle-plume.txt`, ranger le fichier
   dans un gestionnaire de mots de passe, puis l'effacer du disque. Sans elle, plus aucune
   mise à jour ne peut être publiée.

## À chaque version

```sh
# facultatif : notes de version, affichées dans la fenêtre de mise à jour
$EDITOR notes/1.0.1.md
./scripts/release.sh 1.0.1   # compile, signe, notarise, fabrique le .dmg et le flux
./scripts/publish.sh 1.0.1   # met en ligne sur GitHub
```

`release.sh` ne met rien en ligne. Il produit `dist/mises-a-jour/Plume-1.0.1.dmg` et
`appcast.xml` (le flux, signé avec la clé du trousseau). Garder le dossier
`dist/mises-a-jour` d'une version à l'autre : le flux s'y complète.

Lien de téléchargement permanent, à mettre sur le site :
`https://github.com/<dépôt>/releases/latest/download/Plume.dmg`

## Ce qui a été vérifié, et ce qui ne l'est pas encore

Vérifié sur ce Mac, avec la signature locale (`PLUME_IDENTITY` vide = mode essai) :
l'assemblage, la signature sous « hardened runtime », le micro réel et une dictée dans l'app
ainsi signée, la fabrication du `.dmg` et du flux, et une mise à jour de bout en bout
(une app 0.9.0 trouve la 1.0.0, la télécharge, vérifie sa signature, l'installe).

Pas encore vérifié, faute de compte Apple : la signature Developer ID, la notarisation, et
l'ouverture du `.dmg` sur un autre Mac.

### Refaire l'essai de mise à jour

```sh
T=/tmp/essai-maj
export PLUME_FEED_URL=http://127.0.0.1:8765/appcast.xml PLUME_DOWNLOAD_PREFIX=http://127.0.0.1:8765/
PLUME_DIST=$T/ancienne PLUME_BUILD=1 ./scripts/release.sh 0.9.0
PLUME_DIST=$T/nouvelle PLUME_BUILD=2 ./scripts/release.sh 1.0.0
(cd $T/nouvelle/mises-a-jour && python3 -m http.server 8765 --bind 127.0.0.1 &)
PLUME_CHANNEL=essai PLUME_HEADLESS=1 PLUME_UPDATES=1 $T/ancienne/Plume.app/Contents/MacOS/Plume &
# quelques secondes plus tard, l'app d'essai est en 1.0.0 :
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $T/ancienne/Plume.app/Contents/Info.plist
grep "mise à jour" ~/Library/Logs/Plume/plume.log | tail -3
```

## Crédits à afficher

`Resources/LICENCES.md` (ouvert depuis Réglages › À propos) liste les modèles, bibliothèques,
polices et icônes avec leur licence. Les modèles sont sous CC BY 4.0 ou Apache 2.0 :
l'attribution est obligatoire, l'usage et la diffusion sont libres. Reprendre ces crédits sur
la page de téléchargement.
