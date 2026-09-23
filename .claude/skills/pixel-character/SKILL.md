---
name: pixel-character
description: How AgentWorld's pixel characters are built and animated (half-block pixels, CharacterLook, poses, props) and how to design a new character, pose or prop that stays readable in a terminal. Use when adding a provider's look, a new animation for a tool/status, or tweaking colors of cards and portraits.
---

# Pixel characters

## How pixels reach the terminal

`PixelCanvas` (TerminalUI) stores RGB pixels; each terminal cell shows two
stacked pixels with `▀` (fg = top, bg = bottom). So a cell row is 2 pixels
and characters look square-ish. `nil` pixels are transparent.

## The two families — `World/CharacterPainter.swift`

- **Claude**: 16×10 orange block creature, slit eyes, four legs. Only Claude
  Code uses it.
- **Crew**: 10×13 humanoid. Everything else (subagents, other CLIs). Its
  variety comes from `CharacterLook`: `body`, `hair`, `skin`, `accent`,
  `headgear` (antenna, cap, crown, headphones, bare, horns) and `face` (skin,
  visor). `CharacterLook(name:)` derives one from a hash, so the same agent
  always looks the same; providers use fixed looks in `ProviderLook.swift`.

## Animation — `World/Pose.swift`

`Animator.pose(status:elapsed:t:seed:recentError:)` is a pure function of
time: no stored animation state. A `Pose` sets offsets, arms, eyes, leg step,
a tint and `props` (book, terminal, sparkles, thought bubble, magnifier,
energy, z's, stars…). `seed` desynchronizes characters. Selected cards use
`Animator.waving`.

## Designing something new

1. Colors: pick from `Theme` where possible. Card names use `body`, or
   `accent` when body luminance < 0.3, so a dark outfit needs a bright accent.
2. No logos or brand marks; suggest a CLI through color and headgear only.
3. Keep props inside the figure's box plus a few pixels (`Figure` gives the
   rect); anything outside the card is clipped.
4. New status → map it in `Animator.pose` and in `Theme.color/glyph(for:)`.
5. Look at it with `app-snapshot`: the launcher cards, the panel's stage
   (use `act` to put a pane in each status) and the live crew.
