import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct UpdateInfo: Sendable, Equatable {
    public var version: String      // "1.2.0"
    public var tag: String          // "v1.2.0"
    public var notes: String
    public var pageURL: URL
}

/// Update checks. New versions are published as GitHub Releases of this app's repository and the app
/// asks GitHub for the latest one. The Windows app can install the release itself; the macOS app is
/// built from source for now, so here an update is announced with a link.
public enum Updater {
    public static let repo = "panch076/margin"
    /// This build's version. Keep in step with the Windows project file when releasing.
    public static let currentVersion = "1.0.0"

    public static var latestURL: String { "https://api.github.com/repos/\(repo)/releases/latest" }
    public static var releasesPage: URL { URL(string: "https://github.com/\(repo)/releases")! }

    /// "v1.2.3", "1.2" and "1.2.3-beta" all parse to [major, minor, patch]; anything else is nil.
    public static func parseVersion(_ tag: String?) -> [Int]? {
        guard let tag, let m = Rx.first("^v?(\\d+)\\.(\\d+)(?:\\.(\\d+))?", in: tag.trimmingCharacters(in: .whitespacesAndNewlines)),
              let major = Int(m[1]), let minor = Int(m[2]) else { return nil }
        return [major, minor, Int(m[3]) ?? 0]
    }

    public static func isNewer(_ candidate: [Int], than current: [Int]) -> Bool {
        current.lexicographicallyPrecedes(candidate)
    }

    /// The latest release if it is newer than `current`, otherwise nil. Never throws for network problems.
    public static func check(current: String = currentVersion,
                             transport: @escaping BankStore.Transport = BankStore.defaultTransport) async -> UpdateInfo? {
        guard let url = URL(string: latestURL), let mine = parseVersion(current) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Margin-Updater/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, status) = try? await transport(request), (200..<300).contains(status),   // 404: nothing released yet
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if (o["draft"] as? Bool) == true || (o["prerelease"] as? Bool) == true { return nil }
        guard let tag = o["tag_name"] as? String, let theirs = parseVersion(tag), isNewer(theirs, than: mine) else { return nil }

        var page = releasesPage
        if let s = o["html_url"] as? String, s.hasPrefix("https://github.com/\(repo)/"), let u = URL(string: s) { page = u }
        let notes = ((o["body"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return UpdateInfo(version: theirs.map(String.init).joined(separator: "."), tag: tag, notes: notes, pageURL: page)
    }
}
