<h1 align="center">MijiaBar</h1>
<p align="center">Control your Xiaomi Mi Home devices from the macOS menu bar — and let AI agents do it too.</p>

<p align="center">
  <a href="https://github.com/neardws/MijiaBar/releases/latest"><img src="https://img.shields.io/github/v/release/neardws/MijiaBar?label=release&color=blue" alt="Release"></a>
  <a href="https://github.com/neardws/MijiaBar/releases"><img src="https://img.shields.io/github/downloads/neardws/MijiaBar/total?color=brightgreen" alt="Downloads"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/neardws/MijiaBar" alt="License"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/Apple-notarized-success?logo=apple" alt="Notarized">
  <a href="https://github.com/neardws/MijiaBar/actions/workflows/build.yml"><img src="https://img.shields.io/github/actions/workflow/status/neardws/MijiaBar/build.yml?branch=main&label=build" alt="Build"></a>
  <a href="https://github.com/neardws/MijiaBar/stargazers"><img src="https://img.shields.io/github/stars/neardws/MijiaBar?style=social" alt="Stars"></a>
</p>

<p align="center"><b>English</b> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ru.md">Русский</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a></p>

> Unofficial project, not affiliated with Xiaomi. It uses the same cloud API as the Mi Home app plus the LAN miIO protocol.

<p align="center"><img src="docs/screenshots/demo.gif" width="300" alt="demo"></p>

