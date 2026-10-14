# AGENTS.md

Instructions for AI coding agents (Codex, Claude Code, Cursor, …) working in this repository. Humans are welcome to read it too.

## Project

MijiaBar is a macOS menu bar app (SwiftUI, macOS 14+) that controls Xiaomi Mi Home devices, plus a CLI and stdio MCP server. Swift Package Manager only; no Xcode project, no third-party Swift dependencies. Camera live video uses a bundled [go2rtc](https://github.com/AlexxIT/go2rtc) binary that `scripts/package.sh` downloads and checks by SHA-256; it is never committed.

- `Sources/MijiaCore` — Xiaomi cloud API (RC4-signed requests), QR sign-in, the miIO LAN protocol (UDP 54321), MIoT specs, localization (`L()`, `AppLang`, generated `Translations.swift`), the agent setup prompt (`AgentPrompt.swift`), and `Controller`, which picks cloud or LAN for each device.
- `Sources/MijiaBarApp` — the SwiftUI app.
  - `AppModel` holds state and navigation.
  - `Motion.swift` holds every animation token and shared interaction modifiers.
  - `Theme.swift` holds semantic colors (light/dark aware).
  - `TypeKit.swift` / `TypeDetails.swift` / `Art.swift` are the per-device-type detail pages and their illustrations; `CardViews.swift` is the generic spec-driven card; `ACViews.swift` is the air conditioner card.
  - `LiveVideo.swift` is the camera/doorbell live view (inline player, pop-out window, go2rtc process).
- `Sources/mijiabar` — the CLI and MCP server. Writes are gated by `AgentPolicy` (Settings → Agent interface).
- `site/template.html` + `i18n/site/*.json` — the website (GitHub Pages serves `docs/`). `scripts/gen-site.py` renders `docs/index.html` (English) and `docs/zh-CN.html` (Simplified Chinese). Only these two are published for now; drafts for the other app languages sit in `i18n/site/drafts/` and are not built — don't update them until a language is switched back on in `LANGS`.

## Sparkle updates

In-app updates use Sparkle 2 (`SUFeedURL` → GitHub Pages `docs/appcast.xml`). The EdDSA **private** key lives only at `~/mijiabar-private/sparkle/eddsa_priv.key` on the maintainer Mac — never commit it. See [`docs/UPDATING.md`](docs/UPDATING.md).

## Build and check

```bash
swift build                                    # debug build of all targets
swift build -c release                         # what CI packages
scripts/test.sh                                # unit tests (Swift Testing); also works with Command Line Tools only
scripts/scan-secrets.sh                        # must pass before every commit (CI runs it)
python3 scripts/gen-i18n.py                    # regenerate Translations.swift; fails if any L() string lacks a translation
python3 scripts/gen-agent-docs.py              # regenerate docs/AGENT_SETUP*.md from i18n/agent-setup/*.txt
python3 scripts/gen-site.py                    # regenerate the website (docs/*.html); fails if a language lacks a string
python3 -m http.server -d docs 8000            # preview the website at http://localhost:8000 (?lang=ja etc. picks a language)
scripts/site-shots.sh                          # re-render the website's screenshots, illustrations and share image (needs swift build + cwebp)
.build/debug/MijiaBarApp --snapshot /tmp/shots -AppleLanguages "(zh-Hans)"   # every screen, light and dark (*-light.png / *-dark.png)
.build/debug/MijiaBarApp --gif /tmp/demo.gif -AppleLanguages "(zh-Hans)"     # record the AC card animation
.build/debug/MijiaBarApp --art /tmp/art                                        # each illustration on its own, transparent (the website's device lineup)
```

`scripts/package.sh` builds the app and DMG. With a Developer ID it signs and notarizes; `SIGN_IDENTITY=-` forces ad-hoc signing (what CI does).

CI (`.github/workflows/build.yml`) uses Xcode 16 on `macos-15`. Code must compile there: guard newer APIs with `if #available(macOS 15, *)` and keep a macOS 14 fallback.

**Command Line Tools only (no Xcode):** the macOS 27 SDK in Command Line Tools lacks the SwiftUI macro plugin, so `@State` fails to compile. Build against the 26.x SDK instead:

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk swift build --build-system native
```

## Verifying UI changes

You can't click through the menu bar app, so verify visually:

1. Run `--snapshot` and look at the PNGs in both light and dark (list, both AC cards, light, plug, fan, cameras, settings, login).
2. For motion, run `--gif` and step through frames: `ffmpeg -i /tmp/demo.gif -vf fps=4,tile=6x3 sheet.png`.
3. The snapshot path uses `cacheDisplay`, which can't draw `.blur` or `rotation3DEffect`. Use gradients and 2D transforms so screenshots match the live app.

`--snapshot --real` renders your own signed-in devices for local checks. **Never commit those images**: they contain real device names and rooms.

Regenerate `docs/screenshots/` (Simplified Chinese, `-AppleLanguages "(zh-Hans)"`) only when a PR changes how a screen looks. Every README language uses these same images.

## Conventions

- **Read [`docs/DESIGN.md`](docs/DESIGN.md) before touching UI.** In short: animate only for feedback or state; use `Motion.*` tokens (no bounce, ≤ 300 ms, exits faster than entrances); keyboard actions never animate (`withoutAnimation { }`, `animated: false`); respect Reduce Motion; use `Theme` semantic colors; give icon-only and stateful controls accessibility labels and values.
- **Strings:** every user-facing string goes through `L("简体中文", "English")` (or `LF` with `%@` arguments). The English text is the key for the other languages: add a row to `i18n/ui.tsv` (English, de, fr, es, it, ru, ja) and the Taiwan-style Traditional Chinese to `i18n/zh-Hant.tsv`, then run `python3 scripts/gen-i18n.py`. Never edit `Translations.swift` by hand. Reusing an existing English key reuses its translations, so pick a distinct key when the meaning differs (e.g. "Power" is wattage; the power button uses "Power on/off").
- **Style:** match the surrounding code — compact one-line bodies are normal here. Code comments are in Chinese; keep new ones short and in Chinese.
- **Privacy:** never commit tokens, `ssecurity`, device IPs, or real device names. Demo data lives in `Snapshot.swift`. Credentials belong in the Keychain; caches in `~/Library/Application Support/MijiaBar/` with mode 0600.
- **Agent safety:** don't widen what the CLI/MCP can do without going through `AgentPolicy.canWrite` and the confirmation prompt.

## Pull requests

- One topic per PR. Describe user-visible changes first, then implementation notes and a test plan.
- The READMEs (`README.md`, `README.zh-CN.md`, `README.zh-TW.md`, `README.ru.md`, `README.de.md`, `README.fr.md`) are generated by `scripts/gen-readme.py`. Change the text there and regenerate; don't edit the README files directly.
- The website is generated too: edit `site/template.html` and `i18n/site/*.json`, then run `python3 scripts/gen-site.py`; never edit `docs/*.html` directly. `en.json` is the reference — every published language needs the same keys, the same `|` separators and `{v}` placeholder. The agent prompt on the page is read from `AgentPrompt.swift` and the version from `docs/appcast.xml`, so don't copy them into the strings. Re-run `scripts/site-shots.sh` only when the app's look or demo data changes (it uses demo data, never `--real`). The page follows `docs/DESIGN.md` as well: motion only for feedback or state, Reduce Motion respected, semantic colors for light and dark.
- The agent setup guide (`docs/AGENT_SETUP*.md`) is generated from `i18n/agent-setup/*.txt` by `scripts/gen-agent-docs.py`. The prompt users copy in Settings (`AgentPrompt.swift`) stays short and links to that guide; put details in the guide, not the prompt.
- Things you can't verify without real devices (LAN control, sign-in) must be listed as unchecked items in the test plan.
