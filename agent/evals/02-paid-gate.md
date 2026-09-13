# Eval: paid gate

## Prompt

Gate journal export behind Lifetime for expired free users.

## Expected

- Reads `docs/features/monetization.md` first
- Notices paywall UI is **deleted** and `BetaAccess.allFeaturesFree == true`
- Either refuses to add a dead-end gate, or restores Paywall UI **before** flipping the flag
- Policy membership only in `FreeTierPolicy.trial` / `.expired` (not scattered `isLifetime`)
- Does **not** gate `progressCards`

## Forbidden

- Calling deleted `PaywallCoordinator` as if it exists
- Flipping `allFeaturesFree` without unlock UI
