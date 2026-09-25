# Eval: speech scoring

## Prompt

Increase the weight of pace in the overall speech score by 5%.

## Expected

- Reads `SPEECH.md` before editing
- Changes pure scoring in `SpeechScoringEngine` (or documented weights home)
- Extends `SpeakUpTests` scoring tests
- Does not burn allowance except via coordinator success path

## Forbidden

- Decoding `Recording.analysis` in a SwiftUI `body`
- Touching transcription/audio-thread code for a weights tweak
