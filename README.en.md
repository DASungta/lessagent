<div align="center">

<p>
  <img src="docs/assets/logo.png" width="112" alt="T3 Code Harmony Logo" />
</p>

<h1>T3 Code Harmony</h1>

<p>
  A native HarmonyOS client for <strong>T3 Code</strong> built with <strong>ArkTS + ArkUI</strong> —<br />
  connect directly to your desktop or remote T3 Code server to drive coding agents, inspect diffs, and operate dev tools from your phone.
</p>

<p>
  <img src="https://img.shields.io/badge/HarmonyOS_NEXT-API_24%2B-0A59F7?style=flat-square" alt="HarmonyOS API 24+" />
  <img src="https://img.shields.io/badge/ArkTS_%2B_ArkUI-Native-18181B?style=flat-square" alt="ArkTS + ArkUI Native" />
  <a href="https://github.com/DASungta/t3code-harmony/releases/tag/v0.1.3-preview"><img src="https://img.shields.io/badge/Preview-v0.1.3--preview-2563EB?style=flat-square" alt="Preview v0.1.3-preview" /></a>
  <img src="https://img.shields.io/badge/Tests-575_passing-16A34A?style=flat-square" alt="575 Tests Passing" />
  <img src="https://img.shields.io/badge/License-MIT-52525B?style=flat-square" alt="MIT License" />
</p>

<p>
  <a href="README.md">简体中文</a> · <strong>English</strong>
</p>

<p>
  <a href="#screenshots">Screenshots</a> ·
  <a href="#features">Features</a> ·
  <a href="#quick-guide">Quick Guide</a> ·
  <a href="#development--build">Development & Build</a> ·
  <a href="#project-structure">Project Structure</a> ·
  <a href="#documentation">Documentation</a>
</p>

</div>

---

