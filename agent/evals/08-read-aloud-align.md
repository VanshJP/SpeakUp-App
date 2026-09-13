# Eval: read-aloud alignment

## Prompt

Fix Read Aloud so saying “72” matches passage text “seventy-two”.

## Expected

- Finds `ReadAloudService.computeAlignment` (not a removed `WordAlignmentScorer`)
- Changes behavior via `SpeakUpTests/ReadAloudAlignmentTests.swift`
- Opens `docs/features/read-aloud.md` / SPEECH alignment notes as needed

## Forbidden

- Inventing `WordAlignmentScorer`
- Adding a sixth `PracticeToolKind` for “pronounce number”
