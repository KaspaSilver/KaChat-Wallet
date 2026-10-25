import Foundation

/// Your Domains' .kachat names and offers, kept on the device per wallet address and network so
/// the list shows at once instead of waiting on the registry every time. They rarely change, so
/// the screen shows this copy first and the registry read runs behind it, replacing the copy
/// only when it answers - a new name, a sale, a transfer or a lapse lands then; a failed read
/// leaves the copy as it was.
enum KachatOwnedNamesCache {
    struct Entry: Codable {
        var names: [KachatNames.NameInfo]
        var offers: [KachatNames.OfferInfo]
        var savedAt: Date
    }

    private static func key(_ address: String) -> String {
        let network = AppSettings.load().networkType == .testnet ? "testnet" : "mainnet"
        return "kachat_owned_names_\(network)_\(address.lowercased())"
    }

    static func load(_ address: String) -> Entry? {
        guard let data = UserDefaults.standard.data(forKey: key(address)) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    static func save(names: [KachatNames.NameInfo], offers: [KachatNames.OfferInfo], for address: String) {
        let entry = Entry(names: names, offers: offers, savedAt: Date())
        guard let data = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(data, forKey: key(address))
    }
}
