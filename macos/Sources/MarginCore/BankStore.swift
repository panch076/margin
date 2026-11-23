import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct Bank: Sendable {
    public var questions: [Question] = []
    public var byId: [String: Question] = [:]
    public var unusable = 0
    public var updated: Date?

    public init() {}
    public var isEmpty: Bool { questions.isEmpty }
    public func count(_ s: Subject) -> Int { questions.filter { $0.section == s }.count }

    public mutating func add(_ q: Question) {
        questions.append(q)
        byId[q.id] = q
    }
}

public struct DownloadProgress: Sendable {
    public var stage: String
    public var done: Int
    public var total: Int
    public var failed: Int
}

public struct DownloadSummary: Sendable {
    public var added: Int
    public var failed: Int
    public var total: Int
}

public struct BankError: LocalizedError {
    public var message: String
    public var errorDescription: String? { message }
}

/// The local copy of the question bank. Raw responses are kept in bank.jsonl (one question per line),
/// so the download can resume where it stopped and parsing can improve without downloading again.
public enum BankStore {
    static let api = "https://qbank-api.collegeboard.org/msreportingquestionbank-prod/questionbank"
    static let disclosed = "https://saic.collegeboard.org/disclosed/"

    public static var dataDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Margin", isDirectory: true)
    }()

    public static var bankURL: URL { dataDir.appendingPathComponent("bank.jsonl") }
    public static var lookupURL: URL { dataDir.appendingPathComponent("lookup.json") }

    public static func load() -> Bank {
        var bank = Bank()
        guard let text = try? String(contentsOf: bankURL, encoding: .utf8) else { return bank }
        let live = loadLiveIds()
        var seenKeys = Set<String>()
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let node = try? JSONSerialization.jsonObject(with: data),      // skips a line cut short by a crash
                  let q = Normalizer.question(fromLine: node, liveIds: live) else { continue }
            let key = q.externalId ?? q.ibn ?? q.id
            if !seenKeys.insert(key).inserted || bank.byId[q.id] != nil { continue }
            if !q.gradable { bank.unusable += 1; continue }
            bank.add(q)
        }
        bank.updated = (try? FileManager.default.attributesOfItem(atPath: bankURL.path)[.modificationDate]) as? Date
        return bank
    }

    private static func loadLiveIds() -> Set<String> {
        guard let data = try? Data(contentsOf: lookupURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var ids = Set<String>()
        for name in ["readingLiveItems", "mathLiveItems"] {
            for case let s as String in (root[name] as? [Any]) ?? [] { ids.insert(s) }
        }
        return ids
    }

    private static func storedIds() -> Set<String> {
        guard let text = try? String(contentsOf: bankURL, encoding: .utf8) else { return [] }
        var ids = Set<String>()
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let stub = o["stub"] as? [String: Any], let id = Normalizer.str(stub["questionId"]) else { continue }
            ids.insert(id)
        }
        return ids
    }

    // ---- download ----

    /// Performs one request and returns the body and HTTP status. Replaceable so the downloader can be tested offline.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)

    public static let defaultTransport: Transport = { request in
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Data, Int), Error>) in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: (data ?? Data(), (response as? HTTPURLResponse)?.statusCode ?? 0))
            }
            task.resume()
        }
    }

    private struct Todo: Sendable {
        var test: Int
        var externalId: String?
        var ibn: String?
        var stubJSON: String
    }

    private static func request(_ url: String, json body: [String: Any]? = nil) throws -> URLRequest {
        guard let u = URL(string: url) else { throw BankError(message: "Bad address: \(url)") }
        var r = URLRequest(url: u, timeoutInterval: 60)
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("Margin/1.0", forHTTPHeaderField: "User-Agent")
        if let body {
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return r
    }

    /// Fetches one question body and returns it as compact single-line JSON, or nil after three failed attempts.
    private static func fetchDetail(_ item: Todo, _ transport: Transport) async -> String? {
        for attempt in 0..<3 {
            if Task.isCancelled { return nil }
            do {
                let req: URLRequest
                if let ext = item.externalId {
                    req = try request(api + "/digital/get-question", json: ["external_id": ext])
                } else if let ibn = item.ibn {
                    let safe = ibn.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ibn
                    req = try request(disclosed + safe + ".json")
                } else { return nil }
                let (data, status) = try await transport(req)
                if (200..<300).contains(status) {
                    let node = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
                    if node is [String: Any] || node is [Any] {
                        let compact = try JSONSerialization.data(withJSONObject: node)
                        if let s = String(data: compact, encoding: .utf8) { return s }
                    }
                }
            } catch { /* retry below */ }
            try? await Task.sleep(nanoseconds: UInt64(1 + attempt * 2) * 1_000_000_000)
        }
        return nil
    }

    /// Downloads every question not yet stored. Safe to cancel and run again.
    public static func download(parallel: Int = 6,
                                transport: @escaping Transport = defaultTransport,
                                progress: @escaping @Sendable (DownloadProgress) -> Void = { _ in }) async throws -> DownloadSummary {
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        progress(DownloadProgress(stage: "Reading the question list", done: 0, total: 0, failed: 0))

        if let (data, status) = try? await transport(try request(api + "/lookup")), (200..<300).contains(status),
           (try? JSONSerialization.jsonObject(with: data)) is [String: Any] {
            try? data.write(to: lookupURL, options: .atomic)
        }
        try Task.checkCancellation()

        var stubs: [(Int, [String: Any])] = []
        for (test, domains) in [(1, "INI,CAS,EOI,SEC"), (2, "H,P,Q,S")] {
            let body: [String: Any] = ["asmtEventId": 99, "test": test, "domain": domains]
            let (data, status) = try await transport(try request(api + "/digital/get-questions", json: body))
            guard (200..<300).contains(status) else { throw BankError(message: "The question bank answered with an error (\(status)).") }
            guard let list = try JSONSerialization.jsonObject(with: data) as? [Any] else {
                throw BankError(message: "The question list came back in an unexpected format.")
            }
            for case let o as [String: Any] in list { stubs.append((test, o)) }
            try Task.checkCancellation()
        }

        let have = storedIds()
        var keys = Set<String>()
        var todo: [Todo] = []
        for (test, stub) in stubs {
            let ext = Normalizer.nonEmpty(Normalizer.str(stub["external_id"]))
            let ibn = Normalizer.nonEmpty(Normalizer.str(stub["ibn"]))
            guard let id = Normalizer.nonEmpty(Normalizer.str(stub["questionId"])), let key = ext ?? ibn else { continue }
            // The same question is occasionally listed twice under different ids.
            if !keys.insert(key).inserted || have.contains(id) { continue }
            guard let data = try? JSONSerialization.data(withJSONObject: stub), let json = String(data: data, encoding: .utf8) else { continue }
            todo.append(Todo(test: test, externalId: ext, ibn: ext == nil ? ibn : nil, stubJSON: json))
        }

        let total = todo.count
        var done = 0, failed = 0
        progress(DownloadProgress(stage: "Downloading questions", done: 0, total: total, failed: 0))
        if total == 0 { return DownloadSummary(added: 0, failed: 0, total: stubs.count) }

        if !FileManager.default.fileExists(atPath: bankURL.path) { FileManager.default.createFile(atPath: bankURL.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: bankURL)
        defer { try? handle.close() }
        try handle.seekToEnd()

        try await withThrowingTaskGroup(of: (Int, String?).self) { group in
            var next = 0
            while next < min(max(1, parallel), total) {
                let i = next; let item = todo[i]; next += 1
                group.addTask { (i, await fetchDetail(item, transport)) }
            }
            while let (i, detail) = try await group.next() {
                if let detail {
                    let line = "{\"test\":\(todo[i].test),\"stub\":\(todo[i].stubJSON),\"detail\":\(detail)}\n"
                    try handle.write(contentsOf: Data(line.utf8))
                } else {
                    failed += 1
                }
                done += 1
                if done % 5 == 0 || done == total {
                    progress(DownloadProgress(stage: "Downloading questions", done: done, total: total, failed: failed))
                }
                try Task.checkCancellation()
                if next < total {
                    let j = next; let item = todo[j]; next += 1
                    group.addTask { (j, await fetchDetail(item, transport)) }
                }
            }
        }
        return DownloadSummary(added: total - failed, failed: failed, total: stubs.count)
    }

    public static func deleteLocalCopy() {
        try? FileManager.default.removeItem(at: bankURL)
        try? FileManager.default.removeItem(at: lookupURL)
    }
}

public enum HistoryStore {
    public static var historyURL: URL { BankStore.dataDir.appendingPathComponent("history.json") }

    public static func load() -> [SessionResult] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SessionResult].self, from: data)) ?? []
    }

    public static func save(_ all: [SessionResult]) throws {
        try FileManager.default.createDirectory(at: BankStore.dataDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(all).write(to: historyURL, options: .atomic)
    }

    public static func seenIds(_ all: [SessionResult]) -> Set<String> {
        Set(all.flatMap { $0.modules }.flatMap { $0.items }.map { $0.questionId })
    }

    /// Questions whose most recent attempt was wrong or blank.
    public static func missedIds(_ all: [SessionResult]) -> Set<String> {
        var last: [String: Bool] = [:]
        for s in all.sorted(by: { $0.date < $1.date }) {
            for i in s.modules.flatMap({ $0.items }) { last[i.questionId] = i.correct }
        }
        return Set(last.filter { !$0.value }.keys)
    }
}
