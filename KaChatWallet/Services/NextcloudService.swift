import Foundation
import UIKit

/// A connected Nextcloud account (server + login + app password), persisted as one Keychain blob.
struct NextcloudAccount: Codable, Equatable {
    var serverURLString: String
    var username: String
    var appPassword: String

    var serverURL: URL? { URL(string: serverURLString) }
    var displayName: String {
        let host = URL(string: serverURLString)?.host ?? serverURLString
        return "\(username)@\(host)"
    }
}

/// One entry from a WebDAV folder listing.
struct NextcloudFile: Identifiable, Equatable {
    /// Path relative to the user's files root, e.g. "Photos/cat.jpg".
    let path: String
    let name: String
    let isDirectory: Bool
    let contentType: String?
    let size: Int64?
    let modified: Date?

    var id: String { path }

}

extension Array where Element == NextcloudFile {
    /// The one ordering every Nextcloud listing surface uses: phone-gallery order.
    ///
    /// Folders stay grouped ahead of files (so a folder never lands in the middle of the
    /// thumbnail grid), and within each group entries run newest-first by `getlastmodified`.
    /// Entries whose date the server omitted or that failed to parse sort last rather than
    /// interleaving randomly, and name is the tiebreak so equal timestamps stay deterministic.
    ///
    /// Applied once in `NextcloudService.listFolder`; views only filter, never re-sort.
    func sortedNewestFirst() -> [NextcloudFile] {
        sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            switch (lhs.modified, rhs.modified) {
            case let (left?, right?):
                if left != right { return left > right }
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            case (nil, nil):
                break
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

enum NextcloudError: LocalizedError {
    case invalidServerURL
    case httpNotSupported
    case badCredentials
    case httpError(Int)
    case malformedResponse
    case backupNotFound
    case noActiveWallet
    /// The app is running on testnet, where Nextcloud is off (see `isOffForTestnet`).
    case offOnTestnet

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "That doesn't look like a valid server URL."
        case .httpNotSupported:
            return "Use https. Unencrypted connections are not supported."
        case .badCredentials:
            return "Nextcloud rejected the username or app password."
        case .noActiveWallet:
            return "Sign in to an account before connecting Nextcloud."
        case .offOnTestnet:
            return String(localized: "Nextcloud is off while Testnet is on.")
        case .httpError(let code):
            return "Nextcloud returned HTTP \(code)."
        case .malformedResponse:
            return "Unexpected response from the Nextcloud server."
        case .backupNotFound:
            return "No Address Book backup was found in the KaChat folder."
        }
    }
}

/// The user's own Nextcloud server, for one thing: backing up the Address Book to the KaChat
/// folder. Connect with an app password; the backup is the Address Book export file
/// (`AddressBookManager.ExportFile`, plain JSON with photos) at `KaChat/<backupFileName>`, so any
/// KaChat app can import it. Automatic Backup (default off) uploads it a few seconds after the
/// Address Book changes and when the app goes to the background; Restore merges it back in, and a
/// fresh connection restores once by itself. Import / Export in the Address Book also reach the
/// KaChat folder (and Portfolio's CSV export).
///
/// Everything here is scoped to the ACTIVE WALLET ACCOUNT: credentials live in a per-wallet
/// Keychain entry (`KeychainService.saveNextcloudCredentials(_:walletAddress:)`), the toggle and
/// last-backup stamp in per-wallet UserDefaults keys, and `setCurrentWallet` (called by
/// WalletManager) swaps the whole state on account switch/logout so one account's login never
/// leaks into another.
@MainActor
final class NextcloudService: ObservableObject {
    static let shared = NextcloudService()

    @Published private(set) var account: NextcloudAccount?

    /// Settings > Storage > Nextcloud > "Automatic Backup", per wallet account. Default off: a
    /// connection is not a request to start uploading.
    @Published private(set) var autoBackupEnabled = false

    /// When the active wallet's Address Book last uploaded (nil = never).
    @Published private(set) var lastBackupAt: Date?

