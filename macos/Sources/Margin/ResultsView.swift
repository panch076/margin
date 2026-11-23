import SwiftUI
import MarginCore

struct ResultsView: View {
    @Environment(AppModel.self) private var model
    let result: SessionResult

    @State private var selection: String?
    @State private var onlyMissed = false

    struct Entry: Identifiable {
        let id: String
        let item: ResultItem
        let question: Question?
        let number: Int
        let moduleIndex: Int
    }

    private var entries: [Entry] {
        var list: [Entry] = []
        for (mi, m) in result.modules.enumerated() {
            for (qi, item) in m.items.enumerated() {
                list.append(Entry(id: "\(mi)-\(qi)", item: item, question: model.bank.byId[item.questionId], number: qi + 1, moduleIndex: mi))
            }
        }
        return list
    }

    var body: some View {
        let all = entries
        HSplitView {
            summaryList(all)
                .frame(minWidth: 340, idealWidth: 430, maxWidth: 580, maxHeight: .infinity)
            detail(all)
                .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(result.title)
        .navigationSubtitle(result.date.formatted(date: .abbreviated, time: .shortened))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle("Missed Only", systemImage: "line.3.horizontal.decrease.circle", isOn: $onlyMissed)
                    .help("Show only missed questions")
                Button("Retry Missed", systemImage: "arrow.uturn.backward.circle") {
                    let missed = all.filter { !$0.item.correct }.compactMap { $0.question }
                    var seen = Set<String>()
                    model.startMissedQuiz(from: missed.filter { seen.insert($0.id).inserted })
                }
                .disabled(!all.contains { !$0.item.correct && $0.question != nil })
                Button("Done") { model.closeOverlay() }
                    .buttonStyle(.glassProminent)
            }
        }
    }

    // MARK: left column

    private func summaryList(_ all: [Entry]) -> some View {
        List(selection: $selection) {
            SwiftUI.Section {
                HStack(spacing: 10) {
                    ForEach(tiles, id: \.label) { tile in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tile.value).font(.system(size: 26, weight: .semibold)).monospacedDigit()
                            Text(tile.label).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                if result.rwScore != nil || result.mathScore != nil {
                    Text("Scores are rough estimates on the 200–800 scale, not official results.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(result.modules.enumerated()), id: \.offset) { _, m in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(m.title): \(m.correctCount) of \(m.items.count) correct").fontWeight(.semibold)
                        Text(moduleDetail(m)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            SwiftUI.Section("By domain") {
                ForEach(domainRows(all), id: \.name) { row in
                    HStack {
                        Text(row.name).lineLimit(1)
                        Spacer()
                        ProgressView(value: Double(row.correct), total: Double(max(1, row.total)))
                            .frame(width: 110)
                        Text("\(row.correct)/\(row.total)").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            }
            ForEach(Array(result.modules.enumerated()), id: \.offset) { mi, m in
                SwiftUI.Section(result.modules.count > 1 ? m.title : "Questions") {
                    ForEach(all.filter { $0.moduleIndex == mi && (!onlyMissed || !$0.item.correct) }) { e in
                        EntryRow(entry: e).tag(e.id)
                    }
                }
            }
        }
    }

    private var tiles: [(value: String, label: String)] {
        let total = result.questionCount
        let fraction = "\(result.correctCount)/\(total)"
        if let t = result.totalScore, let rw = result.rwScore, let math = result.mathScore {
            return [("\(t)", "Total"), ("\(rw)", "Reading & Writing"), ("\(math)", "Math")]
        }
        if let rw = result.rwScore { return [("\(rw)", "Reading & Writing"), (fraction, "Correct")] }
        if let math = result.mathScore { return [("\(math)", "Math"), (fraction, "Correct")] }
        let pct = total == 0 ? "–" : "\(Int((100.0 * Double(result.correctCount) / Double(total)).rounded()))%"
        return [(fraction, "Correct"), (pct, "Accuracy")]
    }

    private func moduleDetail(_ m: ModuleResult) -> String {
        var text: String
        if let limit = m.timeLimitSec {
            text = "\(clockText(m.usedSec)) of \(clockText(limit)) used"
        } else {
            text = "\(clockText(m.usedSec)) spent"
        }
        if m.route == "higher" { text += " · higher-difficulty module" }
        if m.route == "lower" { text += " · lower-difficulty module" }
        return text
    }

    private func domainRows(_ all: [Entry]) -> [(name: String, correct: Int, total: Int)] {
        var totals: [String: (correct: Int, total: Int)] = [:]
        for e in all {
            guard let q = e.question else { continue }
            var t = totals[q.domain] ?? (0, 0)
            t.total += 1
            if e.item.correct { t.correct += 1 }
            totals[q.domain] = t
        }
        return totals.keys.sorted { Catalog.domainOrder($0) < Catalog.domainOrder($1) }.map { code in
            (name: Catalog.domainName(code), correct: totals[code]?.correct ?? 0, total: totals[code]?.total ?? 0)
        }
    }

    // MARK: right column

    @ViewBuilder
    private func detail(_ all: [Entry]) -> some View {
        if let id = selection, let e = all.first(where: { $0.id == id }) {
            if let q = e.question {
                QuestionWebView(key: e.id, payload: QuestionPayload(q, number: e.number, answer: e.item.answer, review: true))
            } else {
                ContentUnavailableView("Question unavailable", systemImage: "questionmark.circle",
                                       description: Text("This question is no longer in the local bank."))
            }
        } else {
            ContentUnavailableView("Select a question", systemImage: "text.viewfinder",
                                   description: Text("See your answer, the correct answer and the explanation."))
        }
    }
}

struct EntryRow: View {
    let entry: ResultsView.Entry

    var body: some View {
        let blank = (entry.item.answer ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        HStack(spacing: 10) {
            Image(systemName: entry.item.correct ? "checkmark.circle.fill" : (blank ? "minus.circle" : "xmark.circle.fill"))
                .foregroundStyle(entry.item.correct ? Color.green : (blank ? Color.secondary : Color.red))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.number).  \(entry.question?.skill ?? "Question no longer in the bank")").lineLimit(1)
                Text(detail(blank: blank)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func detail(blank: Bool) -> String {
        guard let q = entry.question else { return "" }
        var parts = [q.difficultyName, blank ? "unanswered" : "you answered \(entry.item.answer ?? "")"]
        if !entry.item.correct { parts.append("correct: " + q.correct.prefix(2).joined(separator: " or ")) }
        parts.append(clockText(entry.item.seconds))
        return parts.joined(separator: " · ")
    }
}
