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

[Fonctionnalités](#fonctionnalités) · [Captures](#captures) · [Installation](#installation) · [Connexion](#connexion) · [Appareils masqués automatiquement](#appareils-masqués-automatiquement) · [Vidéo en direct (caméras)](#vidéo-en-direct-caméras) · [Agents / MCP](#agents--mcp) · [Compiler depuis les sources](#compiler-depuis-les-sources) · [Où sont stockées les données](#où-sont-stockées-les-données) · [Remerciements](#remerciements)

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

## Appareils masqués automatiquement

Un appareil est replié en bas de la liste par défaut si l’une de ces conditions est vraie :

- le cloud le signale hors ligne (`isOnline = false`) ;
- le cloud renvoie une dernière connexion (`last_online` / `lastOnline` / `last_online_time`) de plus de 30 jours.

Clique sur l’œil ou **Afficher**, ou active **Réglages → Appareils → Afficher les appareils masqués**. Un clic droit sur un appareil permet de le masquer ou l’afficher manuellement — le choix manuel l’emporte toujours sur la règle automatique.

## Vidéo en direct (caméras)

- Les fiches des caméras et sonnettes ont un bouton **Voir en direct** : la vidéo se lit dans la fiche, et le bouton d'agrandissement l'ouvre dans une fenêtre redimensionnable.
- La lecture utilise [go2rtc](https://github.com/AlexxIT/go2rtc) intégré (MIT, version officielle, SHA-256 vérifié à la compilation), lancé seulement pendant le visionnage : il écoute sur `127.0.0.1` avec un port aléatoire, RTSP / WebRTC / HomeKit (mDNS) désactivés, seuls le lecteur et `/api/ws` sont exposés ; il s'arrête 20 s après la fermeture du lecteur et est tué quand MijiaBar quitte.
- La connexion réutilise la session QR : MijiaBar garde dans le trousseau le `passToken` renvoyé par la connexion QR et le transmet à go2rtc via un `go2rtc.yaml` temporaire (droits 600, supprimé dès sa lecture). Les sessions d'avant v0.1.8 demandent un nouveau scan (**Réglages → Caméra en direct**).
- Les clés viennent du cloud Xiaomi à chaque connexion, la vidéo de la caméra via le P2P Xiaomi. Rien n'est enregistré. Les sonnettes sur batterie sont réveillées et se déchargent plus vite. Les agents / MCP n'ont pas accès aux caméras.
- L'en-tête de la fiche (et discrètement la ligne de liste) indique le chemin de la dernière lecture/commande : **LAN** (miIO direct), **Cloud** (repli) ou **Passerelle BLE**.
- Détection hors domicile : MijiaBar compare les sous-réseaux du Mac aux IP locales des appareils (réévalué à chaque changement de réseau, rien n'est stocké). Hors de chez vous, le LAN est ignoré et le cloud utilisé directement ; les fiches caméra indiquent que le direct n'est disponible qu'à la maison.

<p align="center">
  <img src="docs/screenshots/camera-live-light.png" width="260" alt="">
  <img src="docs/screenshots/doorbell-live-dark.png" width="260" alt="">
</p>

## Agents / MCP

Ouvre **Réglages → Interface agent**, clique sur **Copier les instructions** et colle le texte dans Claude Code, Codex, Cursor ou tout autre agent. L’agent trouve la CLI intégrée, enregistre le serveur MCP dans sa propre configuration et vérifie en listant tes appareils. Le même texte (chemin renseigné) est affiché par `mijiabar setup-prompt` :

```text
Lis https://raw.githubusercontent.com/neardws/MijiaBar/main/docs/AGENT_SETUP.fr.md et suis ces étapes pour configurer MijiaBar comme outil MCP.
Chemin de la CLI : /Applications/MijiaBar.app/Contents/Resources/bin/mijiabar
Ne modifie l’état d’aucun appareil sans mon accord.
```

Instructions complètes pour les agents : [docs/AGENT_SETUP.fr.md](docs/AGENT_SETUP.fr.md)

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

## Où sont stockées les données

- Session de connexion : trousseau macOS, service `com.neardws.MijiaBar` (compte `session`). Supprimée à la déconnexion.
- Cache des appareils `devices.json`, préférences `prefs.json` (favoris, alias, masquage, région), politique agent `agent.json` et cache des spécifications MIoT `spec-index.json` + `specs/<modèle>.json` — tout dans `~/Library/Application Support/MijiaBar/`, avec les droits 600.
- Langue de l’interface : `MijiaBarLang` dans les UserDefaults (partagée par l’app et la CLI ; `MIJIABAR_LANG` a priorité).
- Aucune donnée n’est envoyée ailleurs qu’aux serveurs Xiaomi, à tes appareils sur le réseau local et à miot-spec.org (spécifications publiques).

## Remerciements

Design des animations par [@skyswordw](https://github.com/skyswordw) ([#1](https://github.com/neardws/MijiaBar/pull/1)). Détails des protocoles issus de [python-miio](https://github.com/rytilahti/python-miio), [Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) et [ha_xiaomi_home](https://github.com/XiaoMi/ha_xiaomi_home). Interface inspirée de l’app de climatisation de [@the_mcnaveen](https://x.com/the_mcnaveen).

Licence MIT.
