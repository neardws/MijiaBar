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

<p align="center"><img src="https://files.neardws.com/mijiabar/readme/demo.gif" width="300" alt="demo"></p>

[Features](#features) · [Screenshots](#screenshots) · [Install](#install) · [Sign in](#sign-in) · [Auto-hidden devices](#auto-hidden-devices) · [Live video (cameras)](#live-video-cameras) · [Agent / MCP](#agent--mcp) · [Build from source](#build-from-source) · [Where data is stored](#where-data-is-stored) · [Credits](#credits)

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
  <img src="https://files.neardws.com/mijiabar/readme/list-light.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/ac-cool-light.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/fan-light.webp" width="260" alt="">
</p>
<p align="center"><b>Dark mode</b><br>
  <img src="https://files.neardws.com/mijiabar/readme/list-dark.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/ac-heat-dark.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/light-dark.webp" width="260" alt="">
</p>
<p align="center">
  <img src="https://files.neardws.com/mijiabar/readme/plug-light.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/agent-light.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/login-light.webp" width="260" alt="">
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

## Live video (cameras)

- Camera and doorbell detail cards have a **Watch live** button: the video plays inline in the card, and the enlarge button pops it out into a resizable window.
- It uses the bundled [go2rtc](https://github.com/AlexxIT/go2rtc) (MIT, official release, SHA-256 verified at build time) as a helper that only runs while you watch: it listens on `127.0.0.1` on a random port, has RTSP / WebRTC / HomeKit (mDNS) disabled, exposes only the player and `/api/ws`, stops 20 s after the player closes and is killed when MijiaBar quits.
- Sign-in reuses the QR session: MijiaBar keeps the `passToken` returned by the QR login in the Keychain and hands it to go2rtc via a temporary `go2rtc.yaml` (mode 600, deleted as soon as go2rtc has read it). Sessions from before v0.1.8 need one more QR scan (**Settings → Camera live view**).
- Stream keys come from the Xiaomi cloud on every connect; video comes from the camera over Xiaomi's P2P. Nothing is recorded. Battery doorbells are woken up and drain faster, so keep it short. Agents / MCP have no camera access.
- Each device's detail header (and, subtly, its list row) shows which path the last read/control used: **LAN** (direct miIO), **Cloud** (fallback) or **BLE gateway**.
- Away-from-home detection: MijiaBar compares the Mac's network subnets with the devices' local IPs (re-checked on every network change, nothing stored). When you're away it skips LAN attempts and goes straight to the cloud, and camera cards say live view is only available at home.

<p align="center">
  <img src="https://files.neardws.com/mijiabar/readme/camera-live-light.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/doorbell-live-dark.webp" width="260" alt="">
</p>

## Agent / MCP

Open **Settings → Agent interface**, click **Copy setup instructions** and paste the text into Claude Code, Codex, Cursor or any other agent. The agent finds the bundled CLI, registers the MCP server in its own config and verifies by listing your devices. The same text (with the path filled in) is printed by `mijiabar setup-prompt`:

```text
Read https://raw.githubusercontent.com/neardws/MijiaBar/main/docs/AGENT_SETUP.md and follow it to set up MijiaBar as your MCP tool.
CLI path: /Applications/MijiaBar.app/Contents/Resources/bin/mijiabar
Don't change any device's state without my consent.
```

Full step-by-step instructions for agents: [docs/AGENT_SETUP.md](docs/AGENT_SETUP.md)

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
