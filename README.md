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
- **Pin what matters.** Keep several subscriptions together in one menu bar item, with up to two rows per pin. No automatic account selection or quota-based reshuffling.
- **Mix text and bars freely.** Pair a countdown bar with remaining quota text—or quota bars with countdown text. Each channel can use a different window.
- **Choose your dashboard.** Switch between account cards, a compact table, and a pinned-account focus view, with system/light/dark themes and adjustable density.
- **Know when data is uncertain.** Missing values, expired resets, and failed queries remain visible instead of becoming reassuring zeroes.
- **Keep it local.** No app-managed provider token store, cloud account, or telemetry.

## Quick start

### Install the macOS app

**Current release: [AnyUsagePin 1.1.0](https://github.com/TerryHuangHD/any-usage-pin/releases/tag/v1.1.0) (build 5).** Adds the B1 Orbit app icon, account-scoped reset seats and soonest expiry, a precise 10–50 pt pin bar-length slider, and a compact two-line usage-panel footer with consolidated Options actions.

1. Download the **macOS universal DMG** from [GitHub Releases](https://github.com/TerryHuangHD/any-usage-pin/releases/latest). For checksum verification, also download `appcast.xml` and `SHA256SUMS` into the same directory and run `shasum -a 256 -c SHA256SUMS`.
2. Open the DMG and drag **AnyUsagePin.app** to **Applications**.
3. Open AnyUsagePin from Applications. It runs in the menu bar, not the Dock.

The app requires **macOS 12.0 or later** and **OMP installed and authenticated**; Flutter and Xcode are not needed to run a downloaded release. The universal app contains Apple Silicon and Intel binaries. macOS may still show its normal first-launch confirmation for a downloaded app.

### Build from source

- **macOS 12.0 or later.**
- **Flutter with Dart 3.12.2 or later within the supported 3.x range**, plus Xcode and the Flutter macOS toolchain. The project has been built with Flutter 3.44.9 / Dart 3.12.2.
- **OMP installed and already authenticated**, with support for `omp usage --json`. OMP 18.5.0 has been exercised with this app.

First, confirm that OMP can report your usage:

```sh
omp usage --json
```

For a local development build without company signing credentials, clone this repository and run these commands from its root:

```sh
flutter pub get
flutter build macos --debug
open -a "$PWD/build/macos/Build/Products/Debug/AnyUsagePin.app"
```

To open the usage panel immediately:

```sh
open -a "$PWD/build/macos/Build/Products/Debug/AnyUsagePin.app" --args --show
```

Release builds use **Developer ID Application: LI-SHENG TECHNOLOGY CO., LTD. (V6C4PTHC4J)** with Hardened Runtime and secure signing timestamps. The universal app and DMG have both passed Apple notarization and ticket stapling; Gatekeeper identifies them as **Notarized Developer ID**. The final DMG has been mounted and its app exercised on Apple Silicon.

The macOS bundle identifier is `com.terryhuanghd.AnyUsagePin`, defined in [AppInfo.xcconfig](macos/Runner/Configs/AppInfo.xcconfig). It is independent of the app's local storage directory, so changing the identifier does not reset existing pins or preferences.

### Your first pins

1. Open the menu bar app and review the accounts reported by OMP.
2. Open the panel's bottom **Options / 選項** menu and choose **Settings / 設定…**, then open **Customize / 客製化顯示** and add a pin for an account.
3. Choose the upper/lower row's text and bar windows independently.
4. Review the preview, finish editing, then click **Apply / 套用** to save.

The app has no Dock icon. All configured pins share one menu bar item, displayed side by side in their configured order. Clicking anywhere in the group opens the usage panel; with no pins, the same item shows the app launcher. This compact panel is read-only: it shows account-scoped remaining quotas, progress, reset timing, and data-quality warnings. Its compact fixed footer keeps **AnyUsagePin and the installed version** on the first line, with query progress or the next refresh countdown on the second. Hover over the refresh line for the original snapshot age and configured interval. A single **Options / 選項** menu contains manual refresh, settings, app-update status/actions, and quit. Manual refresh is disabled during a query. Escape, clicking outside, or switching apps hides only the panel without stopping polling.

Source settings, pin creation/editing, account aliases/order, hidden windows, and display customization live in a separate normal macOS settings window with close, minimize, and resize controls. It stays open when it loses focus, and the usage panel can open independently while settings remain visible. Closing settings hides the retained window; reopening preserves unsaved edits. Customization still requires **Apply / 套用** to save or **Cancel / 取消** to discard. Quit through the footer's **Options / 選項** menu, settings, or a status item's right-click menu, which also provides **Settings…** and, in Sparkle-enabled builds, **Check for Updates…**.

Under **App behavior / App 行為**, two settings save immediately without applying or discarding source-form edits:

- **Launch at login / 開機自動啟動:** off until enabled. The switch reads the actual system registration rather than a separate JSON flag. On macOS 13+, it uses `SMAppService.mainApp`; if approval is required, settings shows a pending state and a button to open the system Login Items page. Returning to the settings window rereads the system state. On macOS 12, it installs/removes this app's user LaunchAgent at `~/Library/LaunchAgents/com.terryhuanghd.AnyUsagePin.plist`.
- **Refresh frequency / Refresh 頻率:** choose any whole minute from **1 through 10**, with **5 minutes** retained as the default. The choice survives relaunch and immediately replaces the waiting background timer. An already-running query finishes normally, then schedules the next query using the latest interval.

The panel, settings, customization, and editors share a neutral palette with system-blue controls. Content uses native `NSGlassEffectView` on macOS 26 and later, with `NSVisualEffectView` material on earlier releases. The settings window retains a standard system title bar and system window background; its glass content does not replace the native window controls.

**OMP not found when launched from Finder?** Choose **Options / 選項 → Settings / 設定…** in the footer and set the full executable path under source settings. Leaving the path empty searches PATH and common Bun/Homebrew install locations. The displayed profile comes from the launch environment's `OMP_PROFILE`, defaulting to `default`; it is read-only, not an account or workspace switcher.

Avoid running Debug and Release together: they use the same local settings.

### In-app updates

Starting with **1.0.2 (build 3)**, releases include [Sparkle 2](https://sparkle-project.org/) updates. Published 1.0.0 / 1.0.1 apps do not contain an updater; install 1.0.2 or a later release manually once before using in-app updates.

The app queries update information on launch and whenever the usage panel opens, merging overlapping checks. Background checks do not interrupt startup or open an update dialog. When a compatible, non-skipped update is available, the footer's app name/version turns blue and its **Options / 選項** menu shows **新版 … 可用 / 下載更新…**. The installed version remains visible; hovering over it also shows the app-update status. Choosing **下載更新…** opens Sparkle's standard download, verification, installation, and relaunch flow. No automatic installation is enabled.

The footer's **Options / 選項** menu distinguishes a failed query (**無法確認最新版本**) from no installable update (**沒有可安裝的更新**); the latter also covers skipped or system-incompatible versions, not just being on the latest version. Both the footer's **檢查更新…** and the right-click **Check for Updates…** actions are user-initiated and can rediscover a skipped version. Sparkle's automatic-check preference is respected.

The fixed feed is [`appcast.xml` on GitHub Pages](https://terryhuanghd.github.io/any-usage-pin/appcast.xml); update archives come from GitHub Releases. Update queries and downloads use HTTPS, and a failed query does not affect quota display.

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

Under **Customize / 客製化顯示 → Panel appearance / 面板外觀**, adjust **Menu bar pin bar length / 選單列 pin 條狀長度** with a slider from **10 to 50 pt**, in 1 pt steps, defaulting to **25 pt**. This shared setting updates all quota/countdown bars, including unknown outlined bars. Previews reflect the draft immediately; the menu bar updates after **Apply**.

The editor's preview stays below the scrollable settings. Changes remain a draft until **Apply**, which saves and updates the display without leaving customization; you can continue editing or apply again. **Cancel** and the back button discard only changes made since the last successful apply. Resetting display defaults does not reset the CLI path or log out accounts.

A countdown bar means:

```text
remaining-time ratio = time until reset / source-reported window duration
```

It updates on the existing 30-second clock. When OMP omits the reset time (or returns `null`) and supplies a positive window duration, the window has not started: the countdown shows the full duration (for example, **5時0分** for a five-hour window) and a full bar, without ticking down until OMP reports an actual reset time. The panel and pin tooltips identify this as **尚未開始計時**. This does not refill the remaining quota. Missing/nonpositive window durations or malformed reset times still produce an outlined `?` bar, not a fabricated countdown. A healthy text channel cannot conceal a missing or stale bar; tooltips identify each channel's window and source age.

OpenAI Codex and Claude account panels also show **Reset seats** (OMP's reported available saved-reset count) and **Soonest expires** (the earliest valid expiry among available credits). Expiry times use the Mac's local time. Redeemed credits and credits already expired at the source observation are excluded; optional missing credit statuses are accepted. A reported zero displays **0** with no expiry (`—`), while missing or malformed counts stay **無資料**, not zero. Reset credits remain isolated by account, retain their own observation time through caching/merging, and are read-only here—the app does not redeem them.

There is no fixed product-level pin limit. macOS decides whether the combined menu bar item fits; a wide group may be hidden when menu bar space is insufficient. The app does not drop, collapse, replace, or reorder pins automatically. All configured pins remain manageable in Customize.

Official provider logos identify subscriptions. Automatic colors follow the menu bar's appearance, independently of the app's light/dark theme; each pin retains its custom color when mixed with automatic-color pins.

## Supported agents

| Agent | Status | Data source and boundaries |
| --- | --- | --- |
| **OMP** | Available | `omp usage --json`; multiple providers and accounts, limited to the usage reports OMP exposes |
| **OpenCode** | Planned integration | V2 token-free account inventory plus a supported per-account quota bridge; not implemented in this app |
| **Pi** | Planned research/integration | An extension bridge with explicit account inventory and structured quota; not implemented in this app |

OMP provider reports exercised with the app include **OpenAI / Codex, Claude, Google Antigravity, Grok, and Cursor**. Availability depends on your OMP version, authenticated accounts, and installed usage adapters. This is not a guarantee that every plan or login is discoverable.

**An agent's local token statistics are not subscription quota.** The app displays provider limits reported through the agent rather than deriving remaining allowances from local token spend. Anthropic-direct subscriptions and Claude pools inside Antigravity are distinct sources; API-key spend and subscription limits must not be conflated either.

### Refresh and data quality

- Polls OMP at the configured 1–10 minute interval (five minutes by default), measured from the end of the previous query, including while the usage panel and settings window are closed. Only one query runs at a time.
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
- Per-agent appearance overrides.

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

Update requests go to GitHub Pages and GitHub Releases over HTTPS. They do not include provider credentials, account identifiers, or quota snapshots. Sparkle system profiling is disabled; hosting services still receive normal download/request metadata.

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

App preferences use schema v2; normalized usage snapshots retain schema v1. Preferences without a refresh interval retain the five-minute default; those without a pin bar length use 25 pt. Previously saved Level 1–4 pin bar lengths migrate to their equivalent 16, 24, 32, or 40 pt values. Legacy v1 preferences migrate in memory, preserving the visible text/quota-bar configuration. Old icon-only pins do not enable their previously hidden channels or labels, and old reset text does not automatically gain a countdown bar. Loading does not rewrite the original file; the next preference change saves the new preference format.

Normalized snapshots preserve OMP's not-started reset marker without inventing a reset timestamp. Older cache files without that marker keep an unknown reset state until a successful OMP refresh supplies the source semantics.

</details>

## Development and contributing

The [Flutter layer](lib/) owns one usage controller, settings/customization, previews, polling, and normalized data. The [Swift/AppKit layer](macos/Runner/) renders one native status item containing all pins and the read-only usage panel from controller projections, and hosts the single Flutter engine in a separate retained settings window. Panel dismissal is scoped to the panel, not the settings window. Brand assets are bundled; the app does not fetch provider icons at runtime.

**Initial app icon explorations:** [Compare the first four directions](assets/icon_candidates/index.html) locally, or view the [light](assets/icon_candidates/preview-light.png) / [dark](assets/icon_candidates/preview-dark.png) previews: A **Quota Pin**, B **Orbit**, C **Stack**, and D **U-Pin**. Each includes a 1024×1024 SVG source and transparent PNGs at 16, 32, 64, 128, 256, 512, and 1024 pixels. These exploration sources and previews are excluded from the Flutter bundle.

**macOS app icon: B1 Orbit Original.** The [SVG source](assets/icon_candidates/b-orbit.svg) is exported into the native [Xcode AppIcon set](macos/Runner/Assets.xcassets/AppIcon.appiconset/) at 16, 32, 64, 128, 256, 512, and 1024 pixels. Its segmented quota ring retains the original B design and communicates independent account quotas more directly than B3's continuous gradient ring. [View the adopted design and B3 alternative](assets/icon_candidates/orbit.html); B1 is selected on load, with matching SVG/PNG downloads. The rejected B2 design has been removed; switching previews does not change the native app icon. View the [comparison](assets/icon_candidates/orbit-comparison.png), [light](assets/icon_candidates/orbit-preview-light.png), or [dark](assets/icon_candidates/orbit-preview-dark.png) sheet.

```sh
flutter analyze
flutter test test/core_test.dart test/controller_test.dart
flutter run -d macos
```

The [core regression suite](test/core_test.dart) covers account/scope isolation, shared pools, out-of-order observations, units and reset boundaries, countdown ratios, reset-seat counts and expiry selection, subprocess cancellation/output limits, error privacy, persistent settings (including the 1- and 10-minute refresh boundaries and 10/50 pt pin bar lengths), migrations, and corrupt-file protection, including invalid refresh intervals and pin bar lengths. [Controller regressions](test/controller_test.dart) ensure hidden expired, missing, errored, and stale meters still appear in the usage panel and flag unpinned accounts in focus mode.

Issues and pull requests are welcome for reproducible bugs, display improvements, and real agent integrations. For bug reports, include macOS, Flutter, and agent versions plus reproduction steps—but **not credentials, private emails, or unredacted usage payloads**. For an adapter proposal, include its token-free inventory/quota contract and the limitations listed in the roadmap.

### Signed DMG releases

Release signing requires the company's Developer ID Application certificate **and private key** in an unlocked Keychain, plus **Python 3.12+** for the publishing tools. Debug builds remain ad-hoc signed, with library validation disabled only in Debug/Profile so Sparkle's bundled binaries can load. The [release script](scripts/release_macos.py) signs Sparkle's Autoupdate, Updater app, optional XPC services, and framework inside-out while preserving their entitlements, then the Flutter frameworks and containing app. It verifies Developer ID identity, secure timestamps, Hardened Runtime, universal `arm64` / `x86_64` binaries, and rejects debugging entitlements.

To verify signing and packaging locally without notarization:

```sh
python3 scripts/release_macos.py --prepare-only
```

This produces an explicitly named `*-unnotarized.dmg`. **Do not publish it as a formal release.**

For a notarized release, reuse the existing `apptogo-notarytool-profile` authorized for Team `V6C4PTHC4J`:

```sh
python3 scripts/release_macos.py --notary-profile apptogo-notarytool-profile
```

On a machine without that profile, create a new one in your own Terminal with `xcrun notarytool store-credentials PROFILE_NAME --team-id V6C4PTHC4J`, then pass its name using `--notary-profile`. The command prompts for the Apple ID and app-specific password; do not put passwords or private API keys in the repository or chat.

An existing App Store Connect API key can also be stored using `notarytool store-credentials`; pass only the resulting profile name to the release script. Use `--keychain /path/to/keychain` when the profile is not in the default Keychain.

The formal path submits the signed app ZIP, requires Apple's `Accepted` status, and staples the app before building a drag-to-Applications DMG. It then signs, notarizes, and staples the DMG, validates both tickets, and assesses Gatekeeper policy. Failed submissions preserve Apple's response and diagnostic log rather than producing a release-ready result.

Outputs are placed in a unique directory under `build/releases/`: the app, DMG, notarization responses, `appcast.xml`, and `SHA256SUMS`. Formal releases generate an Ed25519-signed Sparkle enclosure only after the final DMG is notarized and stapled; checksums cover both DMG and XML. `--prepare-only` never produces a public appcast. Keep Keychain credentials and local diagnostic files private. Intel binaries are included, but runtime smoke verification to date has been on Apple Silicon.

### Publishing the update feed

Apple Developer ID signing and Sparkle Ed25519 signing are separate. The dedicated Sparkle private key lives in the local Keychain under account **`any-usage-pin`**; only its public key is committed as `SUPublicEDKey`. Back up/transfer this key securely outside the repository using Sparkle's `generate_keys --account any-usage-pin -x /private/path/key` and `-f /private/path/key` commands. On another release machine, import the same key rather than generating a replacement; a different key will not match installed apps. The [pinned tools helper](scripts/sparkle_tools.py) verifies the Sparkle 2.10.0 distribution checksum before installation into `build/sparkle/2.10.0`.

For each stable release:

1. Increase both the displayed version and build number in `pubspec.yaml`. Sparkle compares `CFBundleVersion` (the number after `+`); it must increase for every update.
2. Run the formal notarized release command above.
3. Create a **draft** GitHub Release with tag `v` followed by the displayed version, and upload the final `AnyUsagePin-VERSION-macos-universal.dmg`, `appcast.xml`, and `SHA256SUMS` from the same output directory. Do not modify or repackage the DMG afterward.
4. Publish only after all three assets have uploaded.

The [publishing workflow](.github/workflows/publish-appcast.yml) runs on stable Release publication or manual dispatch. It selects the current latest stable release, validates metadata, artifact sizes, SHA256 checksums, and the DMG's Ed25519 signature against the app's public key, then deploys the exact XML to GitHub Pages. Missing assets, prereleases, or invalid signatures fail publication instead of exposing a dangling feed. Deployments are serialized; the workflow uses only `GITHUB_TOKEN`, never the update private key.

GitHub Pages must use **GitHub Actions** as its build source. The `github-pages` environment must allow both the `main` branch and `v*` **tag** deployments: a Release-triggered workflow runs on its tag even though it checks out publishing code from `main`. The workflow must be present on `main` before publishing the first Sparkle-enabled release. There is no XML commit or private-key CI secret to maintain. To verify a published release locally with OpenSSL 3:

```sh
GH_TOKEN="$(gh auth token)" python3 scripts/publish_appcast.py \
  --repository TerryHuangHD/any-usage-pin --output build/pages
```

The app/DMG notarization and update flow have been exercised locally: an isolated build-2 app discovered, downloaded, installed, and relaunched as the genuine signed build 3. The published 1.0.2 assets passed live GitHub download, checksum, and Ed25519 verification; the [Release-triggered Actions deployment](https://github.com/TerryHuangHD/any-usage-pin/actions/runs/37147648535) published a byte-identical public feed. The unmodified notarized 1.0.2 app queried that HTTPS feed and displayed no installable update.


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
