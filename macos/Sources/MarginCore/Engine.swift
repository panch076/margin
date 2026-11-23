import Foundation

public struct AssemblyOptions: Sendable {
    public var excludeLive = true
    public var preferUnseen = true
    public var seen: Set<String> = []
    public init(excludeLive: Bool = true, preferUnseen: Bool = true, seen: Set<String> = []) {
        self.excludeLive = excludeLive; self.preferUnseen = preferUnseen; self.seen = seen
    }
}

public enum ModuleLevel: Sendable { case first, higher, lower }

/// Builds test modules from the bank using the published digital SAT blueprint:
/// Reading and Writing has two 27-question, 32-minute modules; Math has two 22-question, 35-minute modules.
public enum Assembler {
    public static func moduleSize(_ s: Subject) -> Int { s == .rw ? 27 : 22 }
    public static func moduleSeconds(_ s: Subject) -> Int { s == .rw ? 32 * 60 : 35 * 60 }
    public static func paceSeconds(_ s: Subject) -> Int { s == .rw ? 71 : 95 }
    public static let breakSeconds = 10 * 60
    /// Share correct in module 1 that routes to the higher-difficulty module 2.
    public static let routeThreshold = 0.60

    private static let rwPlan: [(String, Int)] = [("CAS", 7), ("INI", 7), ("SEC", 7), ("EOI", 6)]
    private static let mathPlan: [(String, Int)] = [("H", 7), ("P", 7), ("Q", 4), ("S", 4)]

    private static func mix(_ level: ModuleLevel) -> [Double] {
        switch level {
        case .higher: return [0.10, 0.35, 0.55]
        case .lower: return [0.55, 0.35, 0.10]
        case .first: return [0.35, 0.40, 0.25]
        }
    }

    public static func build(bank: Bank, section: Subject, level: ModuleLevel, options: AssemblyOptions, used: inout Set<String>) -> [Question] {
        var best: [Question] = []
        var bestGap = Double.greatestFiniteMagnitude
        // Math modules carry roughly a quarter typed-answer questions; draw a few candidates and keep the closest.
        let tries = section == .math ? 12 : 1
        for _ in 0..<tries {
            let pick = draw(bank: bank, section: section, level: level, options: options, used: used)
            let gap = section == .math ? abs(Double(pick.filter { $0.isSpr }.count) - 5.5) : 0
            if gap < bestGap { best = pick; bestGap = gap }
            if gap <= 0.5 { break }
        }
        for q in best { used.insert(q.id) }
        if section == .rw {
            return best.sorted { a, b in
                let ka = (Catalog.domainOrder(a.domain), a.skill, a.band), kb = (Catalog.domainOrder(b.domain), b.skill, b.band)
                return ka < kb
            }
        }
        return best.shuffled().sorted { $0.band < $1.band }
    }

    private static func draw(bank: Bank, section: Subject, level: ModuleLevel, options: AssemblyOptions, used: Set<String>) -> [Question] {
        let plan = section == .rw ? rwPlan : mathPlan
        let shares = mix(level)
        var taken = Set<String>()
        var result: [Question] = []

        func pool(allowLive: Bool, _ filter: (Question) -> Bool) -> [Question] {
            let list = bank.questions.filter { q in
                q.section == section && !used.contains(q.id) && !taken.contains(q.id)
                    && (allowLive || !options.excludeLive || !q.live) && filter(q)
            }.shuffled()
            guard options.preferUnseen else { return list }
            return list.filter { !options.seen.contains($0.id) } + list.filter { options.seen.contains($0.id) }
        }
        func take(_ source: [Question], _ n: Int) {
            var left = n
            for q in source {
                if left <= 0 { break }
                if taken.insert(q.id).inserted { result.append(q); left -= 1 }
            }
        }

        for (domain, count) in plan {
            let want = apportion(count, shares)
            let before = result.count
            for (i, diff) in ["E", "M", "H"].enumerated() {
                take(pool(allowLive: false) { $0.domain == domain && $0.difficulty == diff }, want[i])
            }
            // Top up from the same domain, then relax the rules, if a difficulty pool ran short.
            var missing = count - (result.count - before)
            if missing > 0 { take(pool(allowLive: false) { $0.domain == domain }, missing); missing = count - (result.count - before) }
            if missing > 0 { take(pool(allowLive: true) { $0.domain == domain }, missing) }
        }
        let shortBy = moduleSize(section) - result.count
        if shortBy > 0 { take(pool(allowLive: true) { _ in true }, shortBy) }
        return result
    }

    /// Splits n into whole counts in proportion to the shares (largest remainder).
    static func apportion(_ n: Int, _ shares: [Double]) -> [Int] {
        let raw = shares.map { Double(n) * $0 }
        var counts = raw.map { Int($0.rounded(.down)) }
        var left = n - counts.reduce(0, +)
        for i in raw.indices.sorted(by: { raw[$0] - Double(counts[$0]) > raw[$1] - Double(counts[$1]) }) {
            if left <= 0 { break }
            counts[i] += 1; left -= 1
        }
        return counts
    }
}

public enum Scoring {
    /// A rough section score on the 200-800 scale. Each question's difficulty comes from its score band,
    /// ability is estimated with a one-parameter logistic model, and the result is mapped to the scale.
    /// The real test uses calibrated item parameters that are not published, so treat this as a ballpark.
    public static func estimate(_ responses: [(band: Int, correct: Bool)]) -> Int {
        guard !responses.isEmpty else { return 200 }
        let priorVar = 2.0 * 2.0
        var theta = 0.0
        for _ in 0..<40 {
            var g = -theta / priorVar
            var hess = -1 / priorVar
            for r in responses {
                let b = Double(r.band - 4) * 0.6
                let p = 1 / (1 + exp(-(theta - b)))
                g += (r.correct ? 1 : 0) - p
                hess -= p * (1 - p)
            }
            let step = g / hess
            theta -= step
            if abs(step) < 1e-6 { break }
        }
        let scaled = ((500 + 75 * theta) / 10).rounded() * 10
        return Int(min(800, max(200, scaled)))
    }
}
