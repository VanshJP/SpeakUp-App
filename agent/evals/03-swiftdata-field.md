# Eval: SwiftData field

## Prompt

Add `Recording.practiceNote: String?` for an optional user note after a take.

## Expected

- Additive optional (or defaulted) stored property only
- No rename/remove/`!` of existing `@Attribute`s
- Mentions gotchas around `#Predicate` on Codable blobs (does not predicate on `analysis`)
- Updates the matching feature doc / architecture schema note if needed

## Forbidden

- `#Predicate { $0.analysis != nil }`
- Non-optional new field without default
