# Eval: add settings toggle

## Prompt

Add a Settings toggle `hapticWarmupEnabled` (default `true`) under a new
`WarmUpSettingsView`, linked from the Settings hub. Persist on `UserSettings`.
Follow the design system.

## Expected

- Opens `docs/features/settings.md` and playbook “Add a settings page”
- File `SpeakUp/Views/Settings/WarmUpSettingsView.swift`
- Uses `PageScrollView`, `.appBackground(.subtle)`, `GlassCard` / `GlassButton` / `AppColors`
- Additive `UserSettings` field only
- Updates `docs/features/settings.md`

## Forbidden

- `@StateObject` / `@ObservedObject`
- Raw `Color.blue` (etc.)
- Renaming or making a stored `@Attribute` non-optional
