# AnyUsagePin

**Pin your AI subscription quotas.**

AnyUsagePin is a Flutter-powered macOS menu bar app for pinning AI subscription quotas. It starts with accounts already authorized in your coding agent—even when they are not signed in to the provider's desktop app. Track remaining quota, balances, and reset times across multiple accounts—without managing another set of provider logins.

![macOS 12+](https://img.shields.io/badge/macOS-12%2B-000000?logo=apple&logoColor=white)
![Built with Flutter](https://img.shields.io/badge/Built_with-Flutter-02569B?logo=flutter&logoColor=white)
![OMP supported](https://img.shields.io/badge/Agent-OMP-168575)

> **Available today: OMP.** OpenCode and Pi are on the [roadmap](#roadmap), not available integrations. Accounts appear when the selected agent can report their usage.

[Why this app](#why-anyusagepin) · [Get started](#quick-start) · [Customize](#make-the-menu-bar-yours) · [Supported agents](#supported-agents) · [Roadmap](#roadmap) · [Privacy](#privacy-and-local-data) · [Contribute](#development-and-contributing)

## Why AnyUsagePin?

Your coding agent is already where your accounts live. AnyUsagePin starts there—not with the login state of the native Codex, Claude, or Antigravity apps. The long-term goal is subscription pinning across sources; agent-authorized accounts come first.

An account signed in to OMP can appear here even if it is not signed in to that provider's desktop app, provided OMP exposes its usage. Work and personal accounts stay separate, including two subscriptions from the same provider.

- **Account-first, not provider averages.** Each account and organization/project scope keeps its own quota and identity.
- **Pin what matters.** Keep several subscriptions in the menu bar, with up to two rows per pin. No automatic account selection or quota-based reshuffling.
- **Mix text and bars freely.** Pair a countdown bar with remaining quota text—or quota bars with countdown text. Each channel can use a different window.
- **Choose your dashboard.** Switch between account cards, a compact table, and a pinned-account focus view, with system/light/dark themes and adjustable density.
- **Know when data is uncertain.** Missing values, expired resets, and failed queries remain visible instead of becoming reassuring zeroes.
- **Keep it local.** No app-managed provider token store, cloud account, or telemetry.

## Quick start

### Requirements

- **macOS 12.0 or later.**
- **Flutter with Dart 3.12.2 or later within the supported 3.x range**, plus Xcode and the Flutter macOS toolchain. The project has been built with Flutter 3.44.9 / Dart 3.12.2.
- **OMP installed and already authenticated**, with support for `omp usage --json`. OMP 18.5.0 has been exercised with this app.

First, confirm that OMP can report your usage:

```sh
omp usage --json
```

Then clone this repository and run these commands from its root:

```sh
flutter pub get
flutter build macos --release
open -a "$PWD/build/macos/Build/Products/Release/AnyUsagePin.app"
```

To open the dashboard immediately:

```sh
open -a "$PWD/build/macos/Build/Products/Release/AnyUsagePin.app" --args --show
```

The verified artifact is a **local Release build**; Developer ID signing and notarized distribution have not been verified.

The macOS bundle identifier is `com.terryhuanghd.AnyUsagePin`, defined in [AppInfo.xcconfig](macos/Runner/Configs/AppInfo.xcconfig). It is independent of the app's local storage directory, so changing the identifier does not reset existing pins or preferences.

### Your first pins

1. Open the menu bar app and review the accounts reported by OMP.
2. Open **Customize / 客製化** and add a pin for an account.
3. Choose the upper/lower row's text and bar windows independently.
4. Review the preview, finish editing, then click **Apply / 套用** to save.

The app has no Dock icon. With no pins, an app launcher provides the menu bar entry; once you add pins, any pin opens the dashboard. Escape, closing the panel, or switching apps hides the panel without stopping polling. Quit through settings or a status item's right-click menu.

**OMP not found when launched from Finder?** Set its full executable path in the gear settings. Leaving the path empty searches PATH and common Bun/Homebrew install locations. The displayed profile comes from the launch environment's `OMP_PROFILE`, defaulting to `default`; it is read-only, not an account or workspace switcher.

Avoid running Debug and Release together: they use the same local settings.

## Make the menu bar yours

Each pin belongs to **one account** and has up to **two independently configured rows**. Each row has two optional channels:

| Channel | Display options | Window selection |
| --- | --- | --- |
| Text | Remaining quota, used quota, reset countdown, or off | Any available window for the pinned account |
| Bar | Remaining quota ratio, used quota ratio, remaining-time ratio, or off | Independently selected; does not have to match the text |

Examples of configurations—not live usage values:

| Goal | Text | Bar |
| --- | --- | --- |
| Watch allowance and time together | Five-hour remaining quota | Five-hour reset countdown |
| Watch two constraints in one row | Weekly remaining quota | Five-hour reset countdown |
| Prefer a time label | Five-hour reset countdown | Weekly used quota |
| Keep it minimal | Off | Remaining quota ratio |

Use text only, bars only, or both. Turn both rows off for an icon-only pin. Set the provider icon, shared color, optional label, and label width separately, then drag pins into the order you want.

The editor's preview stays below the scrollable settings. Changes remain a draft until **Apply**; **Cancel** does not partially save. Resetting display defaults does not reset the CLI path or log out accounts.

A countdown bar means:

```text
remaining-time ratio = time until reset / source-reported window duration
```

It updates on the existing 30-second clock. Missing reset times or window durations produce an outlined `?` bar, not a fabricated 0%. A healthy text channel cannot conceal a missing or stale bar; tooltips identify each channel's window and source age.

There is no fixed product-level pin limit. macOS decides which status items fit; the app does not collapse, merge, replace, or reorder them automatically. All configured pins remain manageable in Customize.

Official provider logos identify subscriptions. Automatic menu bar color uses AppKit template tint, independently of the app's light/dark theme; custom colors remain available.

## Supported agents

| Agent | Status | Data source and boundaries |
| --- | --- | --- |
| **OMP** | Available | `omp usage --json`; multiple providers and accounts, limited to the usage reports OMP exposes |
| **OpenCode** | Planned integration | V2 token-free account inventory plus a supported per-account quota bridge; not implemented in this app |
| **Pi** | Planned research/integration | An extension bridge with explicit account inventory and structured quota; not implemented in this app |

OMP provider reports exercised with the app include **OpenAI / Codex, Claude, Google Antigravity, Grok, and Cursor**. Availability depends on your OMP version, authenticated accounts, and installed usage adapters. This is not a guarantee that every plan or login is discoverable.

**An agent's local token statistics are not subscription quota.** The app displays provider limits reported through the agent rather than deriving remaining allowances from local token spend. Anthropic-direct subscriptions and Claude pools inside Antigravity are distinct sources; API-key spend and subscription limits must not be conflated either.

### Refresh and data quality

- Polls OMP about every five minutes, including while the dashboard is closed. Only one query runs at a time.
- Manual refresh performs a normal query; it does not invalidate OMP's cache or force provider requests.
- Retains each meter's original observation time. Duplicate observations replace only older copies of the same meter; independent windows and shared pools are not added together.
- Preserves units such as percent, USD, credits, and requests instead of synthesizing a total percentage.
- Keeps last-known data after a failed query, with its age and warning. Missing/future timestamps, data at least ten minutes old, and passed reset deadlines are flagged.
- A passed reset deadline means **waiting for an update**, not proof that quota has refilled.
- Missing accounts keep their existing pin binding and an unavailable marker; pins are never reassigned to another account.

Full account emails remain visible alongside aliases. Normal quota rows can be hidden, but missing, stale, and error rows remain visible, including problems with unpinned accounts in the focus layout.

## Roadmap

These are directions, not release-date promises. **Only OMP is available today.** New adapters must expose real account-scoped data before appearing as usable sources.

### Next: more agents, the same account-first experience

- [ ] **Complete OMP account discovery.** Add a token-free inventory bridge so logins without a usage adapter can be distinguished from absent accounts and shown as “usage unavailable,” rather than silently disappearing or becoming 0%.
- [ ] **OpenCode V2 integration.** Combine token-free account inventory with an explicitly supported quota bridge such as a user-installed `opencode-quota`. `stats --json` is local statistics, not remaining subscription quota; headless bridge exports may be cached and must retain their real timestamps.
- [ ] **Pi integration.** Evaluate extensions that expose stable multi-account inventory and structured quota contracts. Authentication readiness alone is not a usage API; do not scrape arbitrary TUI output.
- [ ] **Safe agent switching.** Keep snapshots, pins, aliases, ordering, and layout separate per agent. Poll only the active source, cancel outgoing queries where possible, and reject late replies—even after an A → B → A switch. Returning to an agent restores its display settings without changing its active provider/account or profile. Failed switches must not silently select another agent.

### Display candidates

The original product design also identified these options for further discussion; they are **not implemented or committed**:

- Configurable table columns and numeric precision.
- Provider/account/resource ordering and grouping, reset-time sorting, and remaining-quota sorting only within comparable resource types.
- Absolute reset times alongside countdowns.
- Whole-account hiding with visible error summaries, rather than hiding authentication or refresh problems.
- Per-agent appearance overrides and launch-behavior controls.

Cloud sync, app-owned cloud accounts, usage proxying, token/cost history analytics, and notifications are **outside the committed scope**. Cross-agent account merging and profile switching are not implied by multi-agent support.

<details>
<summary>Integration acceptance criteria and research references</summary>

Every adapter should declare whether account inventory is complete or partial, whether quota can be fetched per account without changing the agent's active account, whether data is live/cached/exported, and which providers or resources are unsupported or cannot be reliably attributed.

A known login without a quota interface should remain visible as unavailable. An incomplete inventory must be labeled incomplete. No fabricated quotas, model probes, credential-database scraping, or account switching to collect usage.

Interfaces vary by agent version and extension. Research references:

- [OMP usage CLI](https://github.com/can1357/oh-my-pi/blob/main/packages/coding-agent/src/cli/usage-cli.ts), [account filtering](https://github.com/can1357/oh-my-pi/blob/main/packages/coding-agent/src/slash-commands/helpers/usage-accounts.ts), [usage types](https://github.com/can1357/oh-my-pi/blob/main/packages/ai/src/usage.ts), and [cache / auth broker](https://github.com/can1357/oh-my-pi/blob/main/docs/auth-broker-gateway.md).
- [OpenCode V2 accounts](https://opencode.ai/v2/docs/cli/providers/) and [JSON inventory implementation](https://github.com/anomalyco/opencode/blob/v2/packages/cli/src/commands/handlers/auth/list.ts). The researched inventory interface is `opencode auth list --format json`.
- [OpenCode quota external integration](https://github.com/slkiser/opencode-quota/blob/main/docs/readme/external-integration.md). Its headless `show --json` reads cached reports rather than guaranteeing live provider quota.
- [Pi CLI](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/cli.md). `auth check --json` reports authentication readiness, not quota.

</details>

## Privacy and local data

AnyUsagePin does not provide provider login/logout, maintain provider tokens, directly read or modify the agent's credential database, switch active accounts, or send model probes. CLI calls use fixed arguments rather than interpolated shell commands; provider stderr is not surfaced in the UI.

**The agent CLI still owns its authentication behavior.** Running it may refresh OAuth or update its own cache/history/credential state. The entire query cannot be described as side-effect-free. The macOS app is not sandboxed so it can execute your installed CLI.

Settings and normalized snapshots stay on your Mac:

```text
~/Library/Application Support/AnyUsagePin/
  preferences.json
  snapshot-omp.json
```

Snapshots include **full emails, account/organization identifiers, and quota data**. They do not persist raw CLI payloads, access tokens, refresh tokens, API keys, or arbitrary metadata. Redact screenshots and fixtures before sharing them publicly.

<details>
<summary>Storage permissions, migration, and recovery</summary>

The storage directory uses permissions `0700`, files use `0600`, and writes are serialized and atomically replaced. Corrupt settings are reported rather than silently overwritten; an explicit reset first preserves the damaged file as a backup.

**Upgrading from Cross Agent Usage:** quit the old app before launching AnyUsagePin. If `Application Support/AnyUsagePin` does not exist, the first storage operation moves the previous `Application Support/Cross Agent Usage` directory to the new name, preserving pins, aliases, preferences, snapshots, and recovery backups. A pre-existing AnyUsagePin directory takes precedence; the app does not merge or overwrite either directory. A legacy path that is not a real directory is rejected rather than followed or replaced.

Display preferences use schema v2; normalized usage snapshots retain schema v1. Legacy v1 preferences migrate in memory, preserving the visible text/quota-bar configuration. Old icon-only pins do not enable their previously hidden channels or labels, and old reset text does not automatically gain a countdown bar. Loading does not rewrite the original file; the next Apply saves the new preference format.

</details>

## Development and contributing

The [Flutter layer](lib/) handles the dashboard, settings, previews, polling, and normalized data. A thin [Swift/AppKit layer](macos/Runner/) handles native status items and the retained dashboard panel. Brand assets are bundled; the app does not fetch provider icons at runtime.

```sh
flutter analyze
flutter test test/core_test.dart
flutter run -d macos
```

The [regression suite](test/core_test.dart) covers account/scope isolation, shared pools, out-of-order observations, units and reset boundaries, countdown ratios, subprocess cancellation/output limits, error privacy, persistent settings, migrations, and corrupt-file protection.

Issues and pull requests are welcome for reproducible bugs, display improvements, and real agent integrations. For bug reports, include macOS, Flutter, and agent versions plus reproduction steps—but **not credentials, private emails, or unredacted usage payloads**. For an adapter proposal, include its token-free inventory/quota contract and the limitations listed in the roadmap.

### Brand assets and attribution

Provider marks remain the property of their respective owners. Their use identifies services; it does not imply endorsement or affiliation. Vector sources live in [assets/provider_sources/](assets/provider_sources/), with raster assets in [assets/providers/](assets/providers/).

| Subscription | Official asset source |
| --- | --- |
| OpenAI / Codex | [OpenAI brand guidelines](https://openai.com/brand/) and [logo archive](https://cdn.openai.com/brand/openai-logos.zip), using the Blossom |
| Claude | Splat mark from the [official Claude website](https://claude.com/) |
| Cursor | [Cursor brand guidelines](https://cursor.com/brand) and [brand assets](https://ptht05hbb1ssoooe.public.blob.vercel-storage.com/assets/brand/cursor-brand-assets.zip), using the 2D Cube |
| Grok | Grok mark from the [official xAI website](https://x.ai/) |
| Antigravity | [Official Google Antigravity icon](https://antigravity.google/assets/image/antigravity-logo.png) |

### License

No project license has been declared in this repository. Public source availability does not by itself grant an open-source license; provider assets retain their owners' rights.
