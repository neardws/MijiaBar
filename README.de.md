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

<p align="center"><img src="https://files.neardws.com/mijiabar/readme/demo.gif" width="300" alt="demo"></p>

[Funktionen](#funktionen) · [Screenshots](#screenshots) · [Installation](#installation) · [Anmeldung](#anmeldung) · [Automatisch ausgeblendete Geräte](#automatisch-ausgeblendete-geräte) · [Live-Video (Kameras)](#live-video-kameras) · [Agents / MCP](#agents--mcp) · [Aus dem Quellcode bauen](#aus-dem-quellcode-bauen) · [Wo Daten gespeichert werden](#wo-daten-gespeichert-werden) · [Danksagung](#danksagung)

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
  <img src="https://files.neardws.com/mijiabar/readme/list-light.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/ac-cool-light.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/fan-light.webp" width="260" alt="">
</p>
<p align="center"><b>Dunkelmodus</b><br>
  <img src="https://files.neardws.com/mijiabar/readme/list-dark.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/ac-heat-dark.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/light-dark.webp" width="260" alt="">
</p>
<p align="center">
  <img src="https://files.neardws.com/mijiabar/readme/plug-light.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/agent-light.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/login-light.webp" width="260" alt="">
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

## Automatisch ausgeblendete Geräte

Ein Gerät wird standardmäßig ans Listenende eingeklappt, wenn eine Bedingung zutrifft:

- die Cloud meldet es als offline (`isOnline = false`);
- die Cloud liefert einen letzten Online-Zeitpunkt (`last_online` / `lastOnline` / `last_online_time`), der über 30 Tage zurückliegt.

Über das Augen-Symbol oder **Anzeigen** einblenden, oder **Einstellungen → Geräte → Ausgeblendete Geräte anzeigen** aktivieren. Per Rechtsklick lässt sich ein Gerät manuell aus- oder einblenden – die manuelle Wahl hat immer Vorrang vor der Automatik.

## Live-Video (Kameras)

- Die Detailkarten von Kameras und Türklingeln haben eine Schaltfläche **Live ansehen**: Das Video läuft direkt in der Karte, mit der Vergrößern-Taste öffnet es sich in einem eigenen, skalierbaren Fenster.
- Dafür wird das mitgelieferte [go2rtc](https://github.com/AlexxIT/go2rtc) (MIT, offizielles Release, SHA-256 beim Build geprüft) genutzt, das nur während des Ansehens läuft: lauscht auf `127.0.0.1` mit zufälligem Port, RTSP / WebRTC / HomeKit (mDNS) sind aus, nur Player und `/api/ws` sind erreichbar; es stoppt 20 s nach dem Schließen und wird beim Beenden von MijiaBar beendet.
- Die Anmeldung nutzt die QR-Sitzung: MijiaBar speichert das `passToken` aus dem QR-Login im Schlüsselbund und übergibt es go2rtc über eine temporäre `go2rtc.yaml` (Rechte 600, sofort nach dem Einlesen gelöscht). Sitzungen von vor v0.1.8 brauchen einen weiteren QR-Scan (**Einstellungen → Kamera-Livebild**).
- Schlüssel kommen bei jeder Verbindung aus der Xiaomi-Cloud, das Video per Xiaomi-P2P von der Kamera. Es wird nichts aufgezeichnet. Akku-Türklingeln werden geweckt und entladen sich schneller. Agenten / MCP haben keinen Kamerazugriff.
- Der Kopf der Detailkarte (und dezent die Listenzeile) zeigt, welcher Weg zuletzt genutzt wurde: **LAN** (direkt per miIO), **Cloud** (Rückfall) oder **BLE-Gateway**.
- Erkennung „nicht zu Hause“: MijiaBar vergleicht die Subnetze des Mac mit den lokalen IPs der Geräte (bei jedem Netzwechsel neu, nichts gespeichert). Unterwegs wird LAN übersprungen und direkt die Cloud genutzt; Kamerakarten weisen darauf hin, dass Livebild nur zu Hause geht.

<p align="center">
  <img src="https://files.neardws.com/mijiabar/readme/camera-live-light.webp" width="260" alt="">
  <img src="https://files.neardws.com/mijiabar/readme/doorbell-live-dark.webp" width="260" alt="">
</p>

## Agents / MCP

Öffne **Einstellungen → Agent-Schnittstelle**, klicke auf **Einrichtungsanleitung kopieren** und füge den Text in Claude Code, Codex, Cursor oder einen anderen Agent ein. Der Agent findet das mitgelieferte CLI, registriert den MCP-Server in seiner eigenen Konfiguration und prüft das Ergebnis, indem er deine Geräte auflistet. Denselben Text (mit eingesetztem Pfad) gibt `mijiabar setup-prompt` aus:

```text
Lies https://raw.githubusercontent.com/neardws/MijiaBar/main/docs/AGENT_SETUP.de.md und richte MijiaBar danach als dein MCP-Tool ein.
CLI-Pfad: /Applications/MijiaBar.app/Contents/Resources/bin/mijiabar
Ändere ohne meine Zustimmung keinen Gerätezustand.
```

Vollständige Schritt-für-Schritt-Anleitung für Agents: [docs/AGENT_SETUP.de.md](docs/AGENT_SETUP.de.md)

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

## Wo Daten gespeichert werden

- Anmeldesitzung: macOS-Schlüsselbund, Dienst `com.neardws.MijiaBar` (Account `session`). Wird beim Abmelden gelöscht.
- Gerätecache `devices.json`, Einstellungen `prefs.json` (Favoriten, Aliasse, Ausblendungen, Region), Agent-Richtlinie `agent.json` und MIoT-Spezifikationscache `spec-index.json` + `specs/<Modell>.json` – alles in `~/Library/Application Support/MijiaBar/`, mit Dateirechten 600.
- UI-Sprache: `MijiaBarLang` in den UserDefaults (von App und CLI gemeinsam genutzt; `MIJIABAR_LANG` überschreibt sie).
- Daten gehen nur an Xiaomi-Server, an deine Geräte im LAN und an miot-spec.org (öffentliche Spezifikationen).

## Danksagung

Animationsdesign von [@skyswordw](https://github.com/skyswordw) ([#1](https://github.com/neardws/MijiaBar/pull/1)). Protokolldetails aus [python-miio](https://github.com/rytilahti/python-miio), [Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) und [ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home). UI inspiriert von der Klimaanlagen-Menüleisten-App von [@the_mcnaveen](https://x.com/the_mcnaveen).

MIT-Lizenz.