    /// One-line result of the silent restore on connect. MainTabView renders it as a toast; nil
    /// hides it.
    @Published var syncStatusToast: String?

    /// True when the app is running on testnet. Nextcloud is a mainnet-only feature: the backup
    /// file is one per account across both networks, so on testnet the service holds no account
    /// at all, and the mainnet connection comes back on the next mainnet launch. Fixed per launch,
    /// like the network itself.
    @Published private(set) var isOffForTestnet = false

    /// The active wallet's address - every credential/settings read and write is scoped to it.
    private(set) var currentWalletAddress: String?
    /// Same 8-byte SHA256 hex as the Keychain entry, for the UserDefaults keys.
    private var currentWalletHashSuffix: String?

    /// The pending upload after an Address Book change, and any upload in flight - cancelled on
    /// an account switch so one account's book never uploads while another is active.
    private var backupTask: Task<Void, Never>?
    /// The Address Book changed since the last successful upload. Persisted, so a kill before the
    /// upload still backs up on the next background or launch.
    private var pendingBackup = false

    private nonisolated static let autoBackupKey = "kachat_nextcloud_auto_backup"
    private nonisolated static let lastBackupKey = "kachat_nextcloud_last_address_book_backup"
    private nonisolated static let pendingBackupKey = "kachat_nextcloud_pending_address_book_backup"
    /// Every key this service has ever stored per wallet - KaChat's chat-sync keys included, so a
    /// disconnect or account removal clears them too.
    private nonisolated static let storedKeys = [
        autoBackupKey, lastBackupKey, pendingBackupKey,
        "kachat_nextcloud_media_send", "kachat_nextcloud_last_auto_backup", "kachat_nextcloud_pending_sync",
        "kachat_nextcloud_auto_restore_done", "kachat_nextcloud_auto_sync_chosen", "kachat_nextcloud_last_etag",
        "kachat_nextcloud_talk_calls"
    ]
    /// Quiet time after an Address Book change before the upload, so a burst of edits is one.
    private nonisolated static let backupDebounce: TimeInterval = 5

    static let backupFolderName = "KaChat"
    /// Its own file: KaChat's chat backup (`kachat-backup.json`) may share the folder, and the
    /// wallet never touches it.
    static let backupFileName = "KaChat Wallet Address Book.json"

    private init() {
        // No credential load here: state stays empty until WalletManager reports the active
        // wallet via setCurrentWallet (every login/switch path calls it). Backgrounding uploads a
        // change still owed, inside a background task so iOS gives the upload time to finish.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in NextcloudService.shared.backUpPendingInBackground() }
        }
    }

    // MARK: - Wallet scoping

    /// Points the service at `walletAddress`'s stored Nextcloud state, or clears everything for
    /// nil. Called by WalletManager on every wallet load, account switch, logout and delete.
    func setCurrentWallet(_ requestedAddress: String?) {
        isOffForTestnet = AppSettings.load().networkType == .testnet
        let walletAddress = isOffForTestnet ? nil : requestedAddress
        guard walletAddress != currentWalletAddress else { return }

        backupTask?.cancel()
        backupTask = nil
        currentWalletAddress = walletAddress
        currentWalletHashSuffix = walletAddress.map { KeychainService.walletHashSuffix($0) }

        guard let walletAddress else {
            account = nil
            autoBackupEnabled = false
            pendingBackup = false
            lastBackupAt = nil
            return
        }

        migrateLegacyGlobalStateIfNeeded(for: walletAddress)
        if let data = try? KeychainService.shared.loadNextcloudCredentials(walletAddress: walletAddress) {
            account = try? JSONDecoder().decode(NextcloudAccount.self, from: data)
        } else {
            account = nil
        }
        let defaults = UserDefaults.standard
        autoBackupEnabled = scopedKey(Self.autoBackupKey).map { defaults.bool(forKey: $0) } ?? false
        pendingBackup = scopedKey(Self.pendingBackupKey).map { defaults.bool(forKey: $0) } ?? false
        let stamp = scopedKey(Self.lastBackupKey).map { defaults.double(forKey: $0) } ?? 0
        lastBackupAt = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        if pendingBackup { scheduleBackup(after: Self.backupDebounce) }
    }

