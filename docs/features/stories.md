# Stories — scripts & story-linked practice

## Purpose

User-authored rich-text scripts in folders. Practice against a Story; relevance scoring uses script fidelity.

## Key files

| Role | Path |
|------|------|
| Models | `SpeakUp/Models/Story.swift`, `StoryFolder.swift` |
| Views | `SpeakUp/Views/Stories/` — list, detail, editor, folder bar/sheet |
| Today card | `SpeakUp/Views/Today/StoryPromptCard.swift` |
| VM | `SpeakUp/ViewModels/StoriesViewModel.swift` |
| Tagging | `SpeakUp/Services/StoryTaggingService.swift` (LLM when available; conservative) |
| Editor bits | `Views/Components/RichTextEditor.swift`, `PersistentTextField`, `FlowLayout` |
| Defaults | `StoryFolder.defaults` seeded at launch |

## Data shape

- Plain `content` (search / LLM / relevance) + `contentAttributed` (`Data` for `NSAttributedString`).
- Optional tags: friends / dates / locations / topics.
- `Recording.storyId` links a take to a Story.

## Invariants

1. When both Prompt and Story are attached, **Story wins** for `promptText` / relevance.
2. Warm-ups and drills accept `sourceStory` from Library send-to actions.
3. Deep links: `speakup://story`, `speakup://story/new`.
4. Tagging must skip cleanly when no LLM backend is available.
5. **`StoryFolderBar` is `FilterChip`** — the same chip the Prompts tab filters with, so the two halves of the
   Library look like one control. It used to be a bespoke capsule filled with the folder's own color when
   selected (plus a white count bubble and a divider), which made the selected story chip the loudest thing on
   the page and meant two tabs of the same screen filtered by two different-looking controls. Selection is the
   solid white pill everywhere; a folder's `colorHex` shows on the idle glyph via `FilterChip.tint`. "+ Folder"
   stays a dashed capsule because it is an action, not a filter. Do not fork the chip — change `FilterChip`
   (`Views/History/HistoryView.swift`) and both tabs move together.

## Cross-links

[today-library.md](./today-library.md) · [recording.md](./recording.md) · [speech-pipeline.md](./speech-pipeline.md) · [practice-tools.md](./practice-tools.md) · [widgets.md](./widgets.md) (`QuickStoryWidget`)
