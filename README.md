# KaChat Wallet

A Kaspa wallet for iPhone, from the makers of KaChat.

- **Portfolio** - your balance, its value, price and network charts, and every transaction
- **Cold Storage** - watch and spend funds held on an air-gapped KasSigner device (signing happens on the device, by QR)
- **.kachat** - the .kachat names marketplace: find, claim, buy and sell names
- **Addresses** - saved Kaspa addresses with names
- **Wallet** - receive, your addresses, your domains, settings

KaChat Wallet started from KaChat's own wallet code
([KaChat-iPhone](https://github.com/KaspaSilver/KaChat-iPhone)) so KaChat can focus on chats.

## For the server

What KaChat Wallet needs from the KaChat server is handed off in the server's own repo,
[KaChat-Indexer](https://github.com/KaspaSilver/KaChat-Indexer), under `docs/` (e.g.
`docs/KACHAT_WALLET_PUSH.md`). The push contract the app follows is
[PUSH_SERVICE.md](PUSH_SERVICE.md).

MIT licensed - see [LICENSE](LICENSE).