    /// Settings' Automatic Backup toggle.
    func setAutoBackupEnabled(_ enabled: Bool) {
        if let key = scopedKey(Self.autoBackupKey) {
            UserDefaults.standard.set(enabled, forKey: key)
        }
        autoBackupEnabled = enabled
        if enabled {
            setPendingBackup(true)
            scheduleBackup(after: 0)
        } else {
            backupTask?.cancel()
            backupTask = nil
        }
    }

    /// Revokes the app password the user made for KaChat Wallet on their Nextcloud, so
    /// disconnecting or deleting the wallet leaves nothing that can still log in. Best effort:
    /// the local copy is deleted whatever the server says.
    func revokeAppPassword() async {
        guard let account, let server = account.serverURL else { return }
        var request = URLRequest(url: server.appendingPathComponent("ocs/v2.php/core/apppassword"))
        request.httpMethod = "DELETE"
        request.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        applyAuth(&request, account: account)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            AppLog.log("%@", "[Nextcloud] App password revoke answered HTTP \(status)")
        } catch {
            AppLog.log("%@", "[Nextcloud] App password revoke failed: \(error.localizedDescription)")
        }
    }

    /// Deletes the Address Book backup from the user's Nextcloud. Only ever on the user's say-so
    /// (the Delete Account option that names it).
    func deleteRemoteBackup() async throws {
        guard let request = authenticatedFileRequest(for: backupFilePath) else { throw NextcloudError.badCredentials }
        var delete = request
        delete.httpMethod = "DELETE"
        let (_, response) = try await URLSession.shared.data(for: delete)
        guard let http = response as? HTTPURLResponse else { throw NextcloudError.malformedResponse }
        if http.statusCode == 401 { throw NextcloudError.badCredentials }
        // 404: nothing there, which is the state asked for.
        guard (200..<300).contains(http.statusCode) || http.statusCode == 404 else {
            throw NextcloudError.httpError(http.statusCode)
        }
        AppLog.log("%@", "[Nextcloud] Address Book backup deleted")
    }

    /// Deletes a wallet's stored Nextcloud login and settings outright - used when that account
    /// is removed from this device entirely. Storage only; the in-memory state is cleared by the
    /// setCurrentWallet(nil) that always follows.
    func purgeStoredState(forWalletAddress walletAddress: String) {
        try? KeychainService.shared.deleteNextcloudCredentials(walletAddress: walletAddress)
        let suffix = KeychainService.walletHashSuffix(walletAddress)
        for base in Self.storedKeys {
            UserDefaults.standard.removeObject(forKey: "\(base)_\(suffix)")
        }
    }

    /// The active wallet's UserDefaults key for `base`, or nil when signed out (in which case
    /// nothing is read or written).
    private func scopedKey(_ base: String) -> String? {
        guard let suffix = currentWalletHashSuffix else { return nil }
        return "\(base)_\(suffix)"
    }

    /// One-time migration off the pre-per-wallet storage: the single global Keychain blob moves
    /// to the active wallet's scoped entry, then the global entry is deleted so no other account
    /// ever sees it again.
    private func migrateLegacyGlobalStateIfNeeded(for walletAddress: String) {
        guard let legacyBlob = try? KeychainService.shared.loadLegacyNextcloudCredentials() else { return }
        let hasScoped = (try? KeychainService.shared.loadNextcloudCredentials(walletAddress: walletAddress)) != nil
        if !hasScoped {
            try? KeychainService.shared.saveNextcloudCredentials(legacyBlob, walletAddress: walletAddress)
        }
        try? KeychainService.shared.deleteLegacyNextcloudCredentials()
        AppLog.log("%@", "[Nextcloud] Migrated the global Nextcloud login to the active wallet's per-account storage")
    }

    // MARK: - Automatic backup

    /// The Address Book changed (AddressBookManager calls this on every save, removal and import):
    /// with Automatic Backup on, it uploads a few seconds after the changes settle.
    func noteAddressBookChanged() {
        guard autoBackupEnabled, isConnected else { return }
        setPendingBackup(true)
        scheduleBackup(after: Self.backupDebounce)
    }

    private func setPendingBackup(_ pending: Bool) {
        pendingBackup = pending
        if let key = scopedKey(Self.pendingBackupKey) {
            UserDefaults.standard.set(pending, forKey: key)
        }
    }

    private func scheduleBackup(after delay: TimeInterval) {
        guard autoBackupEnabled, isConnected, let walletAtStart = currentWalletAddress else { return }
        backupTask?.cancel()
        backupTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled, let self, self.currentWalletAddress == walletAtStart else { return }
            do {
                try await self.runBackup()
            } catch {
                // Kept pending: the next change, background or launch retries.
                AppLog.log("%@", "[Nextcloud] Automatic Address Book backup failed: \(error.localizedDescription)")
            }
        }
    }

    /// Going to the background with a change still owed: upload it inside a background task.
    private func backUpPendingInBackground() {
        guard autoBackupEnabled, isConnected, pendingBackup else { return }
        var taskId: UIBackgroundTaskIdentifier = .invalid
        taskId = UIApplication.shared.beginBackgroundTask(withName: "kachat.addressbook.backup") {
            UIApplication.shared.endBackgroundTask(taskId)
            taskId = .invalid
        }
        Task { @MainActor in
            defer {
                if taskId != .invalid { UIApplication.shared.endBackgroundTask(taskId) }
            }
            try? await self.runBackup()
        }
    }

    // MARK: - Backup and restore

    /// Uploads this wallet's Address Book to `KaChat/<backupFileName>`, replacing the previous
    /// backup. The manual Back Up Now and the automatic backup both come here.
    func runBackup() async throws {
        guard let walletAtStart = currentWalletAddress else { throw NextcloudError.noActiveWallet }
        let data = try AddressBookManager.shared.exportData()
        _ = try await uploadToKaChatFolder(
            data: data, filename: Self.backupFileName, contentType: "application/json", keepSpaces: true
        )
        guard currentWalletAddress == walletAtStart else { return }
        setPendingBackup(false)
        lastBackupAt = Date()
        if let key = scopedKey(Self.lastBackupKey) {
            UserDefaults.standard.set(lastBackupAt?.timeIntervalSince1970 ?? 0, forKey: key)
        }
        AppLog.log("%@", "[Nextcloud] Address Book backed up")
    }

    /// Merges the backup into this wallet's Address Book (`AddressBookManager.importExport`: an
    /// address not saved here is added, one saved here takes the backup's version only when that
    /// is newer). Returns (added, updated). Throws `backupNotFound` when there is none yet.
    @discardableResult
    func restoreBackup() async throws -> (added: Int, updated: Int) {
        guard let walletAtStart = currentWalletAddress else { throw NextcloudError.noActiveWallet }
        let data: Data
        do {
            data = try await downloadFile(backupFilePath, maxBytes: 50_000_000)
        } catch NextcloudError.httpError(404) {
            throw NextcloudError.backupNotFound
        }
        guard currentWalletAddress == walletAtStart else { throw CancellationError() }
        let result = try AddressBookManager.shared.importExport(data)
        return (result.added, result.updated)
    }

    /// The backup file's server-side metadata (nil = no backup yet, or it couldn't be read).
    func fetchBackupInfo() async -> NextcloudFile? {
        guard let listing = try? await listFolder(Self.backupFolderName) else { return nil }
        return listing.first { $0.name == Self.backupFileName && !$0.isDirectory }
    }

    private var backupFilePath: String { "\(Self.backupFolderName)/\(Self.backupFileName)" }

    // MARK: - Connection

    var isConnected: Bool { account != nil }

    /// Normalizes user input ("restohome.duckdns.org", trailing slashes, an accidental
    /// "/index.php" suffix) into a clean base URL, defaulting to https.
    nonisolated static func normalizedServerURL(from input: String) -> URL? {
        var raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.lowercased().hasPrefix("http://") && !raw.lowercased().hasPrefix("https://") {
            raw = "https://" + raw
        }
        while raw.hasSuffix("/") { raw.removeLast() }
        if raw.lowercased().hasSuffix("/index.php") { raw.removeLast("/index.php".count) }
        guard let url = URL(string: raw), url.host != nil else { return nil }
        return url
    }

    /// Verifies the credentials against the OCS user endpoint (the cheapest authenticated call),
    /// then persists them and restores the Address Book backup if the KaChat folder has one.
    /// Throws `badCredentials` on a 401 so the connect screen can say exactly what's wrong.
    func connect(serverInput: String, username: String, appPassword: String) async throws {
        guard !isOffForTestnet else { throw NextcloudError.offOnTestnet }
        guard let walletAddress = currentWalletAddress else {
            throw NextcloudError.noActiveWallet
        }
        guard let server = Self.normalizedServerURL(from: serverInput) else {
            throw NextcloudError.invalidServerURL
        }
        // https-only transport. The connect screen rejects http:// inline before calling here;
        // this guard is the backstop for any other path into connect().
        guard server.scheme?.lowercased() == "https" else {
            throw NextcloudError.httpNotSupported
        }
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = appPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !password.isEmpty else { throw NextcloudError.badCredentials }

        let candidate = NextcloudAccount(serverURLString: server.absoluteString, username: user, appPassword: password)
        guard let endpoint = URL(string: server.absoluteString + "/ocs/v2.php/cloud/user?format=json") else {
            throw NextcloudError.invalidServerURL
        }
        var request = URLRequest(url: endpoint)
        applyAuth(&request, account: candidate)
        request.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NextcloudError.malformedResponse }
        if http.statusCode == 401 { throw NextcloudError.badCredentials }
        guard (200..<300).contains(http.statusCode) else { throw NextcloudError.httpError(http.statusCode) }
        guard let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ocs = decoded["ocs"] as? [String: Any],
              ocs["data"] is [String: Any] else {
            throw NextcloudError.malformedResponse
        }

        let encoded = try JSONEncoder().encode(candidate)
        try KeychainService.shared.saveNextcloudCredentials(encoded, walletAddress: walletAddress)
        account = candidate

        // A backup this account made on another device comes back by itself, once.
        Task { [weak self] in
            guard let self, let result = try? await self.restoreBackup(), result.added + result.updated > 0 else { return }
            self.syncStatusToast = String(format: AppLocalization.string("Restored %lld addresses from Nextcloud."), result.added + result.updated)
        }
    }

    func disconnect() {
        // Revoke first, while the credentials still exist to authenticate the request.
        if account != nil {
            Task { await self.revokeAppPassword() }
        }
        backupTask?.cancel()
        backupTask = nil
        if let walletAddress = currentWalletAddress {
            try? KeychainService.shared.deleteNextcloudCredentials(walletAddress: walletAddress)
            // This wallet's Nextcloud settings go with its credentials: connecting a different
            // server later starts fresh.
            purgeStoredState(forWalletAddress: walletAddress)
        }
        // Belt and braces: if a legacy global blob somehow still exists, remove it too so
        // disconnect can never appear to "come back" via migration.
        try? KeychainService.shared.deleteLegacyNextcloudCredentials()
        autoBackupEnabled = false
        pendingBackup = false
        lastBackupAt = nil
        account = nil
    }

    // MARK: - Files in the KaChat folder (Address Book backup and export, Portfolio CSV)

    /// Uploads `data` as `filename` into the KaChat folder, creating it if it isn't there yet,
    /// and returns the stored path. A file of the same name is replaced.
    /// `keepSpaces` keeps a name the user gave (a portfolio's, "KaChat Address Book") readable in
    /// Nextcloud instead of turning its spaces into underscores.
    func uploadToKaChatFolder(data: Data, filename: String, contentType: String, keepSpaces: Bool = false) async throws -> String {
        guard let account, let server = account.serverURL else { throw NextcloudError.badCredentials }
        let folder = Self.backupFolderName
        var folderURL = server.appendingPathComponent("remote.php/dav/files/\(account.username)")
        // Level by level: MKCOL is not recursive, and 405 means the level already exists.
        for part in folder.split(separator: "/") {
            folderURL.appendPathComponent(String(part))
            var mkcol = URLRequest(url: folderURL)
            mkcol.httpMethod = "MKCOL"
            applyAuth(&mkcol, account: account)
            let (_, mkcolResponse) = try await URLSession.shared.data(for: mkcol)
            if let http = mkcolResponse as? HTTPURLResponse {
                if http.statusCode == 401 { throw NextcloudError.badCredentials }
                guard (200..<300).contains(http.statusCode) || http.statusCode == 405 else {
                    throw NextcloudError.httpError(http.statusCode)
                }
            }
        }

        let storedName = Self.sanitizedFilename(filename, keepSpaces: keepSpaces)
        var put = URLRequest(url: folderURL.appendingPathComponent(storedName))
        put.httpMethod = "PUT"
        put.setValue(contentType, forHTTPHeaderField: "Content-Type")
        applyAuth(&put, account: account)
        put.httpBody = data
        let (_, putResponse) = try await URLSession.shared.data(for: put)
        guard let http = putResponse as? HTTPURLResponse else { throw NextcloudError.malformedResponse }
        if http.statusCode == 401 { throw NextcloudError.badCredentials }
        guard (200..<300).contains(http.statusCode) else { throw NextcloudError.httpError(http.statusCode) }
        return "\(folder)/\(storedName)"
    }

    /// A file's bytes, for importing it. Every failure throws so the caller can say what went wrong.
    func downloadFile(_ path: String, maxBytes: Int = 10_000_000) async throws -> Data {
        guard let request = authenticatedFileRequest(for: path) else { throw NextcloudError.badCredentials }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NextcloudError.malformedResponse }
        if http.statusCode == 401 { throw NextcloudError.badCredentials }
        guard (200..<300).contains(http.statusCode) else { throw NextcloudError.httpError(http.statusCode) }
        guard data.count <= maxBytes else { throw NextcloudError.malformedResponse }
        return data
    }

    /// Authenticated GET request for a file's raw bytes over WebDAV.
    private func authenticatedFileRequest(for path: String) -> URLRequest? {
        guard let account, let server = account.serverURL else { return nil }
        var url = server
        for part in "remote.php/dav/files/\(account.username)/\(path)".split(separator: "/") {
            url.appendPathComponent(String(part))
        }
        var request = URLRequest(url: url)
        applyAuth(&request, account: account)
        return request
    }

    /// Keeps stored filenames WebDAV/URL-safe: alphanumerics, dot, dash and underscore survive;
    /// everything else becomes "_". The extension must survive intact.
    private nonisolated static func sanitizedFilename(_ name: String, keepSpaces: Bool = false) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: keepSpaces ? "._- " : "._-"))
        let cleaned = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return cleaned.isEmpty ? "file" : cleaned
    }

    private nonisolated func applyAuth(_ request: inout URLRequest, account: NextcloudAccount) {
        let token = Data("\(account.username):\(account.appPassword)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
    }

    // MARK: - WebDAV browsing (the import file picker's data source)

    /// Lists one folder (non-recursive) of the connected account's files via a Depth-1 PROPFIND.
    func listFolder(_ relativePath: String = "") async throws -> [NextcloudFile] {
        guard let account, let server = account.serverURL else { throw NextcloudError.badCredentials }
        let davBasePath = "/remote.php/dav/files/\(account.username)"
        // Normalized form of the listed folder, for the parser's self-entry exclusion below.
        let listedPath = relativePath.split(separator: "/").joined(separator: "/")
        var url = server
        for part in "remote.php/dav/files/\(account.username)/\(relativePath)".split(separator: "/") {
            url.appendPathComponent(String(part))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        applyAuth(&request, account: account)
        request.httpBody = Data("""
        <?xml version="1.0"?>
        <d:propfind xmlns:d="DAV:">
          <d:prop><d:displayname/><d:resourcetype/><d:getcontenttype/><d:getcontentlength/><d:getlastmodified/></d:prop>
        </d:propfind>
        """.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NextcloudError.malformedResponse }
        if http.statusCode == 401 { throw NextcloudError.badCredentials }
        guard http.statusCode == 207 else { throw NextcloudError.httpError(http.statusCode) }

        return DavMultistatusParser(davBasePath: davBasePath, listedPath: listedPath)
            .parse(data)
            .sortedNewestFirst()
    }
}

/// Minimal WebDAV `multistatus` parser for folder listings — pulls each response's href,
/// display name, collection flag, content type and length. Namespace-agnostic via
/// `shouldProcessNamespaces` (servers vary between `d:` and `D:` prefixes).
private final class DavMultistatusParser: NSObject, XMLParserDelegate {
    private let davBasePath: String
    /// The folder being listed. A Depth-1 PROPFIND's multistatus includes the listed folder
    /// ITSELF as its first response — without excluding it, every folder appears to contain
    /// itself (an infinite "Photos inside Photos" loop when browsing).
    private let listedPath: String
    private var results: [NextcloudFile] = []
    private var inResponse = false
    private var currentHref = ""
    private var currentName: String?
    private var currentType: String?
    private var currentLength: Int64?
    private var currentModified: Date?
    private var isCollection = false
    private var text = ""

    /// WebDAV's getlastmodified is RFC 1123 ("Mon, 11 Aug 2026 20:14:07 GMT").
    private static let lastModifiedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        // The string carries its own zone ("GMT"), but pin the fallback so a server that omits it
        // is read as UTC instead of drifting with the device's local zone.
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    init(davBasePath: String, listedPath: String) {
        self.davBasePath = davBasePath
        self.listedPath = listedPath
    }

    func parse(_ data: Data) -> [NextcloudFile] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        parser.parse()
        return results
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch elementName {
        case "response":
            inResponse = true
            currentHref = ""
            currentName = nil
            currentType = nil
            currentLength = nil
            currentModified = nil
            isCollection = false
        case "collection":
            isCollection = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "href":
            if inResponse, currentHref.isEmpty { currentHref = trimmed }
        case "displayname":
            if inResponse, currentName == nil, !trimmed.isEmpty { currentName = trimmed }
        case "getcontenttype":
            if inResponse, !trimmed.isEmpty { currentType = trimmed }
        case "getcontentlength":
            if inResponse { currentLength = Int64(trimmed) }
        case "getlastmodified":
            if inResponse, !trimmed.isEmpty { currentModified = Self.lastModifiedFormatter.date(from: trimmed) }
        case "response":
            inResponse = false
            appendCurrent()
        default:
            break
        }
    }

    private func appendCurrent() {
        guard let decoded = currentHref.removingPercentEncoding,
              let range = decoded.range(of: davBasePath) else { return }
        var relative = String(decoded[range.upperBound...])
        while relative.hasPrefix("/") { relative.removeFirst() }
        while relative.hasSuffix("/") { relative.removeLast() }
        guard !relative.isEmpty, relative != listedPath else { return } // the listed folder itself
        let fallbackName = relative.split(separator: "/").last.map(String.init) ?? relative
        results.append(NextcloudFile(
            path: relative,
            name: currentName ?? fallbackName,
            isDirectory: isCollection,
            contentType: currentType,
            size: currentLength,
            modified: currentModified
        ))
    }
}
