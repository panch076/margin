import SwiftUI
import MarginCore

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Margin").font(.system(size: 34, weight: .bold))
                    Text("Practice with official SAT questions stored on this Mac: build your own quizzes or sit a timed, adaptive practice test.")
                        .foregroundStyle(.secondary)
                }
                if let update = model.update {
                    updateCard(update)
                }
                bankCard
                HStack(alignment: .top, spacing: 18) {
                    actionCard(title: "Build a quiz", symbol: "checklist",
                               text: "Filter by section, domain, skill and difficulty, pick the questions you want, and take them in the test interface.",
                               button: "Open Question Bank") { model.page = .bank }
                    actionCard(title: "Adaptive practice test", symbol: "timer",
                               text: "Two timed modules per section. The second module gets harder or easier depending on how the first one went.",
                               button: "Set Up a Test") { model.page = .test }
                    actionCard(title: "Fix mistakes", symbol: "arrow.uturn.backward.circle",
                               text: missedText, button: "Retry Missed Questions", disabled: missedCount == 0) { model.startMissedQuiz() }
                }
                VStack(alignment: .leading, spacing: 6) {
                    CardTitle("Your progress")
                    Text(statsText).foregroundStyle(.secondary)
                }
                .glassCard()
                HStack(spacing: 12) {
                    Text("Version \(Updater.currentVersion)")
                    Button("Check for Updates") {
                        Task { await model.checkForUpdate(manual: true) }
                    }
                    .controlSize(.small)
                    .disabled(model.checkingForUpdate)
                    if let status = model.updateStatus {
                        Text(status)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text("Questions are College Board's and are copied from its public question bank for your personal study. Margin is not affiliated with or endorsed by College Board. SAT is a trademark of College Board.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Backdrop())
        .navigationTitle("Home")
    }

    private func updateCard(_ update: UpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("Margin \(update.version) is available")
            Text(updateNotes(update))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("View Release") { openURL(update.pageURL) }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
        .glassCard()
    }

    private func updateNotes(_ update: UpdateInfo) -> String {
        var notes = update.notes.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        if notes.count > 320 { notes = String(notes.prefix(320)).trimmingCharacters(in: .whitespacesAndNewlines) + "…" }
        let howTo = "You have version \(Updater.currentVersion). Download the new disk image from the release page and replace Margin in Applications."
        return notes.isEmpty ? howTo : notes + "\n\n" + howTo
    }

    private var bankCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle("Question bank")
            Text(bankSummary).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(model.bank.isEmpty ? "Download Question Bank" : "Check for New Questions") { model.startDownload() }
                    .buttonStyle(.glassProminent)
                    .disabled(model.downloading || model.loading)
                if model.downloading {
                    Button("Stop") { model.cancelDownload() }
                        .buttonStyle(.glass)
                }
            }
            .controlSize(.large)
            if model.downloading {
                if let p = model.progress, p.total > 0 {
                    ProgressView(value: Double(p.done), total: Double(p.total))
                    Text(progressLine(p))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                    Text("Reading the question list…").font(.caption).foregroundStyle(.secondary)
                }
            } else if let message = model.downloadMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }

    private func actionCard(title: String, symbol: String, text: String, button: String, disabled: Bool = false,
                            action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.tint)
            CardTitle(title)
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(button, action: action)
                .buttonStyle(.glass)
                .disabled(disabled)
        }
        .frame(minHeight: 190, alignment: .topLeading)
        .glassCard()
    }

    private func progressLine(_ p: DownloadProgress) -> String {
        var line = "\(p.stage): \(p.done.formatted()) of \(p.total.formatted())"
        if p.failed > 0 { line += " (\(p.failed.formatted()) to retry)" }
        return line
    }

    private var bankSummary: String {
        let bank = model.bank
        if model.loading { return "Loading…" }
        if bank.isEmpty {
            return "Nothing is stored yet. Download the question bank once (about 3,800 questions, a few minutes) and everything afterwards works offline."
        }
        let live = bank.questions.filter { $0.live }.count
        var text = "\(bank.questions.count.formatted()) questions on this Mac: \(bank.count(.rw).formatted()) Reading and Writing, \(bank.count(.math).formatted()) Math. "
        text += "\(live.formatted()) of them also appear on official full-length practice tests."
        if bank.unusable > 0 { text += " \(bank.unusable.formatted()) could not be read and are left out." }
        if let updated = bank.updated { text += " Last updated \(updated.formatted(date: .abbreviated, time: .omitted))." }
        return text
    }

    private var missedCount: Int {
        model.missedIds.filter { model.bank.byId[$0] != nil }.count
    }

    private var missedText: String {
        missedCount == 0
            ? "Questions you get wrong are collected here so you can try them again."
            : "\(missedCount.formatted()) questions were wrong or blank on your last attempt. Retry up to 20 of them as a quiz."
    }

    private var statsText: String {
        let items = model.history.flatMap { $0.modules }.flatMap { $0.items }
        if items.isEmpty { return "Nothing yet. Results from quizzes and tests appear here and under History." }
        let correct = items.filter { $0.correct }.count
        let tests = model.history.filter { $0.kind != "quiz" }.count
        let best = model.history.compactMap { $0.totalScore }.max()
        var text = "\(items.count.formatted()) questions answered across \(model.history.count.formatted()) sessions, \(Int((100.0 * Double(correct) / Double(items.count)).rounded()))% correct. "
        text += "\(tests) practice test\(tests == 1 ? "" : "s") taken"
        if let best { text += ", best estimated total \(best)." } else { text += "." }
        return text
    }
}

