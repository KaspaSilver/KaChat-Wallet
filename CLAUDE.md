# CLAUDE.md

Guidance for Claude Code in this repository.

## What KaChat Wallet is

KaChat Wallet is a standalone iOS Kaspa wallet, split out of KaChat so KaChat can stay focused on
1:1 and group chats. It keeps KaChat's wallet features: Portfolio, Cold Storage, Address Book and
the whole account Profile (receive, addresses, domains, settings, help, log out, about).

The source started as a copy of KaChat-iPhone (`KaspaSilver/KaChat-iPhone`) at commit `b603eb9f`
(2026-10-24). Most of `KaChatWallet/` is still that code, including features the wallet never
shows (1:1 and group chats, KaPosts, Public Chats, Chess, Swap, calls, Nextcloud, bots). They are
being removed step by step; until then, change only what the wallet uses.

## Dock

Four fixed tabs (`AppTab` in `KaChatWallet/Models/Models.swift`, rendered by
`KaChatWallet/App/MainTabView.swift`):

| Tab | View |
|---|---|
| Portfolio | `PortfolioView` (`Views/Portfolio/`) - the home tab |
| Cold Storage | `ColdStorageListView` (`Views/ColdStorage/`) |
| Address Book | `AddressBookView` (`Views/Contacts/AddressBookView.swift`) |
| Profile | `ProfileView` (`Views/Contacts/ContactsView.swift`); Settings opens from here |

Account setup is KaChat's, unchanged: `ContentView` -> `OnboardingView` (create / import a seed)
-> `MainTabView`.

## Identifiers

- Bundle ID `com.kachat.wallet`, App Group `group.com.kachat.wallet`, keychain group
  `$(AppIdentifierPrefix)com.kachat.wallet`, URL scheme `kachatwallet`, background task
  `com.kachat.wallet.messageFetch`. None of these are shared with KaChat, so the two apps never
  read each other's keychain or storage.
- Team `RP4Z22SFSD` (the KaChat developer's Apple team; the wallet ships under that account)
- Version: `KaChatWallet/Version.xcconfig` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`)

## Build

The project uses a file-system-synchronized folder: every file under `KaChatWallet/` is in the
app target automatically (no pbxproj edits for new files). Exceptions (Info.plist, entitlements,
Version.xcconfig) are listed in the project's exception set.

```bash
xcodebuild -project KaChatWallet.xcodeproj -scheme KaChatWallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
```

Claude may build for the iOS Simulator and run it there. Device and App Store builds are the
owner's.

## Protocol and servers

Same as KaChat: the node pool for balances and transactions, the Kaspa REST API and CoinGecko for
Portfolio, the KaChat indexer where KaChat uses it. The protocol and server docs live in
KaChat-iPhone (`MESSAGING.md`, `KACHAT_NAMES.md`, `PUSH_NOTIFICATIONS.md`).
