<h1 align="center">MijiaBar</h1>
<p align="center">Steuere deine Xiaomi-Mi-Home-Geräte über die macOS-Menüleiste – oder lass es KI-Agents erledigen.</p>

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

<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ru.md">Русский</a> · <b>Deutsch</b> · <a href="README.fr.md">Français</a></p>

> Inoffizielles Projekt ohne Verbindung zu Xiaomi. Es nutzt dieselbe Cloud-API wie die Mi-Home-App sowie das LAN-Protokoll miIO.

<p align="center"><img src="docs/screenshots/demo.gif" width="300" alt="demo"></p>

[Funktionen](#funktionen) · [Screenshots](#screenshots) · [Installation](#installation) · [Anmeldung](#anmeldung) · [Agents / MCP](#agents--mcp) · [Aus dem Quellcode bauen](#aus-dem-quellcode-bauen) · [Danksagung](#danksagung)

## Funktionen

- **QR-Anmeldung** – mit der Mi-Home-App scannen, kein Passwort. Standardmäßig Server Festlandchina; Europa, USA, Russland, Singapur und Indien sind einen Klick entfernt. Zugangsdaten bleiben im macOS-Schlüsselbund.
- **Automatische Geräteliste** – alle Zuhause, Räume und geteilten Geräte mit Online-Status. Offline- und lange ungenutzte Geräte sind standardmäßig ausgeblendet.
- **Eigene Seite pro Gerätetyp** – Klimaanlage, Ventilator, Licht, Steckdose, TV, Lautsprecher, Kamera, Drucker, Küchengeräte, Wasserfilter, Heizgerät, Luftentfeuchter und Sensoren, jeweils mit skeuomorpher Illustration.
- **Zurückhaltende Animationen** – schnelle Federn ohne Nachschwingen (< 300 ms); Ventilatorflügel drehen sich je nach Stufe, der TV-Bildschirm leuchtet, Heizgeräte strahlen; der Ein/Aus-Knopf zieht eine Welle; Schieberegler folgen 1:1, rasten ein und geben haptisches Feedback. „Bewegung reduzieren“ wird respektiert.
- **Tastatur zuerst** – `↑/↓` auswählen, `↩` öffnen, `Leertaste` Ein/Aus, `←/→` Hauptregler, `/` suchen, `Esc` zurück, `⌘Q` beenden.
- **Hell & dunkel** – folgt dem Systemerscheinungsbild mit semantischen Farben.
- **9 Sprachen** – 简体中文, 繁體中文, English, Deutsch, Français, Español, Italiano, Русский, 日本語; Standard je nach Region.
- **Agent-Schnittstelle** – `mijiabar`-CLI und stdio-MCP-Server, standardmäßig nur lesend, mit Positivliste / Vollzugriff und optionalen Bestätigungsdialogen.
- **Zwei Steuerwege** – Xiaomi-Cloud-MIoT-RPC mit LAN-miIO als Rückfall; AC-Partner (`lumi.acpartner.*`) nutzen ältere LAN-Befehle.

## Screenshots

<p align="center">
  <img src="docs/screenshots/list-light.png" width="260" alt="">
  <img src="docs/screenshots/ac-cool-light.png" width="260" alt="">
  <img src="docs/screenshots/fan-light.png" width="260" alt="">
</p>
<p align="center"><b>Dunkelmodus</b><br>
  <img src="docs/screenshots/list-dark.png" width="260" alt="">
  <img src="docs/screenshots/ac-heat-dark.png" width="260" alt="">
  <img src="docs/screenshots/light-dark.png" width="260" alt="">
</p>
<p align="center">
  <img src="docs/screenshots/plug-light.png" width="260" alt="">
  <img src="docs/screenshots/agent-light.png" width="260" alt="">
  <img src="docs/screenshots/login-light.png" width="260" alt="">
</p>

## Installation

1. Lade `MijiaBar-x.y.z.dmg` unter [Releases](https://github.com/neardws/MijiaBar/releases/latest) herunter, ziehe MijiaBar in „Programme“ und öffne es. Release-DMGs sind mit Developer ID signiert und von Apple notarisiert.
2. Erlaube beim ersten Steuern eines Geräts den Zugriff auf das **lokale Netzwerk** (für die LAN-Steuerung nötig).

> CI-Builds `*-unsigned.dmg` und eigene lokale Builds sind ad-hoc signiert; vor dem ersten Start `xattr -dr com.apple.quarantine /Applications/MijiaBar.app` ausführen.

Benötigt macOS 14 oder neuer, Apple Silicon oder Intel.

## Anmeldung

1. Klicke auf das 🏠-Symbol in der Menüleiste; ein QR-Code erscheint.
2. Wähle die Serverregion (Standard: Festlandchina).
3. Tippe in der **Mi-Home**-App auf **+ → Scannen**, scanne den Code und bestätige am Telefon. Die Geräte werden automatisch geladen.

## Agents / MCP

Öffne **Einstellungen → Agent-Schnittstelle**, klicke auf **Einrichtungsanleitung kopieren** und füge den Text in Claude Code, Codex, Cursor oder einen anderen Agent ein. Der Agent findet das mitgelieferte CLI, registriert den MCP-Server in seiner eigenen Konfiguration und prüft das Ergebnis, indem er deine Geräte auflistet. Denselben Text (mit eingesetztem Pfad) gibt `mijiabar setup-prompt` aus:

```text
Bitte richte MijiaBar (eine macOS-Menüleisten-App für Xiaomi-Mi-Home-Geräte) als MCP-Tool für dich ein. Erledige das selbst, Schritt für Schritt:

1. Finde das CLI. Es liegt im App-Bundle unter /Applications/MijiaBar.app/Contents/Resources/bin/mijiabar. Führe "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" --help aus, um es zu prüfen. Für die Nutzung im Terminal verlinken: mkdir -p ~/.local/bin && ln -sf "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" ~/.local/bin/mijiabar
2. Registriere in deiner eigenen Konfiguration einen stdio-MCP-Server namens mijia mit dem Befehl "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" und dem Argument mcp:
   - Claude Code: claude mcp add --scope user mijia -- "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" mcp
   - Codex: codex mcp add mijia -- "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" mcp
     (~/.codex/config.toml:
      [mcp_servers.mijia]
      command = "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar"
      args = ["mcp"])
   - Cursor (~/.cursor/mcp.json), Claude Desktop, …:
     {"mcpServers": {"mijia": {"command": "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar", "args": ["mcp"]}}}
   Lade die MCP-Server danach bei Bedarf neu.
3. Werkzeuge: list_devices, get_device_state, set_property, run_action. Den Zugriff steuere ich in MijiaBar → Einstellungen → Agent-Schnittstelle: Standard ist „Lesen“ (Schreibzugriffe werden abgelehnt); „Positivliste“ erlaubt nur ausgewählte Geräte; „Voll“ erlaubt alle Geräte. Ist „Jeden Schreibvorgang bestätigen“ aktiv, erscheint auf dem Mac für jeden Schreibvorgang ein Dialog, den ich bestätigen muss. Ändere niemals den Zustand eines Geräts, ohne dass ich dich darum bitte.
4. Prüfen: Führe "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" list aus (oder rufe list_devices auf) und zeig mir die Geräteliste. Falls ich nicht angemeldet bin, bitte mich, mich zuerst in MijiaBar per QR-Code anzumelden.
```

### Berechtigungen

| | |
| --- | --- |
| Aus | Agents können nichts tun |
| Lesen (Standard) | Nur Geräte auflisten und Status lesen |
| Positivliste | Nur die angehakten Geräte steuern |
| Voll | Alle Geräte steuern |

Ist **Jeden Schreibvorgang bestätigen** aktiv, zeigt jede Änderung eines Agents einen macOS-Dialog, den du bestätigen musst.

### CLI

```bash
mijiabar list                     # list devices (--all, --refresh)
mijiabar get <device>             # read state as JSON
mijiabar set <device> <prop> <value>
mijiabar action <device> <action> [JSON array]
mijiabar mcp                      # stdio MCP server
mijiabar setup-prompt             # print the agent setup instructions
```

MCP-Werkzeuge: `list_devices`, `get_device_state`, `set_property`, `run_action`.

## Aus dem Quellcode bauen

```bash
git clone https://github.com/neardws/MijiaBar && cd MijiaBar
swift build
.build/debug/MijiaBarApp --snapshot docs/screenshots   # demo-data screenshots
scripts/package.sh   # dist/MijiaBar.app + DMG (signs & notarizes when a Developer ID is available)
# env: VERSION, SIGN_IDENTITY ("-" = ad-hoc), NOTARY_PROFILE (default MijiaBar-notary)
```

Aufbau: `Sources/MijiaCore` (Cloud-API, QR-Anmeldung, miIO, MIoT-Spezifikationen), `Sources/MijiaBarApp` (SwiftUI-App), `Sources/mijiabar` (CLI + MCP). Übersetzungen liegen in `i18n/*.tsv`; danach `scripts/gen-i18n.py` ausführen.

## Danksagung

Animationsdesign von [@skyswordw](https://github.com/skyswordw) ([#1](https://github.com/neardws/MijiaBar/pull/1)). Protokolldetails aus [python-miio](https://github.com/rytilahti/python-miio), [Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) und [ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home). UI inspiriert von der Klimaanlagen-Menüleisten-App von [@the_mcnaveen](https://x.com/the_mcnaveen).

MIT-Lizenz.
