# Read Aloud

**Summary:** Practice reading scripted text with word-level accuracy scoring. Pick a catalog passage or a saved passage, or add personal text in a focused composer. The composer accepts typing, Clipboard paste, and TXT, RTF, RTFD, or PDF imports. Users can hear a TTS model, optionally open the system dictionary for a single word, then record and match against the source.

Any passage can be **heard first** (TTS model line, then speak it back) from inside the session, and **Minimal pairs** packs score through the same engine. A missed word that differs from what was heard by one consonant gets that consonant marked, named and coached (**Sounds to check**).

**Key symbols:** `ReadAloudPassage`, `ReadAloudCategory`, `ReadAloudSelectionView`, `ReadAloudSessionView`, `ReadAloudResultView`, `ReadAloudService`, `ConsonantAnalyzer`, `SoundCheck`, `PronunciationService`, `DictionaryView`

**Related:** [SPEECH.md](../../SPEECH.md) (alignment), [practice-tools.md](practice-tools.md), [monetization.md](monetization.md)

---

## Product intent

**Accuracy under a known script**, not impromptu invention. Catalog passages train fluency on fixed text. **Your passages** covers dictionary-style single-word drills and self-chosen excerpts without a sixth practice-tool kind.

Free: catalog + custom. Same scoring path for both.

---

## Entry

Library (`PracticeHubView`) → **Read Aloud** (`PracticeToolKind.readAloud`) → `ReadAloudSelectionView` → `ReadAloudSessionView` → `ReadAloudResultView`.

`ReadAloudSelectionView(initialPracticeText:)` opens a scored session immediately on an ephemeral `ReadAloudPassage.custom(from:)`, skipping the list and composer. Recording detail's word swaps use it to rehearse a rewritten line (see [recording-detail.md](./recording-detail.md)). Same auto-start shape as `DrillSelectionView(initialMode:)`: a `.task` on the selection view, so the cover presents after the sheet has settled.

Hub outcome: *Train clarity against a script — ours or your own.* Format line (`PracticeToolKind.format`): *Mic on · scored word by word.*

---

## Selection UI (`ReadAloudSelectionView`)

### Your passages

**Adding lives in the nav bar** — a `ToolPageAction(icon: "plus")` handed to
`ToolPage`, which renders it `.topBarTrailing` in both presentations. It used to
be a full-width glass card pinned above the catalog, so a page for reading
passages opened on a form for writing one and the passages started below the
fold. Library already puts "add" in the chrome for Prompts and Stories; this is
the pushed-page equivalent. Do not move it back into the column.

The **Your passages** rail renders only when there is something saved, and ends
with a compact "Add your own" card — a second door for people who already have
passages. Tapping a card starts practice; its visible actions menu supports edit
and confirmed deletion without requiring a hidden context menu. The menu floats
over the card's trailing edge as a sibling of the card's button (never inside
its label), and the card presses with `RowPressStyle` — a `GlassPressStyle`
scale would slide the card out from under its own menu. `presentComposer` plays
no haptic: the toolbar `+` (`ToolPage`) and the rail card each play their own.

### Passage composer

`ReadAloudComposerSheet` owns the creation flow:

1. **Paste** is the system `PasteButton`. Reading `UIPasteboard` from our own button raised iOS's "Allow Paste" alert on every tap; the system control never does, and greys itself out when there is no text. It must stay opaque to pass iOS's visibility check, so it wears a solid neutral tint rather than glass. Its payload can arrive off the main actor: the closure is `@Sendable` and hops to `@MainActor` before touching state.
2. **Import file** accepts TXT, RTF, RTFD, and text-based PDF documents through `ReadAloudDocumentImporter`, and shows the `VoiceLoader` (`isLoading`) while it reads.
3. **Type or edit** uses a dedicated editor with live word and character counts.
4. **Hear it** uses `PronunciationService.speak(word:)`. Multi-word phrases speak as one utterance; more than three tokens use rate `0.32`, otherwise `0.35`. It reads **Stop** while playing, like the session's; it used to disable itself, and an 800-character passage could only be silenced by leaving the sheet.
5. **Full definition** appears only when `PronunciationService.canDefine` is true. It opens `DictionaryView` and then `UIReferenceLibraryViewController`. It is the one name for the define action everywhere (composer, word sheet, Words).
6. **Save and practice** keeps the text and starts the normal scored session after the composer dismisses.
7. **Save for later** (**Save changes** when editing) stores the text without starting a session.

