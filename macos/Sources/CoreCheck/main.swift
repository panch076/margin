// Self-test for the engine. Run with:  swift run CoreCheck
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import MarginCore

var pass = 0, fail = 0
func check(_ ok: Bool, _ name: String) {
    if ok { pass += 1 } else { fail += 1; print("FAIL: " + name) }
}
func parse(_ json: String) -> Any? { try? JSONSerialization.jsonObject(with: Data(json.utf8)) }

// ---------- grader ----------
let spr = Question(id: "s", isSpr: true, stem: "x", correct: ["2/3", ".6666", ".6667", "0.666", "0.667"])
check(Grader.isCorrect(spr, "2/3") && Grader.isCorrect(spr, "4/6") && Grader.isCorrect(spr, ".667") && Grader.isCorrect(spr, "0.666"), "fraction forms")
check(!Grader.isCorrect(spr, ".67") && !Grader.isCorrect(spr, "0.7") && !Grader.isCorrect(spr, "") && !Grader.isCorrect(spr, nil), "wrong forms")
let nine = Question(id: "n", isSpr: true, stem: "x", correct: ["9"])
check(Grader.isCorrect(nine, "9") && Grader.isCorrect(nine, "9.0") && Grader.isCorrect(nine, "18/2") && !Grader.isCorrect(nine, "9.001") && !Grader.isCorrect(nine, "-9"), "integer forms")
let neg = Question(id: "g", isSpr: true, stem: "x", correct: ["-1/3"])
check(Grader.isCorrect(neg, "-.3333") && Grader.isCorrect(neg, "-1/3") && !Grader.isCorrect(neg, "1/3"), "negative")
let mcq = Question(id: "m", stem: "x", choices: ["a", "b", "c", "d"], correct: ["B"])
check(Grader.isCorrect(mcq, "B") && Grader.isCorrect(mcq, "b") && !Grader.isCorrect(mcq, "A") && !Grader.isCorrect(mcq, nil), "mcq")

