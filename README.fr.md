<h1 align="center">MijiaBar</h1>
<p align="center">Contrôle tes appareils Xiaomi Mi Home depuis la barre des menus macOS — ou confie-les à des agents IA.</p>

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

<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ru.md">Русский</a> · <a href="README.de.md">Deutsch</a> · <b>Français</b></p>

> Projet non officiel, sans lien avec Xiaomi. Il utilise la même API cloud que l’app Mi Home ainsi que le protocole LAN miIO.

<p align="center"><img src="docs/screenshots/demo.gif" width="300" alt="demo"></p>

[Fonctionnalités](#fonctionnalités) · [Captures](#captures) · [Installation](#installation) · [Connexion](#connexion) · [Agents / MCP](#agents--mcp) · [Compiler depuis les sources](#compiler-depuis-les-sources) · [Remerciements](#remerciements)

## Fonctionnalités

- **Connexion par QR code** — scanne avec l’app Mi Home, sans mot de passe. Serveur Chine continentale par défaut ; Europe, États-Unis, Russie, Singapour et Inde en un clic. Les identifiants restent dans le trousseau macOS.
- **Liste d’appareils automatique** — toutes les maisons, pièces et appareils partagés avec leur état. Les appareils hors ligne ou inutilisés depuis longtemps sont masqués par défaut.
- **Une page conçue pour chaque type** — climatiseur, ventilateur, lumière, prise, TV, enceinte, caméra, imprimante, cuisine, purificateur d’eau, radiateur, déshumidificateur et capteurs, chacun avec son illustration skeuomorphe.
- **Animations sobres** — ressorts rapides sans rebond (< 300 ms) ; les pales tournent selon la vitesse, l’écran TV s’illumine, le radiateur rayonne ; le bouton d’alimentation fait une onde ; les curseurs suivent 1:1, s’aimantent et donnent un retour haptique. « Réduire les animations » est respecté.
- **Clavier d’abord** — `↑/↓` choisir, `↩` ouvrir, `Espace` marche/arrêt, `←/→` curseur principal, `/` rechercher, `Esc` retour, `⌘Q` quitter.
- **Clair et sombre** — suit l’apparence du système avec des couleurs sémantiques.
- **9 langues** — 简体中文, 繁體中文, English, Deutsch, Français, Español, Italiano, Русский, 日本語 ; langue par défaut selon la région.
- **Interface agent** — CLI `mijiabar` et serveur MCP stdio, en lecture seule par défaut, avec liste autorisée / accès complet et confirmations facultatives.
- **Deux canaux de contrôle** — MIoT RPC via le cloud Xiaomi avec repli LAN miIO ; les AC partner (`lumi.acpartner.*`) utilisent les anciennes commandes LAN.

## Captures

<p align="center">
  <img src="docs/screenshots/list-light.png" width="260" alt="">
  <img src="docs/screenshots/ac-cool-light.png" width="260" alt="">
  <img src="docs/screenshots/fan-light.png" width="260" alt="">
</p>
<p align="center"><b>Mode sombre</b><br>
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

1. Télécharge `MijiaBar-x.y.z.dmg` depuis les [Releases](https://github.com/neardws/MijiaBar/releases/latest), glisse MijiaBar dans Applications et ouvre-le. Les DMG publiés sont signés Developer ID et notarisés par Apple.
2. La première fois que tu contrôles un appareil, autorise l’accès au **réseau local** (nécessaire pour le contrôle LAN).

> Les builds CI `*-unsigned.dmg` et tes builds locaux sont signés ad hoc ; exécute `xattr -dr com.apple.quarantine /Applications/MijiaBar.app` avant le premier lancement.

Nécessite macOS 14 ou ultérieur, Apple silicon ou Intel.

## Connexion

1. Clique sur l’icône 🏠 dans la barre des menus ; un QR code s’affiche.
2. Choisis la région du serveur (Chine continentale par défaut).
3. Dans l’app **Mi Home**, touche **+ → Scanner**, scanne le code et confirme sur le téléphone. Les appareils se chargent automatiquement.

## Agents / MCP

Ouvre **Réglages → Interface agent**, clique sur **Copier les instructions** et colle le texte dans Claude Code, Codex, Cursor ou tout autre agent. L’agent trouve la CLI intégrée, enregistre le serveur MCP dans sa propre configuration et vérifie en listant tes appareils. Le même texte (chemin renseigné) est affiché par `mijiabar setup-prompt` :

```text
Configure MijiaBar (une app de barre des menus macOS pour les appareils Xiaomi Mi Home) comme outil MCP pour toi-même. Fais-le toi-même, étape par étape :

1. Trouve la CLI. Elle est fournie dans l’app : /Applications/MijiaBar.app/Contents/Resources/bin/mijiabar. Lance "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" --help pour vérifier qu’elle fonctionne. Pour l’utiliser dans un terminal, crée un lien : mkdir -p ~/.local/bin && ln -sf "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" ~/.local/bin/mijiabar
2. Enregistre dans ta propre configuration un serveur MCP stdio nommé mijia, commande "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar", argument mcp :
   - Claude Code: claude mcp add --scope user mijia -- "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" mcp
   - Codex: codex mcp add mijia -- "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" mcp
     (~/.codex/config.toml:
      [mcp_servers.mijia]
      command = "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar"
      args = ["mcp"])
   - Cursor (~/.cursor/mcp.json), Claude Desktop, …:
     {"mcpServers": {"mijia": {"command": "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar", "args": ["mcp"]}}}
   Recharge ensuite les serveurs MCP si nécessaire.
3. Outils : list_devices, get_device_state, set_property, run_action. Je contrôle l’accès dans MijiaBar → Réglages → Interface agent : « Lecture » par défaut (les écritures sont refusées) ; « Liste autorisée » n’autorise que les appareils choisis ; « Complet » autorise tous les appareils. Si « Confirmer chaque écriture » est activé, chaque écriture affiche sur le Mac une fenêtre que je dois approuver. Ne modifie jamais l’état d’un appareil sans que je te le demande.
4. Vérifie : lance "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" list (ou appelle list_devices) et montre-moi la liste des appareils. Si je ne suis pas connecté, demande-moi d’abord de me connecter par QR code dans MijiaBar.
```

### Autorisations

| | |
| --- | --- |
| Éteint | Les agents ne peuvent rien faire |
| Lecture (par défaut) | Lister les appareils et lire l’état uniquement |
| Liste autorisée | Contrôler uniquement les appareils cochés |
| Complet | Contrôler tous les appareils |

Avec **Confirmer chaque écriture**, chaque modification d’un agent affiche une fenêtre macOS que tu dois approuver.

### CLI

```bash
mijiabar list                     # list devices (--all, --refresh)
mijiabar get <device>             # read state as JSON
mijiabar set <device> <prop> <value>
mijiabar action <device> <action> [JSON array]
mijiabar mcp                      # stdio MCP server
mijiabar setup-prompt             # print the agent setup instructions
```

Outils MCP : `list_devices`, `get_device_state`, `set_property`, `run_action`.

## Compiler depuis les sources

```bash
git clone https://github.com/neardws/MijiaBar && cd MijiaBar
swift build
.build/debug/MijiaBarApp --snapshot docs/screenshots   # demo-data screenshots
scripts/package.sh   # dist/MijiaBar.app + DMG (signs & notarizes when a Developer ID is available)
# env: VERSION, SIGN_IDENTITY ("-" = ad-hoc), NOTARY_PROFILE (default MijiaBar-notary)
```

Structure : `Sources/MijiaCore` (API cloud, connexion QR, miIO, spécifications MIoT), `Sources/MijiaBarApp` (app SwiftUI), `Sources/mijiabar` (CLI + MCP). Les traductions sont dans `i18n/*.tsv` ; lance `scripts/gen-i18n.py` après modification.

## Remerciements

Design des animations par [@skyswordw](https://github.com/skyswordw) ([#1](https://github.com/neardws/MijiaBar/pull/1)). Détails des protocoles issus de [python-miio](https://github.com/rytilahti/python-miio), [Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) et [ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home). Interface inspirée de l’app de climatisation de [@the_mcnaveen](https://x.com/the_mcnaveen).

Licence MIT.
