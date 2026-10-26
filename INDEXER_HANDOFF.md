# Indexer hand-off from KaChat Wallet

The KaChat Wallet (iPhone) session does not change kachat-indexer. Anything the indexer needs
because of a wallet change is written here, and the indexer session picks it up from this file.

**For the indexer session:** work through the **Open** items in order. When one is done, move it
to **Done** with your kachat-indexer commit, and keep the app-side contract as written. If a
contract can't be met as written, say so to the owner rather than changing the app's side.

**For the wallet session:** add an item for every app change that needs the indexer to store,
serve, send or check something new, or to change how it does. Say what the app sends and expects
(endpoint, request, response, rules) and which KaChat Wallet commit and spec file it comes from,
so the item stands on its own.

## Open

- **2026-10-26 - No "Received" push for a self-send.** KaChat Wallet 42470af,
  [PUSH_SERVICE.md §3](PUSH_SERVICE.md#3-no-received-push-for-a-self-send-required). An
  `address_activity` push must go out only for Kaspa from someone else. Today a transaction that
  spends from the device's own `watch_only_addresses` still pings when its change lands on one of
  them - e.g. a KaPosts post from the same seed. `emit_funds_received`
  (`indexer-actors/src/block_processor.rs`) finds a `sender` for the first input only, and only
  through `tx_id_to_acceptance_partition` (Kasia message txs), so a plain transfer, a KaPosts
  post or a coinbase input gives `sender = None` and the push is sent. Rule: drop a device when
  ANY input of the tx spends an output that paid one of that device's `watch_only_addresses`.
  The app already applies the same rule to its own local notifications (42470af). Suggested
  approach (outpoint -> address map for watched outputs) is in the spec.

- **2026-10-26 - Registration with only a primary address.** KaChat Wallet 2c59051,
  [PUSH_SERVICE.md §0](PUSH_SERVICE.md#0-accept-a-registration-with-only-watch-only-addresses-or-a-primary-address-required).
  With Settings > Notifications > Address Activity off, the wallet sends `watch_only_addresses:
  []` (and empty `watched_addresses` / `watched_group_ids`) but keeps `primary_address`, so the
  device still gets its .kachat `name_event` pushes. `register` and `update` in
  `indexer/src/push.rs` still refuse it ("must not all be empty"). Accept it when
  `primary_address` is set; nothing to watch at all is still refused.

## Done

- **2026-10-25 - Per-app APNs topic, watch-only registrations, wallet devices get only Received
  and .kachat pushes.** KaChat Wallet `apns_topic: "com.kachat.wallet"`,
  [PUSH_SERVICE.md](PUSH_SERVICE.md) §0 (watch-only part), §1 and §2. Done in kachat-indexer
  27f9c57 (`APNS_ALLOWED_TOPICS`, per-device topic on APNs sends, `deliver()` drops wallet-topic
  tokens for every kind except `address_activity` and `name_event`).
