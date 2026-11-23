import Foundation

public enum Subject: String, Codable, Sendable, CaseIterable {
    case rw, math
    public var title: String { self == .rw ? "Reading and Writing" : "Math" }
    public var order: Int { self == .rw ? 0 : 1 }
}

public struct Question: Identifiable, Hashable, Sendable {
    public var id: String
    public var externalId: String?
    public var ibn: String?
    public var section: Subject
    public var domain: String
    public var domainName: String
    public var skill: String
    public var difficulty: String      // E, M, H
    public var band: Int               // 1 (easiest) to 7 (hardest)
    public var live: Bool              // also appears on an official full-length practice test
    public var isSpr: Bool             // student-produced response (typed answer)
    public var stimulus: String
    public var stem: String
    public var rationale: String
    public var choices: [String]
    public var correct: [String]
    public var keyRecovered: Bool

    public init(id: String, externalId: String? = nil, ibn: String? = nil, section: Subject = .rw, domain: String = "",
                domainName: String = "", skill: String = "", difficulty: String = "M", band: Int = 4, live: Bool = false,
                isSpr: Bool = false, stimulus: String = "", stem: String = "", rationale: String = "",
                choices: [String] = [], correct: [String] = [], keyRecovered: Bool = false) {
        self.id = id; self.externalId = externalId; self.ibn = ibn; self.section = section; self.domain = domain
        self.domainName = domainName; self.skill = skill; self.difficulty = difficulty; self.band = band; self.live = live
        self.isSpr = isSpr; self.stimulus = stimulus; self.stem = stem; self.rationale = rationale
        self.choices = choices; self.correct = correct; self.keyRecovered = keyRecovered
    }

    public var gradable: Bool { !stem.isEmpty && !correct.isEmpty && (isSpr || choices.count >= 2) }
    public var difficultyName: String { difficulty == "E" ? "Easy" : difficulty == "H" ? "Hard" : "Medium" }

    public static func == (a: Question, b: Question) -> Bool { a.id == b.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public struct DomainInfo: Sendable, Identifiable {
    public let code: String
    public let name: String
    public let section: Subject
    public var id: String { code }
}

public enum Catalog {
    /// Listed in the order the domains appear inside a Reading and Writing module.
    public static let domains: [DomainInfo] = [
        DomainInfo(code: "CAS", name: "Craft and Structure", section: .rw),
        DomainInfo(code: "INI", name: "Information and Ideas", section: .rw),
        DomainInfo(code: "SEC", name: "Standard English Conventions", section: .rw),
        DomainInfo(code: "EOI", name: "Expression of Ideas", section: .rw),
        DomainInfo(code: "H", name: "Algebra", section: .math),
        DomainInfo(code: "P", name: "Advanced Math", section: .math),
        DomainInfo(code: "Q", name: "Problem-Solving and Data Analysis", section: .math),
        DomainInfo(code: "S", name: "Geometry and Trigonometry", section: .math),
    ]

    public static func domainName(_ code: String) -> String { domains.first { $0.code == code }?.name ?? code }
    public static func section(of code: String) -> Subject? { domains.first { $0.code == code }?.section }
    public static func domainOrder(_ code: String) -> Int { domains.firstIndex { $0.code == code } ?? 99 }
}

public struct ResultItem: Codable, Sendable, Hashable {
    public var questionId: String
    public var answer: String?
    public var correct: Bool
    public var marked: Bool
    public var seconds: Int

    public init(questionId: String, answer: String? = nil, correct: Bool = false, marked: Bool = false, seconds: Int = 0) {
        self.questionId = questionId; self.answer = answer; self.correct = correct; self.marked = marked; self.seconds = seconds
    }
}

public struct ModuleResult: Codable, Sendable, Hashable {
    public var title: String
    public var section: String          // "rw", "math" or "mixed"
    public var route: String?           // "higher" / "lower" for an adaptive second module
    public var timeLimitSec: Int?
    public var usedSec: Int
    public var items: [ResultItem]

    public init(title: String = "", section: String = "mixed", route: String? = nil, timeLimitSec: Int? = nil, usedSec: Int = 0, items: [ResultItem] = []) {
        self.title = title; self.section = section; self.route = route; self.timeLimitSec = timeLimitSec; self.usedSec = usedSec; self.items = items
    }

    public var correctCount: Int { items.filter { $0.correct }.count }
}

public struct SessionResult: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var date: Date
    public var kind: String             // quiz, full, rw, math
    public var title: String
    public var modules: [ModuleResult]
    public var rwScore: Int?
    public var mathScore: Int?

    public init(id: String = UUID().uuidString, date: Date = Date(), kind: String = "quiz", title: String = "",
                modules: [ModuleResult] = [], rwScore: Int? = nil, mathScore: Int? = nil) {
        self.id = id; self.date = date; self.kind = kind; self.title = title; self.modules = modules
        self.rwScore = rwScore; self.mathScore = mathScore
    }

    public var totalScore: Int? {
        guard let r = rwScore, let m = mathScore else { return nil }
        return r + m
    }
    public var correctCount: Int { modules.reduce(0) { $0 + $1.correctCount } }
    public var questionCount: Int { modules.reduce(0) { $0 + $1.items.count } }
}