struct TestSetupView: View {
    @Environment(AppModel.self) private var model
    @State private var kind = "full"
    @State private var excludeLive = true
    @State private var preferUnseen = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Practice Test").font(.system(size: 34, weight: .bold))
                    Text("Each section has two timed modules. Your score on the first decides whether the second is the higher or lower difficulty version, the same way the real test adapts.")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    CardTitle("What to take")
                    Picker("What to take", selection: $kind) {
                        Text("Full-length test: Reading and Writing, a 10-minute break, then Math. About 2 hours 24 minutes.").tag("full")
                        Text("Reading and Writing only: two modules, 54 questions, 64 minutes.").tag("rw")
                        Text("Math only: two modules, 44 questions, 70 minutes, with calculator and reference sheet.").tag("math")
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
                .glassCard()
                VStack(alignment: .leading, spacing: 10) {
                    CardTitle("Question selection")
                    Toggle("Leave out questions used on official full-length practice tests", isOn: $excludeLive)
                    Toggle("Prefer questions I have not seen yet", isOn: $preferUnseen)
                    Text(poolText).font(.caption).foregroundStyle(.secondary)
                }
                .glassCard()
                Button("Start Test") {
                    let options = AssemblyOptions(excludeLive: excludeLive, preferUnseen: preferUnseen, seen: model.seenIds)
                    model.start(TestSession.adaptive(bank: model.bank, kind: kind, options: options))
                }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                .disabled(model.bank.isEmpty)
                Text("Scores are estimates. The real test is scored with calibrated statistics that are not published, so treat the number as a ballpark and the question-by-question review as the useful part.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Backdrop())
        .navigationTitle("Practice Test")
    }

    private var poolText: String {
        if model.bank.isEmpty { return "Download the question bank from Home before starting a test." }
        let usable = model.bank.questions.filter { !excludeLive || !$0.live }
        let rw = usable.filter { $0.section == .rw }.count
        return "Drawing from \(rw.formatted()) Reading and Writing and \((usable.count - rw).formatted()) Math questions."
    }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: String?

    var body: some View {
        let sessions = model.history.sorted { $0.date > $1.date }
        Group {
            if sessions.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Finished quizzes and tests are saved here."))
            } else {
                List(selection: $selection) {
                    ForEach(sessions) { r in
                        HistoryRow(result: r).tag(r.id)
                    }
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    Button("Review") { open(ids.first) }
                    Button("Delete", role: .destructive) { ids.forEach { model.deleteResult(id: $0) } }
                } primaryAction: { ids in
                    open(ids.first)
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Delete", systemImage: "trash") {
                    if let id = selection { model.deleteResult(id: id); selection = nil }
                }
                .disabled(selection == nil)
                Button("Review", systemImage: "doc.text.magnifyingglass") { open(selection) }
                    .disabled(selection == nil)
            }
        }
    }

    private func open(_ id: String?) {
        if let id, let r = model.history.first(where: { $0.id == id }) { model.showResults(r) }
    }
}

struct HistoryRow: View {
    let result: SessionResult

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(result.title).font(.headline)
                Text(result.date.formatted(date: .complete, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(result.correctCount) / \(result.questionCount) correct").fontWeight(.semibold)
                if let score = scoreText {
                    Text(score).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 5)
    }

    private var scoreText: String? {
        if let total = result.totalScore, let rw = result.rwScore, let math = result.mathScore {
            return "Estimated \(total)  (R&W \(rw) · Math \(math))"
        }
        if let rw = result.rwScore { return "Estimated R&W \(rw)" }
        if let math = result.mathScore { return "Estimated Math \(math)" }
        return nil
    }
}
