import Foundation

public enum SessionPhase: Sendable { case question, review, onBreak, finished }

public struct ModuleState {
    public var title = ""
    public var section: Subject?            // nil for a mixed custom quiz
    public var questions: [Question] = []
    public var timeLimitSec: Int?
    public var remainingSec = 0
    public var usedSec = 0
    public var route: String?
    public var answers: [String: String] = [:]
    public var marked: Set<String> = []
    public var eliminated: [String: [String]] = [:]
    public var seconds: [String: Int] = [:]

    public func isAnswered(_ q: Question) -> Bool {
        guard let a = answers[q.id] else { return false }
        return !a.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    public var answeredCount: Int { questions.filter { isAnswered($0) }.count }
}

/// One sitting: a custom quiz (a single module) or an adaptive test (two modules per section,
/// the second one chosen by how the first went).
public final class TestSession {
    private let bank: Bank
    private let options: AssemblyOptions
    private var used = Set<String>()
    private var plan: [(section: Subject, number: Int)] = []
    private var planIndex = 0

    public private(set) var kind = "quiz"
    public private(set) var title = ""
    public private(set) var modules: [ModuleState] = []
    public private(set) var phase: SessionPhase = .question
    public private(set) var questionIndex = 0
    public private(set) var breakRemaining = 0

    public var module: ModuleState { modules[modules.count - 1] }
    public var current: Question {
        let m = module
        return m.questions[min(max(questionIndex, 0), m.questions.count - 1)]
    }
    public var isAdaptive: Bool { !plan.isEmpty }
    public var isLastModule: Bool { !isAdaptive || planIndex >= plan.count - 1 }

    private init(bank: Bank, options: AssemblyOptions) {
        self.bank = bank
        self.options = options
    }

    public static func quiz(bank: Bank, questions: [Question], timed: Bool, title: String = "Custom Quiz") -> TestSession {
        let s = TestSession(bank: bank, options: AssemblyOptions())
        s.kind = "quiz"
        s.title = title
        var m = ModuleState()
        m.title = title
        let sections = Set(questions.map { $0.section })
        m.section = sections.count == 1 ? sections.first : nil
        m.questions = questions
        if timed {
            let limit = max(60, questions.reduce(0) { $0 + Assembler.paceSeconds($1.section) })
            m.timeLimitSec = limit
            m.remainingSec = limit
        }
        s.modules.append(m)
        if questions.isEmpty { s.phase = .finished }
        return s
    }

    /// kind: "full" (both sections), "rw" or "math".
    public static func adaptive(bank: Bank, kind: String, options: AssemblyOptions) -> TestSession {
        let s = TestSession(bank: bank, options: options)
        s.kind = kind
        if kind == "full" || kind == "rw" { s.plan.append((.rw, 1)); s.plan.append((.rw, 2)) }
        if kind == "full" || kind == "math" { s.plan.append((.math, 1)); s.plan.append((.math, 2)) }
        s.title = kind == "rw" ? "Reading and Writing Section" : kind == "math" ? "Math Section" : "Full-Length Adaptive Test"
        s.startPlannedModule(route: nil)
        return s
    }

    private func startPlannedModule(route: String?) {
        let (section, number) = plan[planIndex]
        let level: ModuleLevel = number == 1 ? .first : (route == "higher" ? .higher : .lower)
        var m = ModuleState()
        m.title = "\(section.title) · Module \(number)"
        m.section = section
        m.questions = Assembler.build(bank: bank, section: section, level: level, options: options, used: &used)
        m.timeLimitSec = Assembler.moduleSeconds(section)
        m.remainingSec = Assembler.moduleSeconds(section)
        m.route = number == 2 ? route : nil
        modules.append(m)
        questionIndex = 0
        phase = m.questions.isEmpty ? .finished : .question
    }

    private func editModule(_ change: (inout ModuleState) -> Void) {
        change(&modules[modules.count - 1])
    }