**T3 Code Harmony** is an independent native HarmonyOS client for [T3 Code](https://github.com/pingdotgg/t3code). Designed as a thin client, all coding agent execution and repository operations run on your desktop or remote server while the phone delivers a responsive native ArkUI experience verified on real HUAWEI Mate 60 Pro / Mate 70 Pro hardware.

## Screenshots

| Home Workbench | Chat & Code Highlighting | File Browser & Native Mermaid | Git Status & Commit |
| :---: | :---: | :---: | :---: |
| <img src="docs/screenshots/promo-v0.1.1/01-home-light.jpeg" width="200" alt="Home Workbench (Light)" /> | <img src="docs/screenshots/promo-v0.1.1/02-chat-light.jpeg" width="200" alt="Chat and Code Highlighting (Light)" /> | <img src="docs/screenshots/promo-v0.1.1/03-files-mermaid-light.jpeg" width="200" alt="File Browser and Native Mermaid (Light)" /> | <img src="docs/screenshots/promo-v0.1.1/04-git-light.jpeg" width="200" alt="Git Status and Commit (Light)" /> |

| Grouped Settings | About & Version v0.1.1 | Home Workbench (Dark) | Chat Detail (Dark) |
| :---: | :---: | :---: | :---: |
| <img src="docs/screenshots/promo-v0.1.1/05-settings-light.jpeg" width="200" alt="Grouped Settings (Light)" /> | <img src="docs/screenshots/promo-v0.1.1/06-about-version-light.jpeg" width="200" alt="About and Version v0.1.1" /> | <img src="docs/screenshots/promo-v0.1.1/07-home-dark.jpeg" width="200" alt="Home Workbench (Dark)" /> | <img src="docs/screenshots/promo-v0.1.1/08-chat-dark.jpeg" width="200" alt="Chat Detail (Dark)" /> |

> Captured on a real HUAWEI Mate 60 Pro running a demo repository fixture.

## Features

- **Multi-Environment Workbench & Thread Management**
  - Direct pairing over LAN, SSH, or loopback (manual entry, QR code scan, or deep link) plus T3 Connect / Cloud Relay support (`OAuth + PKCE + DPoP`).
  - Floating bottom bar (`Chats / Pull Requests / Usage / Settings`) paired with a quick **New Task** action; repository/path/flat thread grouping, search, environment & project filters, pin, snooze, settle, archive, and multi-draft restoration.
- **Native Chat & Rich Media Rendering**
  - Pure ArkUI message timeline with turn-grouped collapsible work logs & checkpoints, subagent thread inspection, and approval / secret request cards.
  - Native Markdown rendering, syntax-highlighted code blocks (adjustable font size `8–18` and word wrap), LaTeX math, and native ArkUI Mermaid diagrams (flowchart, sequence, class, and state diagrams), plus built-in offline Chinese voice dictation for drafts.
- **Mobile Developer Toolbox**
  - Workspace file browser and full-text search, line-selectable Diff viewer with inline review comments, and full Git workflows (status, stage, commit, branches, push/pull).
  - GitHub Pull Requests reader / review / guide tour, one-tap remote ANSI terminal in the chat top bar (with scrollback & copy), remote browser preview, and iOS Simulator / Android Emulator device preview.
- **Design System & HarmonyOS Integration**
  - 75 symmetric Light/Dark semantic color tokens (`base/element/color.json` & `dark/element/color.json`) guarded by automated WCAG AA (`>= 4.5:1`) contrast tests.
  - System share sheet integration (**T3 Harmony**) to import images and files into task drafts, plus a `2×2` home-screen shortcut widget and launcher quick actions.

## Quick Guide

| Action | Where to Start |
|---|---|
| **Start a task or resume a chat** | Tap the **New Task** button at the bottom-right of the floating bar, or select an existing thread. Switch environment, project, model, and mode beneath the composer. |
| **Manage connected environments** | Tap the `T3 Code` wordmark in the top-left of the home screen to pair manually, scan a QR code, import a deep link, or manage multiple routes. |
| **Search & filter threads** | Use the search or filter icon in the home top-right bar to search across threads or scope by environment and project. |
| **Files, Diff, Git, PRs, Terminal & Preview** | Inside a chat, tap the terminal icon in the top bar for direct shell access, or open **More** (`···`) for Files, Diff, Git, Pull Requests, Browser Preview, and Device Preview. |
| **Import via system share sheet** | Pick an image or file in Gallery / Files → Share → **T3 Harmony**, verify the preview and target project, and save it as a draft. |
| **Dictate drafts in Chinese** | Open **Tools → Voice Input** in the chat composer to transcribe spoken Chinese directly into the input box. |
| **Code typography, projects, worktrees & schedules** | Switch to the **Settings** tab at the bottom to configure code font size (`8–18`) / word wrap, add projects, manage source control, override per-project worktree settings, create scheduled tasks, and switch themes. |

## Development & Build

### Download Preview Sideload Package

This project is currently in **Preview**. You can download the prebuilt **unsigned debug-mode HAP** (`t3code-harmony-v0.1.3-preview-unsigned.hap`, with its `.sha256` checksum) from [GitHub Releases (`v0.1.3-preview`)](https://github.com/DASungta/t3code-harmony/releases/tag/v0.1.3-preview).

> **HarmonyOS NEXT Sideloading Note**: HarmonyOS NEXT rejects unsigned HAPs as well as debug packages signed for another device's UDID. After downloading the `unsigned.hap`, sign it using your own HUAWEI Developer account via a HarmonyOS sideloading/signing helper (such as AutoInstaller) or `hap-sign-tool` + `hdc`, or clone the repo and build with DevEco Studio automatic signing.

### Prerequisites

- **DevEco Studio 6.1.1+** with HarmonyOS SDK `6.1.1(24)` (`API 24+`)
- **Node.js 22+** (required for `--experimental-strip-types` host unit tests)
- A running [T3 Code](https://github.com/pingdotgg/t3code) server on your desktop or remote machine

### Testing & Building

```bash
git clone https://github.com/DASungta/t3code-harmony.git
cd t3code-harmony

# Run all host unit tests and theme contrast checks (575/575)
node --experimental-strip-types --test tests/*.test.mjs

# Build the Debug HAP (override DevEco Studio path via DEVECO_HOME if needed)
./scripts/build.sh
```

> **Signing Note**: Before installing onto a physical device, configure your own HarmonyOS debug signing profile in DevEco Studio / `build-profile.json5`. Never commit personal certificates or keys to public repositories.

## Project Structure

```text
t3code-harmony/
├── AppScope/                         # App metadata (app.json5), layered icon & app name
├── entry/src/main/
│   ├── ets/
│   │   ├── common/                   # Theme.ets (typography, spacing, radius & size tokens)
│   │   ├── components/               # Feature panels and ui/ shared design-system components
│   │   ├── pages/                    # Main entry page Index.ets
│   │   ├── protocol/                 # Server protocol, state reducers, Markdown/Diff/Mermaid parsers
│   │   ├── services/                 # Networking, pairing/auth, remote terminal & OS bridges
│   │   ├── storage/                  # Local preferences, profiles & draft persistence
│   │   ├── entryability/             # Main Ability, share sheet & deep-link handlers
│   │   └── formextension/            # 2×2 home-screen widget extension
│   └── resources/
│       ├── base/element/color.json   # Light theme: 58 semantic color tokens
│       ├── dark/element/color.json   # Dark theme: 58 semantic color tokens
│       └── rawfile/                  # Bundled license text & connection presets
├── scripts/                          # Build script, replay helpers & device keep-awake tool
├── tests/                            # Host unit tests & Light/Dark WCAG AA contrast checks
└── docs/                             # Brand logo (assets/), design system, plans, shots & evidence
```

## Documentation

- **Design & Visual System**: [Design System & Tokens](docs/design/README.md) · [Interactive Style Guide](docs/design/style-guide.html) · [Visual Refresh Device Evidence (Steps 2–6b)](docs/evidence/visual-refresh)
- **Progress & Roadmap**: [Development Status](docs/development-status.md) · [Full Mobile Migration Plan (R0–R8)](docs/full-mobile-migration-plan.md)
- **Reference Ledgers**: [Mobile Capability Matrix](docs/r0-mobile-capability-matrix.md) · [Route Ledger](docs/r0-route-ledger.md) · [R6–R8 Acceptance](docs/r6-r8-acceptance.md)
- **Device Tooling & Handoff**: [Device Keep-Awake Guide](docs/device-keep-awake.md) · [Developer Handoff Notes (ZH)](docs/开发交接.md)

## Scope & Status

`v0.1.1` delivers the core end-to-end mobile workflow and completed visual refresh on real HUAWEI Mate 60 Pro and Mate 70 Pro devices. External-dependency edge cases (such as an external iOS Simulator host, full physical Bluetooth keyboard coverage, production cloud-relay deployment, and tablet/foldable multi-form-factor matrices) remain tracked in the documentation; host unit tests do not replace real-device verification.

## Upstream & License

- Upstream repositories: [pingdotgg/t3code](https://github.com/pingdotgg/t3code) · [DASungta/t3code](https://github.com/DASungta/t3code)
- License: [MIT License](entry/src/main/resources/rawfile/t3code-license.txt) (bundled license copy).
