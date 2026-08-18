import Foundation

/// Compares the running app's version against the newest GitHub release.
/// Network access happens only when the user asks (App menu -> Check for Updates);
/// the request carries no identifiers beyond a standard HTTP request.
struct UpdateChecker {

    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/jberends/marginal/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/jberends/marginal/releases/latest")!

    struct Release: Decodable, Sendable {
        struct Asset: Decodable, Sendable {
            let name: String
            let browserDownloadUrl: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
            }
        }

        let tagName: String
        let htmlUrl: String
        var assets: [Asset] = []

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case assets
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tagName = try container.decode(String.self, forKey: .tagName)
            htmlUrl = try container.decode(String.self, forKey: .htmlUrl)
            assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
        }

        /// "v0.1.0" -> "0.1.0"
        var version: String {
            tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        }

        /// The downloadable app archive, if the release carries one.
        var appZipAsset: Asset? {
            assets.first { $0.name.hasSuffix(".zip") }
        }
    }

    enum Result {
        case upToDate(current: String)
        case updateAvailable(current: String, release: Release)
        case failed(String)
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// How this copy of Marginal was installed. The same build is shipped to both channels,
    /// so this has to be decided at runtime.
    enum Channel {
        /// Installed from the Mac App Store. The App Store owns updating.
        case appStore
        /// Downloaded from GitHub releases. Marginal updates itself.
        case direct
    }

    /// A Mac App Store install carries a receipt at `Contents/_MASReceipt/receipt`; a
    /// directly downloaded build does not. That file's presence is the only signal available
    /// at runtime, and it is the one Apple's own guidance points at.
    ///
    /// Deliberately conservative: anything we cannot positively identify as App Store is
    /// treated as `.direct`, because being wrong that way shows a redundant menu item, while
    /// being wrong the other way offers an update that cannot possibly install.
    static var channel: Channel {
        guard let receipt = Bundle.main.appStoreReceiptURL,
              FileManager.default.fileExists(atPath: receipt.path)
        else { return .direct }
        return .appStore
    }

    /// Whether Marginal is allowed to install its own updates.
    ///
    /// False on the App Store, for three separate reasons — any one of which is enough:
    ///
    /// 1. Replacing the bundle destroys `_MASReceipt/receipt`, so the app can no longer prove
    ///    it was purchased.
    /// 2. The sandbox blocks every step of the swap. It refuses to launch Terminal, and the
    ///    handoff script is quarantined on write, so Gatekeeper reports it as damaged.
    /// 3. Apple requires App Store apps to update through the App Store.
    ///
    /// There is also a product reason not to merely redirect to the App Store: review lag
    /// means the App Store build is routinely behind the newest GitHub release, so asking
    /// GitHub "is there something newer" gets an answer that does not apply to this install.
    static var canSelfUpdate: Bool {
        channel == .direct
    }

    /// Numeric, segment-wise semantic comparison: "0.10.0" is newer than "0.9.1",
    /// "1.0" and "1.0.0" are equal.
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func check(completion: @escaping @Sendable (Result) -> Void) {
        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let current = currentVersion
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failed(error.localizedDescription))
                return
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data,
                  let release = try? JSONDecoder().decode(Release.self, from: data) else {
                completion(.failed("Could not read the latest release from GitHub."))
                return
            }
            if isVersion(release.version, newerThan: current) {
                completion(.updateAvailable(current: current, release: release))
            } else {
                completion(.upToDate(current: current))
            }
        }.resume()
    }
}