// ---------- normalizer ----------
let n1 = Normalizer.question(fromLine: parse("""
{"test":1,"stub":{"questionId":"aaa111","external_id":"ext-1","ibn":null,"primary_class_cd":"CAS","primary_class_cd_desc":"Craft and Structure","skill_desc":"Words in Context","difficulty":"H","score_band_range_cd":6},
 "detail":{"keys":["k2"],"rationale":"<p>Choice B is the best answer.</p>","stem":"<p>Which?</p>","stimulus":"<p>Text<script>alert(1)</script></p>","type":"mcq","answerOptions":[{"id":"k1","content":"<p>one</p>"},{"id":"k2","content":"<p>two</p>"},{"id":"k3","content":"<p>three</p>"},{"id":"k4","content":"<p>four</p>"}],"correct_answer":["B"]}}
"""), liveIds: ["ext-1"])!
check(n1.gradable && n1.section == .rw && n1.correct == ["B"] && n1.choices.count == 4 && n1.live && n1.band == 6 && !n1.isSpr && !n1.stimulus.contains("script"), "current mcq")
let n2 = Normalizer.question(fromLine: parse("""
{"test":1,"stub":{"questionId":"aaa112","external_id":"ext-2","primary_class_cd":"INI","skill_desc":"Inferences","difficulty":"E","score_band_range_cd":2},
 "detail":{"keys":["k3"],"rationale":"r","stem":"s","answerOptions":"[{\\"id\\":\\"k1\\",\\"content\\":\\"a\\"},{\\"id\\":\\"k2\\",\\"content\\":\\"b\\"},{\\"id\\":\\"k3\\",\\"content\\":\\"c\\"},{\\"id\\":\\"k4\\",\\"content\\":\\"d\\"}]"}}
"""), liveIds: ["ext-1"])!
check(n2.gradable && n2.correct == ["C"] && !n2.live, "key ids + encoded options")
let n3 = Normalizer.question(fromLine: parse("""
{"test":2,"stub":{"questionId":"bbb1","external_id":"ext-3","primary_class_cd":"H","skill_desc":"Linear functions","difficulty":"M","score_band_range_cd":4},
 "detail":{"rationale":"<p>The correct answer is 3.5.</p>","stem":"<p>Value?</p>","type":"spr","correct_answer":["3.5","7/2"]}}
"""))!
check(n3.gradable && n3.isSpr && n3.section == .math && n3.correct.count == 2 && Grader.isCorrect(n3, "7/2"), "current spr")
let n4 = Normalizer.question(fromLine: parse("""
{"test":2,"stub":{"questionId":"ccc1","external_id":null,"ibn":"IBN-9","primary_class_cd":"S","skill_desc":"Circles","difficulty":"H","score_band_range_cd":7},
 "detail":[{"item_id":"IBN-9","prompt":"<p>Old?</p>","body":"<p>fig</p>","answer":{"style":"Multiple Choice","choices":{"b":{"body":"B!"},"a":{"body":"A!"},"d":{"body":"D!"},"c":{"body":"C!"}},"correct_choice":"c","rationale":"<p>Choice C is correct.</p>"}}]}
"""))!
check(n4.gradable && n4.choices.first == "A!" && n4.choices.last == "D!" && n4.correct == ["C"] && n4.ibn == "IBN-9" && n4.externalId == nil && n4.stimulus.contains("fig"), "disclosed mcq")
let n5 = Normalizer.question(fromLine: parse("""
{"test":2,"stub":{"questionId":"ccc2","ibn":"IBN-10","primary_class_cd":"P","difficulty":"M","score_band_range_cd":3},
 "detail":[{"prompt":"<p>Old spr?</p>","answer":{"style":"SPR","rationale":"<p>The correct answer is <strong>1.5</strong>. Note that 1.5 and 3/2 are examples of ways to enter a correct answer.</p>"}}]}
"""))!
check(n5.gradable && n5.isSpr && n5.keyRecovered && n5.correct.contains("1.5"), "disclosed spr key recovered: \(n5.correct)")
let n6 = Normalizer.question(fromLine: parse("""
{"test":2,"stub":{"questionId":"ccc3","ibn":"IBN-11","primary_class_cd":"P","difficulty":"M","score_band_range_cd":3},
 "detail":[{"prompt":"<p>Old?</p>","answer":{"style":"Multiple Choice","choices":{"a":{"body":"1"},"b":{"body":"2"},"c":{"body":"3"},"d":{"body":"4"}},"rationale":"<p>Choice D is correct. Choice A is incorrect.</p>"}}]}
"""))!
check(n6.gradable && n6.correct == ["D"] && n6.keyRecovered, "disclosed mcq key recovered")
let n7 = Normalizer.question(fromLine: parse(#"{"test":1,"stub":{"questionId":"zzz","external_id":"e9","primary_class_cd":"CAS"},"detail":{"unexpected":true}}"#))!
check(!n7.gradable, "unknown shape is unusable, not a crash")
check(Normalizer.question(fromLine: parse("[1,2]")) == nil && Normalizer.question(fromLine: nil) == nil, "garbage line")

// ---------- synthetic bank ----------
func synthetic(perCell: Int) -> Bank {
    var bank = Bank()
    for d in Catalog.domains {
        for (diff, bands) in [("E", [1, 2, 3]), ("M", [3, 4, 5]), ("H", [5, 6, 7])] {
            for i in 0..<perCell {
                let isSpr = d.section == .math && Int.random(in: 0..<4) == 0
                var q = Question(id: "\(d.code)-\(diff)-\(i)", externalId: "x-\(d.code)-\(diff)-\(i)", section: d.section, domain: d.code,
                                 domainName: d.name, skill: "Skill \(i % 3)", difficulty: diff, band: bands.randomElement()!,
                                 live: i % 2 == 0, isSpr: isSpr, stem: "stem")
                if isSpr { q.correct = ["7"] } else { q.choices = ["a", "b", "c", "d"]; q.correct = ["A"] }
                bank.add(q)
            }
        }
    }
    return bank
}
let big = synthetic(perCell: 60)
func avgBand(_ qs: [Question]) -> Double { Double(qs.reduce(0) { $0 + $1.band }) / Double(max(1, qs.count)) }

// ---------- assembler ----------
do {
    var used = Set<String>()
    let opt = AssemblyOptions()
    let rw1 = Assembler.build(bank: big, section: .rw, level: .first, options: opt, used: &used)
    check(rw1.count == 27 && rw1.allSatisfy { $0.section == .rw && !$0.live }, "rw module size, no live")
    check(rw1.filter { $0.domain == "CAS" }.count == 7 && rw1.filter { $0.domain == "EOI" }.count == 6, "rw blueprint")
    let order = rw1.map { Catalog.domainOrder($0.domain) }
    check(order == order.sorted(), "rw domain order")
    let hi = Assembler.build(bank: big, section: .rw, level: .higher, options: opt, used: &used)
    let lo = Assembler.build(bank: big, section: .rw, level: .lower, options: opt, used: &used)
    check(hi.count == 27 && lo.count == 27 && avgBand(hi) > avgBand(rw1) && avgBand(lo) < avgBand(rw1), "difficulty by level")
    check(used.count == 81, "no repeats across modules")
    let m1 = Assembler.build(bank: big, section: .math, level: .first, options: opt, used: &used)
    let sprCount = m1.filter { $0.isSpr }.count
    check(m1.count == 22 && sprCount >= 4 && sprCount <= 7, "math module, typed answers = \(sprCount)")
    check(m1.map { $0.band } == m1.map { $0.band }.sorted(), "math ordered by difficulty")
    print(String(format: "  bands  m1 %.2f  higher %.2f  lower %.2f", avgBand(rw1), avgBand(hi), avgBand(lo)))
    let seen = Set(big.questions.filter { $0.section == .math && $0.id.hasSuffix("1") }.map { $0.id })
    var fresh = Set<String>()
    let m2 = Assembler.build(bank: big, section: .math, level: .first, options: AssemblyOptions(seen: seen), used: &fresh)
    check(m2.allSatisfy { !seen.contains($0.id) }, "prefers unseen")
    var tinyUsed = Set<String>()
    let t = Assembler.build(bank: synthetic(perCell: 1), section: .rw, level: .higher, options: AssemblyOptions(), used: &tinyUsed)
    check(t.count == 12 && Set(t.map { $0.id }).count == 12, "tiny bank: uses all 12 once, got \(t.count)")
}

// ---------- scoring ----------
do {
    let hard = (0..<27).map { 1 + $0 % 7 } + (0..<27).map { 4 + $0 % 4 }
    let easy = (0..<27).map { 1 + $0 % 7 } + (0..<27).map { 1 + $0 % 4 }
    let perfect = Scoring.estimate(hard.map { (band: $0, correct: true) })
    let zero = Scoring.estimate(easy.map { (band: $0, correct: false) })
    let miss3 = Scoring.estimate(hard.enumerated().map { (band: $1, correct: $0 < 51) })
    let miss8 = Scoring.estimate(hard.enumerated().map { (band: $1, correct: $0 % 7 != 0) })
    let half = Scoring.estimate((Array(hard.prefix(27)) + Array(easy.suffix(27))).enumerated().map { (band: $1, correct: $0 % 2 == 0) })
    let third = Scoring.estimate(easy.enumerated().map { (band: $1, correct: $0 % 3 == 0) })
    print("  scores  perfect \(perfect)  miss3 \(miss3)  miss8 \(miss8)  half \(half)  third \(third)  zero \(zero)")
    check(perfect == 800 && zero == 200 && miss3 == 750 && miss8 == 680 && half == 460 && third == 400, "scores match the Windows build")
}

// ---------- session ----------
do {
    let s = TestSession.adaptive(bank: big, kind: "full", options: AssemblyOptions())
    check(s.modules.count == 1 && s.module.questions.count == 27 && s.module.remainingSec == 1920 && s.phase == .question, "full test starts")
    for q in s.module.questions { s.setAnswer(q.correct[0]); s.tick(); s.next() }
    check(s.phase == .review, "last next opens review")
    s.back(); check(s.phase == .question && s.questionIndex == 26, "back from review")
    s.openReview(); s.submitModule()
    check(s.modules.count == 2 && s.module.route == "higher" && s.phase == .question && s.questionIndex == 0, "routes higher")
    check(Set(s.modules[0].questions.map { $0.id }).isDisjoint(with: s.module.questions.map { $0.id }), "module 2 has new questions")
    for _ in 0..<1920 { s.tick() }
    check(s.phase == .onBreak && s.breakRemaining == 600, "time expiry submits, break starts")
    s.setAnswer("A"); check(s.modules.count == 2, "input ignored on break")
    s.endBreak()
    check(s.modules.count == 3 && s.module.section == .math && s.module.remainingSec == 2100, "math module 1")
    s.setAnswer("zzz"); s.submitModule()
    check(s.modules.count == 4 && s.module.route == "lower", "routes lower")
    s.go(to: 5); s.setMarked(true); s.setEliminated(["B"]); s.submitModule()
    check(s.phase == .finished, "finishes")
    let r = s.buildResult()
    check(r.modules.count == 4 && (200...800).contains(r.rwScore ?? 0) && r.mathScore == 200 && r.totalScore == (r.rwScore ?? 0) + 200, "result scores rw \(r.rwScore ?? -1) math \(r.mathScore ?? -1)")
    check(r.modules[0].correctCount == 27 && r.modules[1].correctCount == 0 && r.modules[3].items[5].marked, "result items")

    let quiz = TestSession.quiz(bank: big, questions: Array(big.questions.prefix(5)), timed: true)
    check(quiz.module.timeLimitSec == 5 * 71 && !quiz.isAdaptive, "quiz timing")
    quiz.submitModule(); check(quiz.phase == .finished && quiz.buildResult().rwScore == nil, "quiz finishes without a scaled score")
    let untimed = TestSession.quiz(bank: big, questions: Array(big.questions.prefix(3)), timed: false)
    for _ in 0..<5000 { untimed.tick() }
    check(untimed.phase == .question && untimed.module.usedSec == 5000, "untimed never expires")
}

// ---------- downloader against a fake server ----------
final class Fake: @unchecked Sendable {
    let lock = NSLock()
    var heal = false
    var detailCalls = 0
    func respond(_ req: URLRequest) -> (Data, Int) {
        let url = req.url?.absoluteString ?? ""
        let body = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
        func ok(_ s: String) -> (Data, Int) { (Data(s.utf8), 200) }
        if url.hasSuffix("/lookup") { return ok(#"{"lookupData":{},"readingLiveItems":["e-r1"],"mathLiveItems":[]}"#) }
        if url.hasSuffix("/get-questions") {
            return body.contains("\"test\":1")
                ? ok(#"[{"questionId":"r1","external_id":"e-r1","ibn":null,"primary_class_cd":"CAS","skill_desc":"Words in Context","difficulty":"E","score_band_range_cd":1},{"questionId":"r2","external_id":"e-r2","primary_class_cd":"INI","skill_desc":"Inferences","difficulty":"M","score_band_range_cd":4},{"questionId":"r2dup","external_id":"e-r2","primary_class_cd":"INI","skill_desc":"Inferences","difficulty":"M","score_band_range_cd":4},{"questionId":"r3","external_id":"e-r3","primary_class_cd":"SEC","skill_desc":"Boundaries","difficulty":"H","score_band_range_cd":6}]"#)
                : ok(#"[{"questionId":"m1","external_id":"e-m1","primary_class_cd":"H","skill_desc":"Linear functions","difficulty":"E","score_band_range_cd":2},{"questionId":"m2","external_id":"e-m2","primary_class_cd":"P","skill_desc":"Nonlinear functions","difficulty":"H","score_band_range_cd":7},{"questionId":"old1","external_id":"","ibn":"OLD-1","primary_class_cd":"S","skill_desc":"Circles","difficulty":"M","score_band_range_cd":4}]"#)
        }
        if url.hasSuffix("/get-question") {
            lock.lock(); detailCalls += 1; let healed = heal; lock.unlock()
            if body.contains("e-r3") && !healed { return (Data(), 500) }
            if body.contains("e-m2") { return ok(#"{"stem":"<p>v?</p>","type":"spr","rationale":"r","correct_answer":["12"]}"#) }
            return ok(#"{"stem":"<p>q</p>","stimulus":"<p>t</p>","type":"mcq","rationale":"r","answerOptions":[{"id":"1","content":"a"},{"id":"2","content":"b"},{"id":"3","content":"c"},{"id":"4","content":"d"}],"correct_answer":["A"],"keys":["1"]}"#)
        }
        if url.contains("/disclosed/OLD-1.json") {
            lock.lock(); detailCalls += 1; lock.unlock()
            return ok(#"[{"prompt":"<p>o</p>","answer":{"style":"Multiple Choice","choices":{"a":{"body":"1"},"b":{"body":"2"},"c":{"body":"3"},"d":{"body":"4"}},"correct_choice":"c","rationale":"x"}}]"#)
        }
        return (Data(), 404)
    }
}
do {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("margin-test-\(UUID().uuidString)")
    BankStore.dataDir = dir
    BankStore.retryBaseSeconds = 0.01
    BankStore.throttleBaseSeconds = 0.02
    let fake = Fake()
    let transport: BankStore.Transport = { req in fake.respond(req) }
    let first = try await BankStore.download(transport: transport)
    check(first.added == 5 && first.failed == 1, "first run: added \(first.added) failed \(first.failed)")
    let b1 = BankStore.load()
    check(b1.questions.count == 5 && b1.byId["m2"]?.isSpr == true && b1.byId["r1"]?.live == true && b1.byId["r2"]?.live == false && b1.byId["old1"]?.correct == ["C"], "load after download")
    fake.heal = true
    let calls = fake.detailCalls
    let second = try await BankStore.download(transport: transport)
    check(second.added == 1 && second.failed == 0 && fake.detailCalls - calls == 1, "resume fetches only what is missing")
    check(BankStore.load().questions.count == 6, "bank complete after resume")
    let h = try FileHandle(forWritingTo: BankStore.bankURL); try h.seekToEnd()
    try h.write(contentsOf: Data(#"{"test":1,"stub":{"questionId":"trunc"#.utf8)); try h.close()
    check(BankStore.load().questions.count == 6, "truncated last line is ignored")
    let hist = [SessionResult(title: "t", modules: [ModuleResult(items: [ResultItem(questionId: "r1", correct: false), ResultItem(questionId: "r2", correct: true)])])]
    try HistoryStore.save(hist)
    let back = HistoryStore.load()
    check(back.count == 1 && HistoryStore.missedIds(back) == ["r1"] && HistoryStore.seenIds(back).count == 2, "history round trip")
    try? FileManager.default.removeItem(at: dir)
} catch {
    check(false, "downloader threw: \(error)")
}

// ---------- downloader under load: concurrency, "slow down" answers, missing questions ----------
final class LoadFake: @unchecked Sendable {
    let lock = NSLock()
    let count: Int
    let throttleFirst: Int
    let goneId: String?
    var inFlight = 0, maxInFlight = 0, calls = 0, goneCalls = 0, throttled = 0

    init(count: Int, throttleFirst: Int = 0, goneId: String? = nil) {
        self.count = count; self.throttleFirst = throttleFirst; self.goneId = goneId
    }

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    func respond(_ req: URLRequest) async -> (Data, Int) {
        let url = req.url?.absoluteString ?? ""
        let body = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
        if url.hasSuffix("/lookup") { return (Data("{}".utf8), 200) }
        if url.hasSuffix("/get-questions") {
            if !body.contains("\"test\":1") { return (Data("[]".utf8), 200) }
            let items = (0..<count).map { #"{"questionId":"q\#($0)","external_id":"e-\#($0)","primary_class_cd":"CAS","skill_desc":"Words in Context","difficulty":"M","score_band_range_cd":4}"# }
            return (Data(("[" + items.joined(separator: ",") + "]").utf8), 200)
        }
        locked { inFlight += 1; maxInFlight = max(maxInFlight, inFlight) }
        try? await Task.sleep(nanoseconds: 25_000_000)
        return locked {
            inFlight -= 1
            if let goneId, body.contains("\"" + goneId + "\"") { goneCalls += 1; return (Data(), 404) }
            calls += 1
            if calls <= throttleFirst { throttled += 1; return (Data(), 429) }
            return (Data(#"{"stem":"<p>q</p>","type":"mcq","rationale":"r","answerOptions":[{"id":"1","content":"a"},{"id":"2","content":"b"},{"id":"3","content":"c"},{"id":"4","content":"d"}],"correct_answer":["A"]}"#.utf8), 200)
        }
    }
}
do {
    let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("margin-load-\(UUID().uuidString)")
    BankStore.dataDir = base
    let load = LoadFake(count: 120, throttleFirst: 15, goneId: "e-7")
    let sum = try await BankStore.download(parallel: 20, transport: { await load.respond($0) })
    check(sum.added == 119 && sum.failed == 1, "load: added \(sum.added) failed \(sum.failed)")
    check(load.maxInFlight > 6 && load.maxInFlight <= 20, "load: ran in parallel, peak \(load.maxInFlight)")
    check(load.goneCalls == 1, "a question that no longer exists is not retried, calls \(load.goneCalls)")
    check(load.throttled == 15, "every throttled request was retried, saw \(load.throttled)")
    check(BankStore.load().questions.count == 119, "load: bank has everything that exists")
    try? FileManager.default.removeItem(at: base)

    func timed(parallel: Int, suffix: String) async throws -> (ms: Int, peak: Int) {
        BankStore.dataDir = base.appendingPathExtension(suffix)
        let fake = LoadFake(count: 120)
        let start = Date()
        _ = try await BankStore.download(parallel: parallel, transport: { await fake.respond($0) })
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        try? FileManager.default.removeItem(at: BankStore.dataDir)
        return (ms, fake.maxInFlight)
    }
    let before = try await timed(parallel: 6, suffix: "b")
    let after = try await timed(parallel: 20, suffix: "c")
    print("  120 questions at 25 ms each: 6 at a time \(before.ms) ms, 20 at a time \(after.ms) ms")
    check(after.ms * 2 < before.ms && before.peak <= 6, "20 at a time is at least twice as fast as 6")
} catch {
    check(false, "load test threw: \(error)")
}

// ---------- updater ----------
do {
    check(Updater.parseVersion("v1.2.3") == [1, 2, 3] && Updater.parseVersion("1.4") == [1, 4, 0] && Updater.parseVersion("v2.0.1-beta") == [2, 0, 1]
          && Updater.parseVersion("latest") == nil && Updater.parseVersion(nil) == nil, "version parsing")
    check(Updater.isNewer([1, 0, 1], than: [1, 0, 0]) && Updater.isNewer([1, 10, 0], than: [1, 9, 9]) && !Updater.isNewer([1, 0, 0], than: [1, 0, 0]) && !Updater.isNewer([0, 9, 9], than: [1, 0, 0]), "version ordering")

    func site(_ body: String, status: Int = 200) -> BankStore.Transport {
        { req in
            guard req.url?.absoluteString.hasSuffix("/releases/latest") == true else { return (Data(), 404) }
            return (Data(body.utf8), status)
        }
    }
    let release = #"{"tag_name":"v1.1.0","draft":false,"prerelease":false,"html_url":"https://github.com/panch076/margin/releases/tag/v1.1.0","body":"What changed\n- faster\n","assets":[]}"#
    let found = await Updater.check(current: "1.0.0", transport: site(release))
    check(found?.version == "1.1.0" && found?.tag == "v1.1.0" && found?.notes.hasPrefix("What changed") == true
          && found?.pageURL.absoluteString == "https://github.com/panch076/margin/releases/tag/v1.1.0", "finds a newer release")
    let current = await Updater.check(current: "1.1.0", transport: site(release))
    let ahead = await Updater.check(current: "2.0", transport: site(release))
    check(current == nil && ahead == nil, "no update when already current or ahead")
    let none = await Updater.check(current: "1.0.0", transport: site("{}", status: 404))
    let garbage = await Updater.check(current: "1.0.0", transport: site("<html>"))
    let offline = await Updater.check(current: "1.0.0", transport: { _ in throw URLError(.notConnectedToInternet) })
    check(none == nil && garbage == nil && offline == nil, "no releases, garbage and offline are not errors")
    let draft = await Updater.check(current: "1.0.0", transport: site(release.replacingOccurrences(of: #""prerelease":false"#, with: #""prerelease":true"#)))
    check(draft == nil, "pre-releases are skipped")
    let odd = await Updater.check(current: "1.0.0", transport: site(release.replacingOccurrences(of: "https://github.com/panch076/margin/releases/tag/v1.1.0", with: "https://example.com/x")))
    check(odd?.pageURL == Updater.releasesPage, "a link pointing anywhere else falls back to the releases page")
    check(Updater.parseVersion(Updater.currentVersion) != nil, "this build's own version parses")
}

print("\(pass) passed, \(fail) failed")
exit(fail == 0 ? 0 : 1)
