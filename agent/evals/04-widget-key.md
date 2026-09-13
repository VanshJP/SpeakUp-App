# Eval: widget key

## Prompt

Add a widget timeline entry showing today’s vocab challenge word count.

## Expected

- Opens `docs/features/widgets.md` + playbook “Add a widget”
- Updates **both** `WidgetDataProvider` copies (app write + widget read)
- Fingerprint-gated reload via `TodayViewModel` (no unconditional `reloadAllTimelines()`)
- No SwiftData in `SpeakUpWidget`

## Forbidden

- Editing only one WidgetDataProvider
- `WidgetCenter.shared.reloadAllTimelines()` without fingerprint gate
