# Stories — scripts & story-linked practice

## Purpose

User-authored rich-text scripts in folders. Practice against a Story; relevance scoring uses script fidelity.

## Key files

| Role | Path |
|------|------|
| Models | `SpeakUp/Models/Story.swift`, `StoryFolder.swift`, `StoryFolderHealing.swift` |
| Seed / heal | `SpeakUp/Services/StoryFolderSeedService.swift` (launch + Stories VM) |
| Views | `SpeakUp/Views/Stories/` — list, detail, editor, folder bar/sheet |
| Today card | `SpeakUp/Views/Today/StoryPromptCard.swift` |
| VM | `SpeakUp/ViewModels/StoriesViewModel.swift` |
| Tagging | `SpeakUp/Services/StoryTaggingService.swift` (LLM when available; conservative) |
| Editor bits | `Views/Components/RichTextEditor.swift`, `PersistentTextField`, `FlowLayout` |
| Defaults | `StoryFolder.defaults` healed + seeded via `StoryFolderSeedService` |

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
7. **Folder seed heals CloudKit dupes by normalized name** (not stable ids — folders use random UUIDs;
   prompts heal by string `id`). Collapse same-name rows (keep one, remap `Story.folderId` on **full** Story
   fetches, delete extras), then insert any **missing** default names (`Personal` / `Work` / `Practice Ideas`).
   Fingerprint `seededStoryFoldersFingerprint_v1` is a **name multiset** hash (not raw row count); it is only
   written after a post-save verify plan is a no-op. Heal also runs from `StoriesViewModel` on configure /
   remote change, and posts `SpeakUp.storyFoldersDidHeal` so open UIs reload after launch heal.
   **Name collision is intentional:** a user folder renamed to `Personal` merges into the default on the next
   heal. Folder create/rename/delete invalidates the fingerprint.
8. **Empty Stories rail.** When there are zero stories, `StoryFolderBar` shows **All + New Folder** only
   (hides Pinned and per-folder chips). Chips / Move sheet use `foldersForDisplay` (one per normalized name)
   so ghosts cannot flood those surfaces before heal finishes. **Deleting a display chip** removes every
   same-normalized-name `StoryFolder` (unfiles their stories) so siblings cannot resurrect the chip.
   Folder scope is a clearable filter: re-tapping the selected chip returns to All; `hasActiveFilters` /
   Clear Filters include `folderSelection != .all`.

## Cross-links

[today-library.md](./today-library.md) · [recording.md](./recording.md) · [speech-pipeline.md](./speech-pipeline.md) · [practice-tools.md](./practice-tools.md) · [widgets.md](./widgets.md) (`QuickStoryWidget`)
