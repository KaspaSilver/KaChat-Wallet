# CLAUDE.md

Guidance for Claude Code in this repository.

## What KaPay is

KaPay (named KaChat Wallet until 2026-10-27) is a standalone iOS Kaspa wallet, split out of KaChat so KaChat can stay focused on
1:1 and group chats. It keeps KaChat's wallet features: Portfolio, Cold Storage, the .kachat names
marketplace, Address Book and the account's Wallet tab (receive, send, addresses, domains, help,
about).

The source started as a copy of KaChat-iPhone (`KaspaSilver/KaChat-iPhone`) at commit `b603eb9f`
(2026-10-24). Everything that was not the wallet has been removed (2026-10-25 calls; 2026-10-27
1:1, group and public chats, KaPosts, Chess, Swap, bots, voice/Opus, the message store, chat push
and sync, the app-extension data sharing). There is no chat code left: don't bring any back.
The wallet's identity address keeps KaChat's name, "Chatting Address", in code and UI alike: the
wallet is part of the KaChat ecosystem (owner's call, 2026-10-27). Don't rename it.

## Dock

Five fixed tabs (`AppTab` in `KaChatWallet/Models/Models.swift`, rendered by
`KaChatWallet/App/MainTabView.swift`):

| Tab | View |
|---|---|
| Portfolio | `PortfolioView` (`Views/Portfolio/`) |
| Cold Storage | `ColdStorageListView` (`Views/ColdStorage/`) |
| Wallet | `ProfileView` (`Views/Contacts/ContactsView.swift`, `AppTab.profile`) - the home tab, where the app opens after logging in; receive, the Chatting Address, Manage Addresses, Your Domains, Address Book (`AddressBookView`, as a sheet), help, about; a floating up/down arrow (bottom right, as in KaChat) opens a half sheet: Send Kaspa, Receive Kaspa, Request Payment (`CreatePaymentRequestView`) |
| .kachat | `KachatMarketView` (`Views/Ecosystem/`); dock icon `KachatTabIcon.domainsImage` (name tag with an @) - the full .kachat names marketplace: search, buy, claim, sell, offers, activity |
| Settings | `SettingsView(isDockTab: true)` (`Views/Settings/SettingsView.swift`, `AppTab.settings`) - no Done button as a tab; Log Out is its last row |

Account setup: `ContentView` -> `OnboardingView` (create / import a seed) -> `MainTabView`. The
sign-in screen says "KaPay" with the wallet logo and no tagline. The rename kept every identifier
(bundle ID, keychain group, URL scheme, folder and target names `KaChatWallet`): only what people
read says KaPay. Texts about the KaChat ecosystem (KaChat profiles, .kachat names, the Nextcloud
`KaChat` folder) still say KaChat.

The Wallet tab keeps KaChat's profile (Receive, Chatting Address, Edit KaChat Profile, Your Domains,
share link); Help has only the .kachat names guide. The bell (`GlobalNotificationCenter`) lists
"Received" and .kachat notifications.

## Services

- `WalletService` (`Services/WalletService*.swift`): the node connection, the live UTXO
  subscription to the wallet's own addresses (main, spending, cold storage; re-subscribed when a
  cold account or a new primary appears), sending (`WalletService+Sending`) and Kaspa REST reads
  (`WalletService+Transactions`). Live batches go to `AddressActivityNotifier` and a balance
  refresh; without a subscription a 60s poll refreshes the balance and catches up receives.
- `WalletManager`: accounts, keys, spending addresses. `AddressBookManager`, `ColdStorageManager`,
  `PortfolioManager`/`PortfolioViewModel`, `KNSService` and `KachatNames*` as their names say.
- `NextcloudService`: backs up the Address Book and the Portfolio, nothing else, as two plain
  JSON files in the `KaChat` folder - never KaChat's `kachat-backup.json`:
  `KaPay Address Book.json` (the Address Book export file, `AddressBookManager.ExportFile`,
  with photos) and `KaPay Portfolio.json` (`PortfolioBackupFile`: portfolios,
  transactions, fees and deletion tombstones); a restore falls back to the pre-rename
  `KaChat Wallet …` names. Connect with an app password. Automatic Backup
  (off by default) uploads a few seconds after either changes and on background; a backup merges
  the server's Portfolio in first (`PortfolioSync.merge`, newest edit or deletion wins), so two
  devices don't overwrite each other. Restore and a fresh connection merge both back
  (`AddressBookManager.importExport`, `PortfolioViewModel.importFromArchive`). Address Book and
  Portfolio import/export can also use the KaChat folder.
