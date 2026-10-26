# CLAUDE.md

Guidance for Claude Code in this repository.

## What KaChat Wallet is

KaChat Wallet is a standalone iOS Kaspa wallet, split out of KaChat so KaChat can stay focused on
1:1 and group chats. It keeps KaChat's wallet features: Portfolio, Cold Storage, the .kachat names
marketplace, Address Book and the whole account Profile (receive, addresses, domains, settings, help, log out, about).

The source started as a copy of KaChat-iPhone (`KaspaSilver/KaChat-iPhone`) at commit `b603eb9f`
(2026-10-24). Most of `KaChatWallet/` is still that code, including features the wallet never
shows (1:1 and group chats, KaPosts, Public Chats, Chess, Swap, Nextcloud, bots). Calls are gone
entirely - call code, VoIP push and the WebRTC package were removed on 2026-10-25. They are
being removed step by step; until then, change only what the wallet uses.

## Dock

Five fixed tabs (`AppTab` in `KaChatWallet/Models/Models.swift`, rendered by
`KaChatWallet/App/MainTabView.swift`):

| Tab | View |
|---|---|
| Portfolio | `PortfolioView` (`Views/Portfolio/`) - the home tab |
| Cold Storage | `ColdStorageListView` (`Views/ColdStorage/`) |
| Wallet | `ProfileView` (`Views/Contacts/ContactsView.swift`) - KaChat's Profile, labelled "Wallet" in the dock with KaPosts' wallet icon (`AppTab.profile`); Settings opens from here |
| .kachat | `KachatMarketView` (`Views/Ecosystem/`); dock icon `KachatTabIcon.domainsImage` (name tag with an @) - the full .kachat names marketplace: search, buy, claim, sell, offers, activity; hidden in Simple Mode |
| Addresses | `AddressBookView` (`Views/Contacts/AddressBookView.swift`) - KaChat's Address Book, called "Addresses" |

Account setup is KaChat's: `ContentView` -> `OnboardingView` (create / import a seed) ->
`MainTabView`. The sign-in screen says "KaChat Wallet" with the wallet logo and no tagline; KaChat's
welcome guide is not shown.

Profile keeps KaChat's whole profile (Receive, Chatting Address, Edit KaChat Profile, Your
Domains, share link) minus the chat-only parts: Settings has no Chats or Chat History page, and
Help has only the .kachat names guide. The bell lists wallet and .kachat notifications only.

## Logo

`tools/make_logo.py` draws the logo and the app icons (teal wallet, Kaspa's backward K in the
middle). Variants: `logo` (white rounded square, the in-app `KaChatWalletLogo` image, 512 px) and
the 1024 px app icons `light` (white), `dark` (near-black) and `tinted` (grayscale on black):

```bash
python3 tools/make_logo.py KaChatWallet/Resources/Assets.xcassets/KaChatWalletLogo.imageset/KaChatWalletLogo.png 512 logo
for v in light dark tinted; do python3 tools/make_logo.py KaChatWallet/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-$v.png 1024 $v; done
```

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

## Chats are off

`ChatService.chatsEnabled` is `false`. ChatService stays only for the node connection and the
live subscription to the wallet's own addresses (main, spending, cold storage): incoming UTXO
batches go to `AddressActivityNotifier` ("Received KAS") and a balance refresh, nothing else.
Every chat path checks the flag and does nothing - handshakes, message sync and fallback
polling, payments-as-chat, contact sweeps, catch-ups, group live polling and catch-up, KaPosts
notifications, the unnamed-contact .kachat sweep, the local message load (and its "chat with
yourself"), extension contact/group syncs, incoming pushes (`handleRemoteNotification` leaves
them to iOS as plain banners), and background fetch (which refreshes the balance
and catches up receives instead). The icon never shows a badge. Notifications are only for the
wallet's own addresses, Cold Storage and .kachat names. The chat code itself still compiles;
change nothing in it unless removing it.

## Push

The wallet registers with KaChat's push service for "Received KAS" (its own addresses as
`watch_only_addresses`) and .kachat name events (`primary_address`), with `apns_topic` =
`com.kachat.wallet` - no chats, rooms or KaPosts. "Received" is only for Kaspa from someone
else: a tx with any input from the wallet's own addresses never notifies, including one sent by
another app on the same seed (KaPosts, KaChat). `AddressActivityNotifier` matches inputs the
REST API hasn't resolved yet against the coins the live batches just spent, by outpoint. With Address Activity off it stays registered
through `primary_address` alone. A `name_event` push has no thread id (the wallet has no
notification extension); a tap routes by its `type` and `name`. Settings > Notifications has only
the Wallet page (Address Activity, sound, vibration). It asks for notification permission once, when
its tabs first show. Entitlements carry `aps-environment` (development / production). The service
still has to send on the wallet's topic and skip chat pushes for it: see `PUSH_SERVICE.md`.

## Server hand-offs

This session never changes the server's code. When kachat-indexer
(`/Users/restosaved/KaChat Server/kachat-indexer`, `KaspaSilver/KaChat-Indexer`) needs a change,
write a hand-off doc in that repo's `docs/` (one per change, e.g. `docs/KACHAT_WALLET_PUSH.md`),
in its format: a dated title, "**For:** the indexer session. **From:** the KaChat Wallet iOS
session", then what the app sends and expects, the rule, where in the server it goes, the wallet
commits, and how to test. Commit and push only that doc there; the indexer session builds from it.

## Protocol and servers

Same as KaChat: the node pool for balances and transactions, the Kaspa REST API and CoinGecko for
Portfolio, the KaChat indexer where KaChat uses it. The protocol and server docs live in
KaChat-iPhone (`MESSAGING.md`, `KACHAT_NAMES.md`, `PUSH_NOTIFICATIONS.md`).