Both save actions ride a `.safeAreaBar(edge: .bottom)`, so they sit above the keyboard the editor opens with. A dirty draft (text differs from what the sheet opened with) cannot be swiped away (`interactiveDismissDisabled`), and **Cancel** asks before discarding it.

Replacing non-empty editor text through Paste or Import requires confirmation. Empty, under-minimum, whitespace-only, and over-limit drafts cannot be saved, heard, or practiced.

The scoring engine is designed for one focused section. If imported text exceeds `customMaxCharacters` (800), the importer selects an opening at the nearest sentence, paragraph, or word boundary and tells the user. Pasted or typed over-limit text offers the same one-tap **Use first practice section** recovery, a small secondary `GlassButton` (it was caption text with a hit area the size of its words). Scanned PDFs fail with a clear OCR-specific message instead of appearing to import empty content.

### Catalog

**Grouped by `PracticeFocus`**, not by source material. `news` → `.pace`,
`literature` → `.presence`, `technical` / `tongueTwister` / `minimalPairs` /
`custom` → `.clarity`. "News" and "Literature" say where the words came from,
which is not why anyone picks a passage; the category is now the row's tag.

**No filter bars.** Sections are the shared `FocusSection` over
`viewModel.availableFocuses` (= `PracticeToolKind.readAloud.focuses`), rows are
`PracticeItemRow`. This page carried the most chrome in the app — a Shadow-mode
toggle, a focus pill bar, a length pill bar, and a "12 of 20 passages" caption
to explain what the bars had done — above twenty passages whose rows already
print difficulty and word count. All four are gone; the row tag carries
`difficulty · N words`, which is what the length pills were for.
`initialFocus:` still arrives from the Library outcome browser and now
**scrolls** to that group rather than filtering to it. See practice-tools
invariant 8.

See [practice-tools.md](practice-tools.md) invariants 17–20 for the shared axis and its components.

---

## Custom passage model

```swift
ReadAloudPassage.custom(from: text) // id: "custom-<uuid>", category: .custom, ephemeral
ReadAloudPassage.saved(from: text)  // id: "saved-<text>", category: .custom, kept
```

Both run the same title / difficulty / cap rules (`make(text:id:)`); only the id differs. `custom` gets a fresh UUID per call because it is thrown away after the take; `saved` derives its id from the text so a kept row keeps one identity across renders and launches. Saved texts are de-duplicated case-insensitively, which is what makes the text a sound key.

| Rule | Value |
|------|--------|
| Min length | `customMinCharacters` (2) |
| Max length | `customMaxCharacters` (800), prefix-capped |
| Title | 1 word: "Word practice"; 2 to 20: "Sentence practice"; otherwise "Paragraph practice" |
| Difficulty | 1 to 8 words: `.easy`; 9 to 40: `.medium`; otherwise `.hard` |

Not in `DefaultReadAloudPassages.all`. `isCustom` is `category == .custom`.

### Saved passages

| Where | What |
|-------|------|
| Storage | `UserSettings.savedReadAloudTexts: [String]`, additive, defaulted, raw text only |
| List rules | `SavedReadAloudTexts.adding/removing/contains`, a `nonisolated enum` in `ReadAloudPassage.swift`, so the rules are testable without a `ModelContainer` (gotcha §12) |
| Order | Newest first |
| Derived | Title, difficulty and id all come from the text and are never stored, so they cannot drift from `custom(from:)`'s rules |

The seed catalog is still static: saving writes to `UserSettings`, never to `DefaultReadAloudPassages.all`.

`ReadAloudCategory.custom` is for typing only and never appears in `DefaultReadAloudPassages.all`; the catalog lists passages grouped by focus, so no category listing is needed.

---

## Session & scoring

Unchanged for custom vs catalog:

1. Show source text; capture on a live `AVAudioEngine` tap feeding on-device `SFSpeech` recognition (`AudioService` only supplies the permission and record-capable session).
2. Stitch every recognition result into one transcript (`RequestTranscript` per request, see below).
3. `ReadAloudService.computeAlignment(reference:normalizedReference:spokenWords:)` — matched / missed / extra.
4. Read each miss down to the consonant (`SoundCheck`, below).
5. Show `ReadAloudResultView`, then reset on Done, run the same passage on Retry, or run **Drill what you missed** or a sound's **Practice** (below); after a drill, **Read full passage** goes back to the passage it came from.

The session auto-starts listening; there is no pre-roll state to tap through.

