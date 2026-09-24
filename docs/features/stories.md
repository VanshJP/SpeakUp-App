# Stories — scripts & story-linked practice

## Purpose

User-authored rich-text scripts in folders. Practice against a Story; relevance scoring uses script fidelity.

## Key files

| Role | Path |
|------|------|
| Models | `SpeakUp/Models/Story.swift`, `StoryFolder.swift`, `StoryFolderHealing.swift` (plan + `StoryFolderSeedService` apply) |
| Views | `SpeakUp/Views/Stories/` — list, detail, editor, folder bar/sheet |
| Today card | `SpeakUp/Views/Today/StoryPromptCard.swift` |
| VM | `SpeakUp/ViewModels/StoriesViewModel.swift` |
| Tagging | `SpeakUp/Services/StoryTaggingService.swift` (LLM when available; conservative) |
| Editor bits | `Views/Components/RichTextEditor.swift`, `PersistentTextField`, `FlowLayout` |
| Defaults | `StoryFolder.defaults` healed + seeded via `StoryFolderSeedService.healIfNeeded` |

## Data shape

- Plain `content` (search / LLM / relevance) + `contentAttributed` (`Data` for `NSAttributedString`).
- Optional tags: friends / dates / locations / topics.
- `Recording.storyId` links a take to a Story.

## Invariants

1. When both Prompt and Story are attached, **Story wins** for `promptText` / relevance.
2. Warm-ups and drills accept `sourceStory` from Library send-to actions.
3. Deep links: `speakup://story`, `speakup://story/new`.
4. Tagging must skip cleanly when no LLM backend is available.
5. Recording detail opened from Story practice history supplies `RecordingDetailSource.story`; “Practice again” routes through the parent `((Story, RecordingDuration) -> Void)` callback so the next take keeps the same Story and target duration instead of becoming one-minute prompt-less free practice.
6. **`StoryFolderBar` is `FilterChip`** — the same chip the Prompts tab filters with, so the two halves of the
   Library look like one control. It used to be a bespoke capsule filled with the folder's own color when
   selected (plus a white count bubble and a divider), which made the selected story chip the loudest thing on
   the page and meant two tabs of the same screen filtered by two different-looking controls. Selection is the
   solid white pill everywhere; a folder's `colorHex` shows on the idle glyph via `FilterChip.tint`. "+ Folder"
   stays a dashed capsule because it is an action, not a filter. Do not fork the chip — change `FilterChip`
   (`Views/History/HistoryView.swift`) and both tabs move together. Tool pages
   have no filter chrome at all (practice-tools invariant 8).
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

9. **Nothing touches a story after deleting it.** `StoryEditorView` drops `draftStory` (and its autosave) *before* `deleteStory`: its `onDisappear` runs `finalSave()`, which otherwise wrote the editor's fields straight back into the deleted row. `StoryDetailView` renders nothing past `storyIsGone` (`isDeleted || story.isDeleted || story.modelContext == nil`) and pops itself when the editor sheet it presented deleted the story - it used to stay open on a story that no longer existed. Same rule as `RecordingDetailView.deleteRecording`: stop reading, then delete.

10. **Remote-change refreshes are fingerprint- and visibility-gated.** `NSPersistentStoreRemoteChange` fires for this
    process's own saves too (simulator probe: every main- and background-context save posts it, CloudKit on or off), so each
    take's analysis saves used to heal + refetch every Story (RTFD, tags) and re-render the list. Now the list and
    `StoryDetailView` call `surfaceAppeared` / `surfaceDisappeared`; with neither on screen a burst only sets
    `needsRemoteRefresh`, replayed on the next appear. When visible, the debounced refresh compares a `StoreFingerprint`
    (story count, newest `updatedAt`, each folder's id/name/symbol/color/order via `propertiesToFetch`) with the one taken at
    the last full load and skips heal + reload when equal. Folders have no timestamp, so their fields are compared directly
    to catch a remote rename. **Every Story write the list shows or sorts by must bump `updatedAt`** (edits, pin, move,
    stage, take count, best score) or the list misses it.
11. **Row and detail costs.** Rows are direct children of the `LazyVStack` (only on-screen rows build) and read their
    preview from `StoriesViewModel.contentPreview(for:)`, memoized per (id, `updatedAt`). `StoryDetailView` decodes RTFD,
    word count and reading time once per `updatedAt` into a `@State` reference box (`StoryDisplayCache`) filled
    synchronously in body, so first paint has styled text with no placeholder flash. Linked-take summaries come from
    `StoriesViewModel.linkedTakeSummaries(for:)` on a detached `ModelContext` (gotchas §3).

## Cross-links

[today-library.md](./today-library.md) · [recording.md](./recording.md) · [speech-pipeline.md](./speech-pipeline.md) · [practice-tools.md](./practice-tools.md) · [widgets.md](./widgets.md) (`QuickStoryWidget`)
