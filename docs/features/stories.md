# Stories — scripts & story-linked practice

## Purpose

User-authored rich-text scripts in folders. Practice against a Story; relevance scoring uses script fidelity.

## Key files

| Role | Path |
|------|------|
| Models | `SpeakUp/Models/Story.swift`, `StoryFolder.swift`, `StoryFolderHealing.swift` |
| Views | `SpeakUp/Views/Stories/` — list, detail, editor, folder bar/sheet |
| Today card | `SpeakUp/Views/Today/StoryPromptCard.swift` |
| VM | `SpeakUp/ViewModels/StoriesViewModel.swift` |
| Tagging | `SpeakUp/Services/StoryTaggingService.swift` (LLM when available; conservative) |
| Editor bits | `Views/Components/RichTextEditor.swift`, `PersistentTextField`, `FlowLayout` |
| Defaults | `StoryFolder.defaults` healed + seeded at launch (`seedStoryFoldersIfNeeded`) |

## Data shape

- Plain `content` (search / LLM / relevance) + `contentAttributed` (`Data` for `NSAttributedString`).
- Optional tags: friends / dates / locations / topics.
- `Recording.storyId` links a take to a Story.

## Invariants

1. When both Prompt and Story are attached, **Story wins** for `promptText` / relevance.
2. Warm-ups and drills accept `sourceStory` from Library send-to actions.
3. Deep links: `speakup://story`, `speakup://story/new`.
4. Tagging must skip cleanly when no LLM backend is available.
5. Recording detail opened from Story practice history supplies `RecordingDetailSource.story`; “Practice Again” routes through the parent `((Story, RecordingDuration) -> Void)` callback so the next take keeps the same Story and target duration instead of becoming one-minute prompt-less free practice.
6. **`StoryFolderBar` is `FilterChip`** — the same chip the Prompts tab filters with, so the two halves of the
   Library look like one control. It used to be a bespoke capsule filled with the folder's own color when
   selected (plus a white count bubble and a divider), which made the selected story chip the loudest thing on
   the page and meant two tabs of the same screen filtered by two different-looking controls. Selection is the
   solid white pill everywhere; a folder's `colorHex` shows on the idle glyph via `FilterChip.tint`. "+ Folder"
   stays a dashed capsule because it is an action, not a filter. Do not fork the chip — change `FilterChip`
   (`Views/History/HistoryView.swift`) / `SelectedFilterChrome` (`FilterPill.swift`) and both tabs move together.
   Tool lists (`FilterPill` in Warm-Up / Read-Aloud / Calm) use the same selected-white / idle-glass chrome.
7. **Folder seed heals CloudKit dupes.** Launch collapses `StoryFolder` rows by normalized name (keep one,
   remap `Story.folderId`, delete extras), then inserts any **missing** default names (`Personal` / `Work` /
   `Practice Ideas`) — not “seed only when the table is empty.” Fingerprint key:
   `seededStoryFoldersFingerprint_v1`. Same class of heal as prompts (`seededPromptFingerprint_v1`).
8. **Empty Stories rail.** When there are zero stories, `StoryFolderBar` shows **All + New Folder** only
   (hides Pinned and per-folder chips). Folder scope is a clearable filter: re-tapping the selected chip
   returns to All; `hasActiveFilters` / Clear Filters include `folderSelection != .all`.

## Cross-links

[today-library.md](./today-library.md) · [recording.md](./recording.md) · [speech-pipeline.md](./speech-pipeline.md) · [practice-tools.md](./practice-tools.md) · [widgets.md](./widgets.md) (`QuickStoryWidget`)