Current code does **not** persist a SwiftData `Recording`; Read-Aloud results
are session-local and therefore absent from History and longitudinal clarity
charts. Successful matching still writes the curriculum activity signal. Treat
History persistence as future product work, not as an implemented contract.

**Recognition survives its own request boundaries.** `SFSpeechRecognizer`
closes a request after a pause in speech and again at the request's own
audio-duration ceiling; a reader working through a paragraph triggers both,
several times. `ReadAloudService` re-arms on the same engine and tap
(`armRecognition`) and keeps one `RequestTranscript` per request (`segments`,
joined by the pure `joinTranscripts`), so alignment sees one continuous read and
the reader never loses their place. It also rolls over proactively every 45 s,
waiting up to 10 s for a gap between words so no word is cut in half.

**…and the recognizer restarting inside a request.** On device, SFSpeech can
start a request's transcript over from empty after a pause of a second or two —
`isFinal` still false — and can deliver a blank final. Storing each request's
newest transcript as-is erased everything before the pause, and alignment put
the reader back near word one: the "read restarts from zero" report. Every
result now goes through `RequestTranscript.apply`, which asks the pure
`RecognitionContinuity.classify` whether it is a revision, a new utterance
(commit the old one), a restatement of the whole request (replace everything
held, or the first utterance counts twice), or a blank / shrunken copy (ignore
it). Two signals decide the hard cases: a result carrying
`speechRecognitionMetadata` marks the end of an utterance and is never coalesced
away (`PendingResults.closed`), and a partial arriving after `restartGap` of
quiet (stamped when the recognizer delivered it, `HeardResult.at`) is new speech
even after a one-word utterance. Pinned in `SpeakUpTests/RecognitionContinuityTests.swift`.

**The mic is held, never lost.** Every way capture can go down is a *hold* on
the read, not the end of it — hearing the model line (`isPaused`), a call or
Siri (`isInterrupted`), the app leaving the foreground (`isBackgrounded`), and
automatic recovery failing (`isStalled`). Holds keep `segments` and every
matched word; `rebuildCaptureGraph` brings capture back on `didBecomeActive`, an
interruption's `.ended`, or the reader's **Resume reading**. The rebuild
re-activates the session in a detached task, because `setActive` blocks until
the audio server answers and every way back lands just as the reader starts
speaking; the engine is built afterwards in `startCaptureGraph`, only if the
read is still listening, unheld, and no overlapping rebuild got there first.
A stall gets one
automatic retry after 1.5 s, then waits for the reader; it used to end the
session, which left Retry — the passage from the top — as the only way on.
Held time (`heldDuration(until:)`) is subtracted from the clock and from wpm.
The session keeps the screen awake (`keepsScreenAwake`): a read is minutes of
speaking without a touch, and Auto-Lock used to lock the phone mid-passage.
See gotchas §9 and §26.

**Drill what you missed.** When a take has missed or skipped words, the result
screen offers a short passage made of each miss with two words of context either
side, overlapping stretches merged (`ReadAloudResult.missedPhrases`, built by
`ReadAloudPassage.practiceText(around:in:)`). It runs in the same cover
(`ReadAloudSessionView.drilledPassage`), so the next rep is spent only on what
went wrong instead of re-reading clean sentences.

A drill's result offers **Read full passage** (`ReadAloudResultView.onReadFullPassage`,
set only while `drilledPassage` is non-nil) in place of Drill what you missed:
the drill's own misses were a near-copy of Try again, and checking the fix on
the whole passage was the step the loop lacked. Before it, Retry repeated the
drill and Done left.

**Sounds to check.** The recognizer hears words, not sounds, so nothing here
scores pronunciation. What it can do is read a miss: when "three" comes back as
"free", the two words differ by exactly one consonant, and that consonant is
the place to listen. `ConsonantAnalyzer` turns both words into consonant sounds
with rules of English spelling (digraphs, silent letters, soft C and G, the
three sounds of -ed), finds the one sound that differs, and reports a
`ConsonantSlip`: a swap (TH sounded like F) or a consonant not heard (the final
T, the -ed ending), with the character range that spells it in the word as
written. It stays narrow on
purpose, because a wrong call sends the reader to fix a sound they made fine:

- exactly one consonant swapped or not heard, never an extra one;
- a swap only between related sounds (same place or manner, or a common swap
  such as TH/T, V/W, B/V), so "house" heard as "home" is a misread, not an S;
- same syllable count, at least three letters, and no function words that
  connected speech shrinks anyway ("and" as "an");
