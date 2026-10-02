# Plume — crédits et licences

Plume transcrit la voix sur ton Mac, sans rien envoyer ailleurs. Elle s'appuie sur des
modèles, des bibliothèques, des polices et des icônes publiés par d'autres. Les voici, avec
leur licence.

## Modèles

Ils ne sont pas inclus dans l'app : Plume les télécharge depuis Hugging Face au premier
lancement, dans `~/Library/Application Support/FluidAudio/Models`.

### Transcription — Parakeet Ultra

- Parakeet TDT 0.6b v3, © NVIDIA — https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
- post-entraîné par moondream (parakeet-ultra) — https://huggingface.co/moondream/parakeet-ultra
- converti pour Core ML (version modifiée) par Fluid Inference —
  https://huggingface.co/FluidInference/parakeet-ultra-coreml

Licence : Creative Commons Attribution 4.0 — https://creativecommons.org/licenses/by/4.0/

### Séparation des voix

- pyannote speaker-diarization-community-1 —
  https://huggingface.co/pyannote/speaker-diarization-community-1
- empreintes vocales WeSpeaker — https://github.com/wenet-e2e/wespeaker
- PLDA de BUT Speech@FIT
- convertis pour Core ML (versions modifiées) par Fluid Inference —
  https://huggingface.co/FluidInference/speaker-diarization-coreml

Licence : Creative Commons Attribution 4.0 — https://creativecommons.org/licenses/by/4.0/

Références :

- A. Plaquet, H. Bredin, « Powerset multi-class cross entropy loss for neural speaker
  diarization », Interspeech 2023.
- H. Wang et al., « WeSpeaker: A research and production oriented speaker embedding learning
  toolkit », ICASSP 2023.
- F. Landini, J. Profant, M. Diez, L. Burget, « Bayesian HMM clustering of x-vector sequences
  (VBx) in speaker diarization: theory, implementation and analysis on standard tasks »,
  Computer Speech & Language, 2022.

### Annulation d'écho — LocalVQE

- LocalVQE, © 2024-2026 Richard Sherwood Palethorpe — https://huggingface.co/LocalAI-io/LocalVQE
- converti pour Core ML par Fluid Inference — https://huggingface.co/FluidInference/localvqe-coreml
- d'après DeepVQE : E. Indenbom et al., Interspeech 2023, arXiv:2306.03177.

Licence : Apache 2.0 — https://www.apache.org/licenses/LICENSE-2.0

## Bibliothèques

- **FluidAudio**, © Fluid Inference — Apache 2.0 — https://github.com/FluidInference/FluidAudio
- **Sparkle** (mises à jour), © Sparkle Project et Andy Matuschak — licence MIT —
  https://github.com/sparkle-project/Sparkle

## Polices

- **Geist** et **Geist Mono**, © 2024 The Geist Project Authors — SIL Open Font License 1.1 —
  https://github.com/vercel/geist-font (texte de la licence joint aux polices, dans l'app).

## Sons

- Packs de sons d'enregistrement (Pluck, Bips, Clics, Mélodie, Glisse) : **Epidemic Sound** —
  https://www.epidemicsound.com — « User Interface, Click, Select, Soft Round Pluck, Short,
  Reverb », « Beep, Button, Happy, Select, Confirm, Deselect, Cancel », « Click, On & Off,
  Small, Short 03 », « Alert, Alerts, Notification 15 », « Misc, Completions, Melodic,
  Success », « Alert, Notification, Email, Receive, Incoming 03 » et « Motion, Swipe Backup ».
  Les autres sons de Plume, dont le pack Bois, sont synthétisés par l'app.

## Icônes

- **Lucide**, © Lucide Contributors — licence ISC ; certaines icônes proviennent de Feather,
  © Cole Bemis — licence MIT — https://lucide.dev