    // ---- interaction ----

    public func setAnswer(_ value: String?) {
        guard phase == .question else { return }
        let id = current.id
        let v = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        editModule { m in
            if v.isEmpty { m.answers[id] = nil } else { m.answers[id] = v }
        }
    }

    public func setMarked(_ on: Bool) {
        guard phase == .question else { return }
        let id = current.id
        editModule { m in
            if on { m.marked.insert(id) } else { m.marked.remove(id) }
        }
    }

    public func setEliminated(_ letters: [String]) {
        guard phase == .question else { return }
        let id = current.id
        editModule { $0.eliminated[id] = letters }
    }

    public func go(to index: Int) {
        guard phase == .question || phase == .review else { return }
        questionIndex = min(max(index, 0), module.questions.count - 1)
        phase = .question
    }

    /// Moves forward; after the last question this opens the module's review page.
    public func next() {
        guard phase == .question else { return }
        if questionIndex >= module.questions.count - 1 { phase = .review } else { questionIndex += 1 }
    }

    public func back() {
        if phase == .review {
            phase = .question
            questionIndex = module.questions.count - 1
        } else if phase == .question, questionIndex > 0 {
            questionIndex -= 1
        }
    }

    public func openReview() {
        if phase == .question { phase = .review }
    }

    /// Call once per second while the session is on screen.
    public func tick() {
        switch phase {
        case .question, .review:
            let id = current.id
            let onQuestion = phase == .question
            var expired = false
            editModule { m in
                m.usedSec += 1
                if onQuestion { m.seconds[id, default: 0] += 1 }
                if m.timeLimitSec != nil {
                    m.remainingSec = max(0, m.remainingSec - 1)
                    expired = m.remainingSec == 0
                }
            }
            if expired { submitModule() }
        case .onBreak:
            breakRemaining = max(0, breakRemaining - 1)
            if breakRemaining == 0 { endBreak() }
        case .finished:
            break
        }
    }

    public func submitModule() {
        guard phase == .question || phase == .review else { return }
        if !isAdaptive || planIndex >= plan.count - 1 { phase = .finished; return }

        let finished = plan[planIndex]
        planIndex += 1
        let upcoming = plan[planIndex]
        if upcoming.section == finished.section {
            let m = module
            let correct = m.questions.filter { Grader.isCorrect($0, m.answers[$0.id]) }.count
            let share = m.questions.isEmpty ? 0 : Double(correct) / Double(m.questions.count)
            startPlannedModule(route: share >= Assembler.routeThreshold ? "higher" : "lower")
        } else {
            phase = .onBreak
            breakRemaining = Assembler.breakSeconds
        }
    }

    public func endBreak() {
        guard phase == .onBreak else { return }
        startPlannedModule(route: nil)
    }

    // ---- results ----

    public func buildResult() -> SessionResult {
        var r = SessionResult(kind: kind, title: title)
        for m in modules {
            var mr = ModuleResult(title: m.title, section: m.section?.rawValue ?? "mixed", route: m.route,
                                  timeLimitSec: m.timeLimitSec, usedSec: m.usedSec)
            for q in m.questions {
                let a = m.answers[q.id]
                mr.items.append(ResultItem(questionId: q.id, answer: a, correct: Grader.isCorrect(q, a),
                                           marked: m.marked.contains(q.id), seconds: m.seconds[q.id] ?? 0))
            }
            r.modules.append(mr)
        }
        if isAdaptive {
            for section in Subject.allCases {
                let mods = modules.filter { $0.section == section }
                if mods.count < 2 { continue }   // a section only gets a score when both modules were taken
                let responses = mods.flatMap { m in m.questions.map { (band: $0.band, correct: Grader.isCorrect($0, m.answers[$0.id])) } }
                let score = Scoring.estimate(responses)
                if section == .rw { r.rwScore = score } else { r.mathScore = score }
            }
        }
        return r
    }
}
