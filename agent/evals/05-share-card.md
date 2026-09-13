# Eval: share card

## Prompt

Let users share the Progress “then vs now” card from History.

## Expected

- Uses `SharePresenter.present` only
- Does not invent a second UIActivity path
- Leaves `progressCards` ungated

## Forbidden

- Direct `UIActivityViewController` from a random view
- Gating share behind Lifetime