- sounds that spelling cannot tell apart (S/Z, SH/ZH, G/J, N/NG) count as equal.

`SoundCheck` (`ReadAloudResult.soundCheck`, derived from the result's word
states when it is built) holds every slip by word index and groups them into
`SoundPattern`s: one per sound, plus **Word endings** for every last sound not
heard, most frequent first. The
result screen shows the top three under **Sounds to check** with the words
("three → free", letters marked), a placement tip specific to the swap, and a
**Practice** button that runs each word on its own and then the stretches of
the page it came from. The word review marks the slipped letters in the passage,
and `WordDetailSheet` shows the marked word, the one-line summary and the tip,
live during the read as well as on the result. **Its speaker works mid-read:**
the session passes `onHear`, which plays the word under the same hold as Hear
it (`playModel` — `pauseForModel`, speak, and the session's
`onChange(of: isSpeaking)` resumes). It used to say "Stop session to hear
pronunciation", and stopping scored the read; on a Minimal pairs pack, hearing
the word is the point. The sheet closes with `Button(role: .close)`, scrolls,
and opens at `.medium` / `.large` (the fixed 320pt height clipped at large
text sizes). Copy says what was heard
("sounded like", "wasn't heard") and never claims a diagnosis or accent work.

The alignment has to keep what was heard for any of this to work. A near miss
("free" for "three", `isNearMiss`, measured on the spelling because "three"
normalizes to "3") followed by a word that lands on the next page word is that
word said wrong (`isSlip`). It used to read as a filler plus
a skip, or, in a minimal pair, as a skip to the look-alike ahead, so every slip
in a Minimal pairs pack came back as "skipped" with the heard word thrown away.
Accuracy is unchanged either way: a skip and a mismatch are both a miss.

The same holds for a word spelled nothing like the page's: a word said in place
of the page word, followed by the next page word, is that word **replaced**
(`isReplacement`) and keeps what was heard. It used to read as a filler plus a
skip whenever the two were not spelled alike, so the review said "skipped" for
a word the reader plainly said, and Sounds to check found a slip on some misses
and not others. Hesitations ("um", "well") still read as fillers.

And a **name the recognizer preferred** is the word: "Laurie" for "lorry"
(`ConsonantAnalyzer.isNameSpelling` — capitalized, same first letter, same
consonant sounds, same syllables, two or more, and not itself a word on the
page). Read cleanly, "Red lorry yellow lorry" used to come back with half its
lorries scored as misses nobody could fix. One-syllable words never qualify:
that is where vowel pairs live, and consonants cannot vouch for a vowel.

Silence-is-not-a-score applies (see practice-tools invariant 14).

---

## Pronunciation service

| API | Behavior |
|-----|----------|
| `speak(word:)` | Strip edge punctuation; rate by token count (>3 tokens → `0.32`, else `0.35`) |
| `speak(text:rate:)` | Keeps punctuation for prosody in shadow mode's model line |
| `canDefine(_:)` | Single token only; then `UIReferenceLibraryViewController.dictionaryHasDefinition` |
| `stripPunctuation(_:)` | Shared with `DictionaryView` |

---

## Files

| Path | Role |
|------|------|
| `SpeakUp/Models/ReadAloudPassage.swift` | Catalog types + `custom(from:)` / `saved(from:)` + `SavedReadAloudTexts` |
| `SpeakUp/Views/ReadAloud/ReadAloudSelectionView.swift` | Toolbar add action, saved rail, focus-grouped catalog |
| `SpeakUp/Views/ReadAloud/ReadAloudComposerSheet.swift` | Paste, import, edit, preview, save, and practice flow |
| `SpeakUp/Views/ReadAloud/ReadAloudSessionView.swift` | Record + score |
| `SpeakUp/Views/ReadAloud/DictionaryView.swift` | System dictionary sheet |
| `SpeakUp/Services/ReadAloudDocumentImporter.swift` | On-device TXT, rich text, and PDF extraction |
| `SpeakUp/Services/PronunciationService.swift` | TTS + define gate |
| `SpeakUp/Services/ReadAloudService.swift` | Session listening, holds / stalls + `computeAlignment` / `isSlip` |
| `SpeakUp/Services/ConsonantAnalyzer.swift` | Spelling to consonant sounds, one-consonant slips, `SoundCheck` / `SoundPattern` |
| `SpeakUp/Views/ReadAloud/MarkedWordText.swift` | A word with one consonant's letters marked, as a single `Text` |
| `SpeakUp/Views/ReadAloud/WordDetailSheet.swift` | Tap-a-word sheet: hear it, define it, the consonant that slipped |
| `SpeakUp/Services/RecognitionContinuity.swift` | `RecognitionContinuity` + `RequestTranscript`: in-request restart handling, shared with live transcription and dictation |
| `SpeakUp/Extensions/View+KeepsScreenAwake.swift` | Idle-timer hold for every timed practice screen |
| `SpeakUp/ViewModels/ReadAloudViewModel.swift` | Selection / session VM |
| `SpeakUpTests/ReadAloudAlignmentTests.swift` | Alignment core, words said wrong, request-boundary stitching |
| `SpeakUpTests/ConsonantAnalyzerTests.swift` | Spelling rules, slips vs. different words, pattern grouping and practice text |
| `SpeakUpTests/RecognitionContinuityTests.swift` | In-request restarts, blank finals, end-to-end "never snaps back" |
| `SpeakUpTests/PracticeToolProgressTests.swift` | `missedPhrases` (with drill ladder and catalog checks) |
| `SpeakUpTests/ReadAloudCustomPassageTests.swift` | Custom factory + define gate |
| `SpeakUpTests/PracticeFocusTests.swift` | Focus axis + derived catalog listings |