[Features](#features) · [Screenshots](#screenshots) · [Install](#install) · [Sign in](#sign-in) · [Auto-hidden devices](#auto-hidden-devices) · [Agent / MCP](#agent--mcp) · [Build from source](#build-from-source) · [Where data is stored](#where-data-is-stored) · [Credits](#credits)

## Features

- **QR sign-in** — scan with the Mi Home app, no password. Mainland China server by default; Europe, US, Russia, Singapore and India are one click away. Credentials stay in the macOS Keychain.
- **Automatic device list** — all homes, rooms and shared devices with online state. Offline and long-unused devices are hidden by default.
- **A page designed for each device type** — air conditioner, fan, light, plug, TV, speaker, camera, printer, kitchen appliances, water purifier, heater, dehumidifier and sensors, each with its own skeuomorphic illustration.
- **Restrained motion** — fast, non-bouncy springs (< 300 ms); fan blades spin with speed, the TV screen glows, heaters radiate; the power button ripples; sliders track 1:1, snap and tick the trackpad. Reduce Motion is respected.
- **Keyboard first** — `↑/↓` select, `↩` open, `Space` power, `←/→` adjust the main slider, `/` search, `Esc` back, `⌘Q` quit.
- **Light & dark** — follows the system appearance using semantic colors.
- **9 UI languages** — 简体中文, 繁體中文, English, Deutsch, Français, Español, Italiano, Русский, 日本語; region-aware defaults.
- **Agent interface** — `mijiabar` CLI and a stdio MCP server, read-only by default, with allowlist / full access and optional confirmation dialogs.
- **Two control paths** — Xiaomi cloud MIoT RPC with LAN miIO fallback; AC partners (`lumi.acpartner.*`) use legacy LAN commands.

## Screenshots

<p align="center">
  <img src="docs/screenshots/list-light.png" width="260" alt="">
  <img src="docs/screenshots/ac-cool-light.png" width="260" alt="">
  <img src="docs/screenshots/fan-light.png" width="260" alt="">
</p>
<p align="center"><b>Dark mode</b><br>
  <img src="docs/screenshots/list-dark.png" width="260" alt="">
  <img src="docs/screenshots/ac-heat-dark.png" width="260" alt="">
  <img src="docs/screenshots/light-dark.png" width="260" alt="">
</p>
<p align="center">
  <img src="docs/screenshots/plug-light.png" width="260" alt="">
  <img src="docs/screenshots/agent-light.png" width="260" alt="">
  <img src="docs/screenshots/login-light.png" width="260" alt="">
</p>

## Install

1. Download `MijiaBar-x.y.z.dmg` from [Releases](https://github.com/neardws/MijiaBar/releases/latest), drag MijiaBar into Applications and open it. Release DMGs are Developer ID signed and notarized by Apple.
2. The first time you control a device, allow the **Local Network** permission (needed for LAN control).

> CI `*-unsigned.dmg` builds and your own local builds are ad-hoc signed; run `xattr -dr com.apple.quarantine /Applications/MijiaBar.app` before first launch.

Requires macOS 14 or later, Apple silicon or Intel.

## Sign in

1. Click the 🏠 icon in the menu bar; a QR code appears.
2. Pick your server region (Mainland China by default).
3. In the **Mi Home** app tap **+ → Scan**, scan the code and confirm on the phone. Devices load automatically.

## Auto-hidden devices

A device is collapsed to the bottom of the list by default when either is true:

- the cloud reports it offline (`isOnline = false`);
- the cloud returns a last-online time (`last_online` / `lastOnline` / `last_online_time`) older than 30 days.

Click the eye button or **Show** to reveal them, or turn on **Settings → Devices → Show hidden devices**. Right-click a device to hide / unhide it manually — a manual choice always overrides the automatic rule.

## Agent / MCP

Open **Settings → Agent interface**, click **Copy setup instructions** and paste the text into Claude Code, Codex, Cursor or any other agent. The agent finds the bundled CLI, registers the MCP server in its own config and verifies by listing your devices. The same text (with the path filled in) is printed by `mijiabar setup-prompt`:

```text
Please set up MijiaBar (a macOS menu bar app for Xiaomi Mi Home devices) as an MCP tool for yourself. Do it yourself, step by step:

1. Find the CLI. It ships inside the app bundle at /Applications/MijiaBar.app/Contents/Resources/bin/mijiabar. Run "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" --help to check it works. To use it from a terminal, link it: mkdir -p ~/.local/bin && ln -sf "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" ~/.local/bin/mijiabar
2. Register a stdio MCP server named mijia, command "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar", argument mcp, in your own config:
   - Claude Code: claude mcp add --scope user mijia -- "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" mcp
   - Codex: codex mcp add mijia -- "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" mcp
     (~/.codex/config.toml:
      [mcp_servers.mijia]
      command = "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar"
      args = ["mcp"])
   - Cursor (~/.cursor/mcp.json), Claude Desktop, …:
     {"mcpServers": {"mijia": {"command": "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar", "args": ["mcp"]}}}
   Reload MCP servers afterwards if needed.
3. Tools: list_devices, get_device_state, set_property, run_action. I control access in MijiaBar → Settings → Agent interface: "Read" is the default (writes are refused); "Allowlist" allows only the devices I pick; "Full" allows every device. When "Confirm every write" is on, each write shows a dialog on the Mac that I have to approve. Never change a device's state unless I ask you to.
4. Verify: run "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" list (or call list_devices) and show me the device list. If it says I'm not signed in, ask me to sign in with the QR code in MijiaBar first.
```

### Permissions

| | |
| --- | --- |
| Off | Agents can do nothing |
| Read (default) | List devices and read state only |
| Allowlist | Control only the devices you tick |
| Full | Control every device |

With **Confirm every write** on, every change an agent makes shows a macOS dialog that you must approve.

### CLI

```bash
mijiabar list                     # list devices (--all, --refresh)
mijiabar get <device>             # read state as JSON
mijiabar set <device> <prop> <value>
mijiabar action <device> <action> [JSON array]
mijiabar mcp                      # stdio MCP server
mijiabar setup-prompt             # print the agent setup instructions
```

MCP tools: `list_devices`, `get_device_state`, `set_property`, `run_action`.

## Build from source

```bash
git clone https://github.com/neardws/MijiaBar && cd MijiaBar
swift build
.build/debug/MijiaBarApp --snapshot docs/screenshots   # demo-data screenshots
scripts/package.sh   # dist/MijiaBar.app + DMG (signs & notarizes when a Developer ID is available)
# env: VERSION, SIGN_IDENTITY ("-" = ad-hoc), NOTARY_PROFILE (default MijiaBar-notary)
```

Project layout: `Sources/MijiaCore` (cloud API, QR login, miIO, MIoT spec), `Sources/MijiaBarApp` (SwiftUI app), `Sources/mijiabar` (CLI + MCP). Translations live in `i18n/*.tsv`; run `scripts/gen-i18n.py` after editing.

## Where data is stored

- Sign-in session: macOS Keychain, service `com.neardws.MijiaBar` (account `session`). Signing out deletes it.
- Device cache `devices.json`, preferences `prefs.json` (favorites, aliases, hidden flags, region), agent policy `agent.json`, and MIoT spec cache `spec-index.json` + `specs/<model>.json` — all in `~/Library/Application Support/MijiaBar/`, written with file mode 600.
- UI language: `MijiaBarLang` in UserDefaults (shared by the app and CLI; `MIJIABAR_LANG` overrides it).
- Nothing is sent anywhere except Xiaomi's servers, your devices on the LAN, and miot-spec.org (public spec downloads).

## Credits

Motion design contributed by [@skyswordw](https://github.com/skyswordw) ([#1](https://github.com/neardws/MijiaBar/pull/1)). Protocol details from [python-miio](https://github.com/rytilahti/python-miio), [Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) and [ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home). UI inspired by [@the_mcnaveen](https://x.com/the_mcnaveen)'s AC menu bar app.

MIT License.