- `KachatNamesRegistry` reads .kachat names through `AppSettings.indexerURL` (Settings >
  Connection > Domains, editable so anyone can run their own indexer; blank = the network's
  default) while it serves this registry and keeps up, else walks the chain itself; the Domains
  tab shows which.
- `AppSettings` (`Models/Models.swift`) holds only wallet settings; a blob from an older build
  (with KaChat's chat settings) still decodes, every field falling back to its default.

## Logo

`tools/make_logo.py` draws the logo and the app icons (teal wallet, Kaspa's backward K in the
middle). Variants: `logo` (white rounded square, the in-app `KaChatWalletLogo` image, 512 px) and
the 1024 px app icons `light` (white), `dark` (near-black) and `tinted` (grayscale on black):

```bash
python3 tools/make_logo.py KaChatWallet/Resources/Assets.xcassets/KaChatWalletLogo.imageset/KaChatWalletLogo.png 512 logo
python3 tools/make_logo.py KaChatWallet/Resources/Assets.xcassets/KaChatWalletLogoDark.imageset/KaChatWalletLogoDark.png 512 dark
for v in light dark tinted; do python3 tools/make_logo.py KaChatWallet/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-$v.png 1024 $v; done
```

## Identifiers

- Bundle ID `com.kachat.wallet`, keychain group `$(AppIdentifierPrefix)com.kachat.wallet`, URL
  scheme `kachatwallet`, background task `com.kachat.wallet.messageFetch` (the name is historical;
  it refreshes the balance). None of these are shared with KaChat, so the two apps never read each
  other's keychain or storage.
- Team `RP4Z22SFSD` (the KaChat developer's Apple team; the wallet ships under that account)
- Version: `KaChatWallet/Version.xcconfig` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`)

## Build

The project uses a file-system-synchronized folder: every file under `KaChatWallet/` is in the
app target automatically (no pbxproj edits for new files). Exceptions (Info.plist, entitlements,
Version.xcconfig) are listed in the project's exception set.

```bash
xcodebuild -project KaChatWallet.xcodeproj -scheme KaChatWallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
```

Claude writes the code and never tests it - no Simulator driving, screenshots or verification
builds; the owner does all testing. When the owner says "rebuild", build with the command above
and install + launch the app in the Simulator, then stop. Device and App Store builds are the
owner's.

## Push

The wallet registers with KaChat's push service for "Received KAS" (its own addresses as
`watch_only_addresses`) and .kachat name events (`primary_address`), with `apns_topic` =
`com.kachat.wallet` - no chats, rooms or KaPosts. "Received" is only for Kaspa from someone
else: a tx with any input from the wallet's own addresses never notifies, including one sent by
another app on the same seed (KaPosts, KaChat). `AddressActivityNotifier` matches inputs the
REST API hasn't resolved yet against the coins the live batches just spent, by outpoint. With remote push
registered the app announces a receive only while it is open (the push covers the rest, and the open
app hides it); the catch-up never re-announces history: only receives newer than each address's floor,
newest first, up to the balance increase. With Address Activity off it stays registered
through `primary_address` alone. Registration and updates are signed like KaChat's
(`PushNotificationManager.buildPushAuth`); the chat fields (`watched_addresses`,
`watched_group_ids`, aliases) are always empty. A `name_event` push has no thread id (the wallet
has no notification extension); a tap routes by its `type` and `name`. Settings > Notifications is one page:
Push Notifications, Address Activity, sound, vibration. It asks for notification permission once, when
its tabs first show. Entitlements carry `aps-environment` (development / production). The service
still has to send on the wallet's topic and skip chat pushes for it: see `PUSH_SERVICE.md`.

## Server hand-offs

This session never changes the server's code. When kachat-indexer
(`/Users/restosaved/KaChat Server/kachat-indexer`, `KaspaSilver/KaChat-Indexer`) needs a change,
write a hand-off doc in that repo's `docs/` (one per change, e.g. `docs/KACHAT_WALLET_PUSH.md`),
in its format: a dated title, "**For:** the indexer session. **From:** the KaPay (KaChat Wallet) iOS
session", then what the app sends and expects, the rule, where in the server it goes, the wallet
commits, and how to test. Commit and push only that doc there; the indexer session builds from it.

## Protocol and servers

Same as KaChat: the node pool for balances and transactions, the Kaspa REST API and CoinGecko for
Portfolio, the KaChat indexer for push and .kachat names. The protocol and server docs live in
KaChat-iPhone (`KACHAT_NAMES.md`, `PUSH_NOTIFICATIONS.md`).
