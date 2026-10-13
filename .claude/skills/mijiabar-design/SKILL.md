---
name: mijiabar-design
description: Apply and review MijiaBar's UI and motion rules. Use when adding or changing SwiftUI views, animations, transitions, buttons, icons, colors, illustrations, or accessibility in Sources/MijiaBarApp, or when asked to review UI changes.
---

# MijiaBar design rules

The source of truth is `docs/DESIGN.md`. Read it before changing UI. Build and verification commands are in `AGENTS.md`. Motion tokens live in `Sources/MijiaBarApp/Motion.swift`, colors in `Theme.swift`.

## When building

1. Decide whether it should animate at all, using the frequency table in `docs/DESIGN.md` §1. Keyboard-triggered paths (↑↓ ↩ Esc ← → Space, search typing) never animate: use `withoutAnimation { }` or `m.open(d, animated: false)`.
2. Name the purpose: feedback, state, spatial, or preventing a jarring change. If none applies, don't animate.
3. Use only `Motion.press / snappy / smooth / enter / exit`. No bounce, ≤ 300 ms, exits faster than entrances (`.transition(.pop())`).
4. Press: `.buttonStyle(.pressable)`. Hover: `.hoverHighlight()`. Never scale from 0; never scale on hover.
5. Respect Reduce Motion: cross-fades only; pause continuous `TimelineView` animation.
6. Use `Theme` semantic colors so light and dark both work.
7. Put glows in `.background {}`/`overlay`; don't use `.blur` or `rotation3DEffect` on views, so snapshots match the live app.
8. Give icon-only and stateful controls `.accessibilityLabel` / `.accessibilityValue`; use `OptionPicker` for single-choice menus.

## When verifying

```bash
swift build
.build/debug/MijiaBarApp --snapshot /tmp/shots -AppleLanguages "(zh-Hans)"
.build/debug/MijiaBarApp --gif /tmp/demo.gif -AppleLanguages "(zh-Hans)"
```

Look at the light and dark screenshots, and step through the GIF frame by frame (`ffmpeg -i /tmp/demo.gif -vf fps=4,tile=6x3 sheet.png`).

## When reviewing

Report findings as a table with columns `Before | After | Why`, one row per issue, citing `file:line`. Check every item in the checklist at the end of `docs/DESIGN.md` (§8).
