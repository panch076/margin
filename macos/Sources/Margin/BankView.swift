import SwiftUI
import MarginCore

struct BankView: View {
    @Environment(AppModel.self) private var model

    @State private var subject: Subject? = nil
    @State private var domain: String? = nil
    @State private var skill: String? = nil
    @State private var difficulty: String? = nil
    @State private var status: String? = nil          // "new", "missed", "done"
    @State private var hideLive = false
    @State private var search = ""

    @State private var selected: Set<String> = []     // checked for the quiz
    @State private var focused: String? = nil         // highlighted row, shown in the preview
    @State private var showAnswer = false
    @State private var showPreview = true
    @State private var timed = false
    @State private var randomCount = 10

    var body: some View {
        let seen = model.seenIds
        let missed = model.missedIds
        let rows = filtered(seen: seen, missed: missed)

        table(rows: rows, seen: seen, missed: missed)
            .safeAreaInset(edge: .top, spacing: 0) { filterBar }
            .safeAreaInset(edge: .bottom, spacing: 0) { actionBar(rows: rows) }
            .inspector(isPresented: $showPreview) {
                preview.inspectorColumnWidth(min: 340, ideal: 480, max: 760)
            }
            .searchable(text: $search, prompt: "Question ID")
            .navigationTitle("Question Bank")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Preview", systemImage: "sidebar.trailing") { showPreview.toggle() }
                }
            }
            .onChange(of: subject) { _, _ in
                domain = nil
                skill = nil
            }
            .onChange(of: domain) { _, _ in
                skill = nil
            }
    }

    // MARK: table

    private func table(rows: [Question], seen: Set<String>, missed: Set<String>) -> some View {
        Table(rows, selection: $focused) {
            TableColumn("") { (q: Question) in
                Toggle("Include", isOn: checked(q.id))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
            .width(24)
            TableColumn("ID") { (q: Question) in
                Text(q.id).font(.system(.body, design: .monospaced))
            }
            .width(min: 70, ideal: 86, max: 120)
            TableColumn("Domain") { (q: Question) in
                Text(q.domainName)
            }
            TableColumn("Skill") { (q: Question) in
                Text(q.skill)
            }
            TableColumn("Difficulty") { (q: Question) in
                Text(q.difficultyName)
            }
            .width(min: 60, ideal: 76, max: 100)
            TableColumn("Status") { (q: Question) in
                Text(statusText(q, seen: seen, missed: missed)).foregroundStyle(.secondary)
            }
            .width(min: 56, ideal: 70, max: 100)
        }
    }

    private func checked(_ id: String) -> Binding<Bool> {
        Binding(get: { selected.contains(id) },
                set: { on in
                    if on { selected.insert(id) } else { selected.remove(id) }
                })
    }

    private func statusText(_ q: Question, seen: Set<String>, missed: Set<String>) -> String {
        if missed.contains(q.id) { return "Missed" }
        return seen.contains(q.id) ? "Correct" : "New"
    }

    private func filtered(seen: Set<String>, missed: Set<String>) -> [Question] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        let list = model.bank.questions.filter { q in
            if let subject, q.section != subject { return false }
            if let domain, q.domain != domain { return false }
            if let skill, q.skill != skill { return false }
            if let difficulty, q.difficulty != difficulty { return false }
            if hideLive && q.live { return false }
            if !needle.isEmpty && !q.id.lowercased().contains(needle) { return false }
            switch status {
            case "new": return !seen.contains(q.id)
            case "missed": return missed.contains(q.id)
            case "done": return seen.contains(q.id) && !missed.contains(q.id)
            default: return true
            }
        }
        return list.sorted(by: AppModel.bankOrder)
    }

    // MARK: filters

    private var domainChoices: [DomainInfo] {
        Catalog.domains.filter { subject == nil || $0.section == subject }
    }

    private var skillChoices: [String] {
        guard let domain else { return [] }
        return Array(Set(model.bank.questions.filter { $0.domain == domain }.map { $0.skill })).filter { !$0.isEmpty }.sorted()
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Group {
                Picker("Section", selection: $subject) {
                    Text("All sections").tag(Subject?.none)
                    Text("Reading and Writing").tag(Subject?.some(.rw))
                    Text("Math").tag(Subject?.some(.math))
                }
                Picker("Domain", selection: $domain) {
                    Text("All domains").tag(String?.none)
                    ForEach(domainChoices) { d in
                        Text(d.name).tag(String?.some(d.code))
                    }
                }
                Picker("Skill", selection: $skill) {
                    Text("All skills").tag(String?.none)
                    ForEach(skillChoices, id: \.self) { s in
                        Text(s).tag(String?.some(s))
                    }
                }
                .disabled(domain == nil)
                Picker("Difficulty", selection: $difficulty) {
                    Text("Any difficulty").tag(String?.none)
                    Text("Easy").tag(String?.some("E"))
                    Text("Medium").tag(String?.some("M"))
                    Text("Hard").tag(String?.some("H"))
                }
                Picker("Status", selection: $status) {
                    Text("Any status").tag(String?.none)
                    Text("Not seen yet").tag(String?.some("new"))
                    Text("Missed").tag(String?.some("missed"))
                    Text("Answered correctly").tag(String?.some("done"))
                }
            }
            .labelsHidden()
            Toggle("Hide practice-test questions", isOn: $hideLive)
                .toggleStyle(.checkbox)
                .help("Hide questions that also appear on official full-length practice tests")
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: actions

    private func actionBar(rows: [Question]) -> some View {
        HStack(spacing: 12) {
            Text("\(selected.count.formatted()) selected · \(rows.count.formatted()) shown")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button("Select All Shown") { rows.forEach { selected.insert($0.id) } }
            Button("Clear") { selected.removeAll() }
                .disabled(selected.isEmpty)
            Divider().frame(height: 18)
            Stepper("Add \(randomCount) random", value: $randomCount, in: 1...100)
            Button("Add") {
                let pool = rows.filter { !selected.contains($0.id) }.shuffled()
                pool.prefix(randomCount).forEach { selected.insert($0.id) }
            }
            Spacer()
            Toggle("Timed at test pace", isOn: $timed)
                .toggleStyle(.checkbox)
            Button("Start Quiz") { startQuiz() }
                .buttonStyle(.glassProminent)
                .disabled(selected.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .padding(.top, 6)
    }

    private func startQuiz() {
        let picked = selected.compactMap { model.bank.byId[$0] }.sorted(by: AppModel.bankOrder)
        guard !picked.isEmpty else { return }
        model.start(TestSession.quiz(bank: model.bank, questions: picked, timed: timed))
    }

    // MARK: preview

    private func caption(_ q: Question) -> String {
        var text = "\(q.id) · \(q.domainName) · \(q.difficultyName)"
        if q.live { text += " · on a practice test" }
        return text
    }

    @ViewBuilder
    private var preview: some View {
        if let id = focused, let q = model.bank.byId[id] {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(q.skill).font(.headline).lineLimit(1)
                        Text(caption(q))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Toggle("Show answer", isOn: $showAnswer)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                Divider()
                QuestionWebView(key: "\(q.id)|\(showAnswer)",
                                payload: QuestionPayload(q, review: showAnswer, readOnly: true, hideBar: !showAnswer))
            }
        } else {
            if model.bank.isEmpty {
                ContentUnavailableView("No questions yet", systemImage: "tray",
                                       description: Text("Download the question bank from Home."))
            } else {
                ContentUnavailableView("Select a question", systemImage: "text.viewfinder",
                                       description: Text("Its text appears here."))
            }
        }
    }
}