---

## Agent notes

- Presented from Practice Hub **tools** section (pushed full page through `ToolPresentation.pushed` via `navigationDestination`), Today, and RecordingDetail next-steps as sheets, not its own tab.
- Difficulty coloring uses `AppColors.difficultyColor`, not raw system colors.
- Keep passage seed data in `Data/`, not inline in views. Custom “Practice anything” passages are ephemeral (`ReadAloudPassage.custom`); kept ones persist on `UserSettings.savedReadAloudTexts`. Neither is appended to the seed array.
- **"Hear it" is a control, not a mode.** It was a Shadow-mode toggle at the top of the catalog that had to be flipped *before* a passage opened, which put it furthest from the moment it is wanted: mid-read, having just fumbled a line. It is one full-width secondary button in the session now, live on every passage for the whole read. Pressing it calls `ReadAloudService.pauseForModelPlayback()` — the mic goes down, because a live recogniser would score the synthesiser as the reader — plays `PronunciationService.speak(text:rate:)`, and resumes on `isSpeaking` falling, with `segments` and every matched word intact. It is one of the service's holds, so the clock stops while the model plays and the result's wpm measures reading, not listening. **Never disabled while the model plays**: that is exactly when someone reaches for it, and the only way past the voiceover used to be sitting through it — it reads Stop instead. **It plays from the start of the sentence the reader is in** (`ReadAloudSessionView.modelLine(in:from:)` walks back from `currentWordIndex` to the word after the last `.` `!` `?` `…`) through to the end; before the first word that is the whole passage. It used to replay from word one, so a reader who fumbled line five sat through lines one to four first. The hold lives in one helper, `playModel`, shared with the word sheet. Copy must not claim accent therapy; the score remains alignment and clarity.
- **Session chrome is glass on the canvas, one white button at a time.** The ✕ is the runner `.glassCircle()` the warm-up and confidence screens wear; the clock and live accuracy are `.glassEffect(.regular, in: .capsule)` with `.statValue` numerals (the accuracy was the only live number without tabular figures); progress is `TickMeter`, not a gradient capsule, and is not animated (a `Canvas` reads it — gotcha §28). While the mic is stalled, **Resume reading** is the white primary and Done drops to `.secondary`. The ✕ plays `Haptics.light()`, not `warning`, on every tap.
- **A start failure offers Try Again** (`viewModel.retryPassage()`) beside Close, unless it needs Settings; it used to offer only Close, back to the list.
- Minimal pairs (`ReadAloudCategory.minimalPairs`) score word hits via the same alignment engine, not phoneme accuracy. A slip on one word of a pair is a miss with the heard word kept, not a skip (`isSlip`), which is what lets **Sounds to check** name the consonant.
- **Sounds to check reads misses, it does not score sounds.** `ConsonantAnalyzer` only runs on `.mismatched(spoken:)` words and only reports one related consonant. Keep it that narrow: widening it (extra consonants, unrelated swaps, function words) mostly flags misreads, and the tip would coach a sound the reader made fine. Marked letters change colour and underline only, never weight or size (see the metrics note below).
- **Silence is not a score.** Mic permission + the record-capable session come from a session-scoped `AudioService.requestPermission()` before the engine starts. A recognizer that stops for good sets `service.recognitionFailureMessage` and **stalls** the read (clock stopped, "Mic stopped", **Resume reading**); finishing from there lands on the result screen with a warning notice that says only the part heard was scored, never a confident "0% · Complete". A session that heard nothing for >3 s gets the "didn't catch any words" notice and `Haptics.warning()`.
- **A dead mic must never sit under a live clock.** `ReadAloudViewModel.startTimer` also ends the session when `service.isListening` goes false while the state still says `.listening`. Every known way to lose the mic is a hold now, so that only fires for something unforeseen — and the old behaviour there (frozen passage, "Not listening", a disabled Done button, restart from the top) is precisely what a dropped read felt like.
- **The session cover is presented on the passage, the result cover on the result** (`fullScreenCover(item:)`). Both used to be `isPresented:` flags over state that `viewModel.reset()` or Retry clears, which drew an empty cover for the length of a dismissal. Gotcha §27.
- The alignment engine (`ReadAloudService.computeAlignment`) is pure/static and pinned by `SpeakUpTests/ReadAloudAlignmentTests.swift`: reference-skips via lookahead, single-word insertion tolerance (fillers do not consume words), words said wrong kept as misses with what was heard (`isSlip`), and number normalization (page "seventy-two" matches recognizer "72"). Change behavior through tests.
- Result screen reports actual wpm against the ≈150 promise when the take is long enough to mean it (>5 s). It counts only words said (matched or said differently): `mismatchedWords` also counts skips, and a skipped line was never spoken, so counting it read as rushing when the reader had jumped ahead.
- Result layout: a pinned header (passage title, **Done** as a small secondary `GlassButton`) so leaving never means scrolling past the word review; the accuracy ring counts up with `Haptics.playCountUp` under a one-line verdict; three stat tiles in one neutral recipe (colour lives in the icon — they used to be three shades of tinted glass) with `.metricValue` numerals; "Sounds to check" and "Word review" are `GlassSectionHeader`s and each sound card titles itself with `GlassCardTitle`; the legend wraps; Try again and Drill what you missed (or Read full passage, after a drill) ride a `.safeAreaBar(edge: .bottom)`, so the next rep never sits under the whole word review.
- Results are ephemeral today. Adding History support requires a deliberate `Recording`/analysis shape and media-storage lifecycle; do not imply persistence in UI copy until that exists.
- Word texts carry state-aware accessibility labels in both session and review ("missed X, you said Y"); upcoming words are `.accessibilityHidden`, and every read (settled) word carries `.isButton`, because a tap opens its sheet.
- **Nothing about a word's match state may change its measured size.** The whole passage draws at one weight (`ReadAloudPassageText.weight`); position is carried by the highlight fill and the colour ramp. The current word used to render `.bold` against `.regular` neighbours, and because bold glyphs are wider, every cursor advance re-flowed the rest of the line — the passage visibly squirmed while being read. Auto-scroll re-centres once per `scrollAdvanceWords` (8) rather than every second word, which was the other half of the same complaint.
- `WrappingHStack` caches its measurement pass per (width, `metricsKey`), with a first-subview probe as a tripwire for callers that do not pass a key. Without the cache it re-measured every subview in **both** `sizeThatFits` and `placeSubviews`, so a 150-word passage cost ~300 text measurements per layout pass, on every partial recognition result. See gotchas §25.
- **The clock does not rebuild the passage.** The passage is its own view (`ReadAloudPassageText`, taking `words` / `states` / `fontSize` and a `selectedWord` binding), and the elapsed time is read only inside `ReadAloudClock`. `ReadAloudViewModel.startTimer` still polls every 250 ms but writes `elapsedTime` only when the whole second changes. The clock used to be read in the session body, so every quarter second re-ran it: the `ForEach` over every word, and a fresh split of `currentPassage.words`.
- Transcript updates **coalesce latest-wins** with at most one drain task in flight (`pendingTranscript` / `isDrainScheduled`), and the recognition callback lifts a `String` out before hopping actors — `SFSpeechRecognitionResult` and `any Error` are not `Sendable`.

- Do **not** add a sixth `PracticeToolKind` for “pronounce word”. Extend Read Aloud.
- Passages the user *types* stay ephemeral (UUID id). Passages the user *keeps* live on `UserSettings`, which is still not the static catalog. Never append to `DefaultReadAloudPassages.all`.
- `canDefine` must stay single-word; sentences use Hear + Practice only.
