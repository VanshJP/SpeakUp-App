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

## Cross-links

[today-library.md](./today-library.md) · [recording.md](./recording.md) · [speech-pipeline.md](./speech-pipeline.md) · [practice-tools.md](./practice-tools.md) · [widgets.md](./widgets.md) (`QuickStoryWidget`)
