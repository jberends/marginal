import Foundation

/// Compares the running app's version against the newest GitHub release.
/// Network access happens only when the user asks (App menu -> Check for Updates);
/// the request carries no identifiers beyond a standard HTTP request.
struct UpdateChecker {

    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/jberends/marginal/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/jberends/marginal/releases/latest")!

    struct Release: Decodable {
        let tagName: String
        let htmlUrl: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
        }

        /// "v0.1.0" -> "0.1.0"
        var version: String {
            tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        }
    }

    enum Result {
        case upToDate(current: String)
        case updateAvailable(current: String, latest: String)
        case failed(String)
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
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
                completion(.updateAvailable(current: current, latest: release.version))
            } else {
                completion(.upToDate(current: current))
            }
        }.resume()
    }
}
