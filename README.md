# Keyla

Prototype d'application d'apprentissage du piano : les partitions deviennent des notes qui tombent, la difficulté s'adapte au niveau de l'élève, et le piano numérique est détecté en USB (Web MIDI).

**Utiliser l'app :** ouvrez la page GitHub Pages du dépôt.

- **Mac / PC** : Chrome, piano branché en USB.
- **Android** : Chrome, piano branché avec un câble USB OTG.
- **iPad / iPhone** : app « Web MIDI Browser » (Safari ne gère pas le MIDI).

Import de partitions au format MusicXML (`.musicxml`, `.mxl`) ou MIDI (`.mid`). Exemples : `exemple-deux-mains.musicxml`, `exemple-deux-mains.mid`.

## Morceaux intégrés

Traditionnels (Au clair de la lune, Frère Jacques, Ah ! vous dirai-je maman, Jingle Bells) et œuvres classiques
du domaine public (Beethoven : Ode à la joie, Lettre à Élise ; Pachelbel : Canon ; Petzold : Menuet en sol ;
Satie : Gymnopédie n°1 ; Bach : Prélude en do), transcrits et simplifiés spécialement pour l'app.
Les partitions importées par l'utilisateur restent sur son appareil et ne sont pas diffusées.

## Crédits

Son de piano : Salamander Grand Piano (Yamaha C5) par Alexander Holm, sous licence [Creative Commons BY 3.0](https://creativecommons.org/licenses/by/3.0/). Les 30 échantillons MP3 du dossier `sounds/piano` proviennent de la version distribuée par [Tone.js](https://github.com/Tonejs/audio).

Partition classique dessinée par [Verovio](https://www.verovio.org) (licence LGPL), chargé depuis jsDelivr.

## App iPad / iPhone (dossier `ios/`)

Petite app native qui ouvre le site en plein écran et branche le MIDI de l'appareil (CoreMIDI) sur la page :
plus besoin de Web MIDI Browser. Ouvrir `ios/PianoPasAPas.xcodeproj` dans Xcode, choisir son équipe
(Signing & Capabilities), brancher l'iPad et lancer. Avec un Apple ID gratuit, l'app est à réinstaller tous les 7 jours.
