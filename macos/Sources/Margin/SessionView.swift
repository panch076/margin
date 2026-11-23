import SwiftUI
import Combine
import MarginCore

/// The test-taking screen: question in the middle, with the module name, clock and tools floating
/// on glass above it and the navigator and paging buttons floating below.
struct SessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    let sm: SessionModel

    @State private var clockHidden = false
    @State private var showNavigator = false
    @State private var confirmSubmit = false
    @State private var confirmExit = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let topInset = 84
    private let bottomInset = 88

    var body: some View {
        let _ = sm.revision
        let session = sm.session

        ZStack {
            Color(nsColor: .textBackgroundColor).ignoresSafeArea()
            switch session.phase {
            case .question:
                questionBody(session)
            case .review:
                reviewBody(session)
            case .onBreak:
                breakBody(session)
            case .finished:
                ProgressView()
            }
        }
        .overlay(alignment: .top) {
            if session.phase != .finished { topBar(session) }
        }
        .overlay(alignment: .bottom) {
            if session.phase == .question || session.phase == .review { bottomBar(session) }
        }
        .navigationTitle(session.phase == .onBreak ? "Break" : session.module.title)
        .onReceive(ticker) { _ in
            sm.act { $0.tick() }
            finishIfDone()
        }
        .confirmationDialog(submitTitle(session), isPresented: $confirmSubmit) {
            Button(session.isLastModule ? "Finish" : "Submit Module") {
                sm.act { $0.submitModule() }
                finishIfDone()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(submitMessage(session))
        }
        .confirmationDialog("End this session?", isPresented: $confirmExit) {
            Button("End and Score") { leave(save: true) }
            Button("Leave Without Saving", role: .destructive) { leave(save: false) }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("Ending now scores what you have answered so far and saves it to History.")
        }
    }

    // MARK: flow

    private func finishIfDone() {
        guard sm.session.phase == .finished else { return }
        dismissWindow(id: "calculator")
        model.finish(sm.session.buildResult())
    }

    private func leave(save: Bool) {
        dismissWindow(id: "calculator")
        model.finish(save ? sm.session.buildResult() : nil)
    }

    private func submitTitle(_ s: TestSession) -> String {
        s.isLastModule ? "Finish and see your results?" : "Submit this module?"
    }

    private func submitMessage(_ s: TestSession) -> String {
        let m = s.module
        let blank = m.questions.count - m.answeredCount
        var text: String = blank > 0 ? "\(blank) question\(blank == 1 ? " is" : "s are") unanswered. " : ""
        if !s.isLastModule { text += "You will not be able to return to this module." }
        return text
    }

    // MARK: question

    private func questionBody(_ s: TestSession) -> some View {
        let m = s.module
        let q = s.current
        let payload = QuestionPayload(q, number: s.questionIndex + 1, answer: m.answers[q.id], marked: m.marked.contains(q.id),
                                      eliminated: m.eliminated[q.id] ?? [], insetTop: topInset, insetBottom: bottomInset)
        return QuestionWebView(
            key: "\(s.modules.count)|\(s.questionIndex)|\(q.id)",
            payload: payload,
            onAnswer: { value in sm.act { $0.setAnswer(value) } },
            onMark: { on in sm.act { $0.setMarked(on) } },
            onEliminated: { letters in sm.act { $0.setEliminated(letters) } }
        )
    }

    // MARK: review page

    private func reviewBody(_ s: TestSession) -> some View {
        let m = s.module
        let blank = m.questions.count - m.answeredCount
        var hint: String = blank == 0 ? "Every question has an answer. " : "\(blank) question\(blank == 1 ? " is" : "s are") unanswered. "
        hint += "Select any number to go back to it"
        hint += m.timeLimitSec != nil ? " while time remains." : "."
        return ScrollView {
            VStack(spacing: 14) {
                Text("Check Your Work").font(.system(size: 30, weight: .bold))
                Text(hint)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(m.title).font(.headline)
                        Spacer()
                        NumberLegend()
                    }
                    numberGrid(s, current: nil)
                }
                .padding(22)
                .frame(maxWidth: 720)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, CGFloat(topInset) + 28)
            .padding(.bottom, CGFloat(bottomInset) + 24)
            .padding(.horizontal, 32)
        }
    }

    private func numberGrid(_ s: TestSession, current: Int?) -> some View {
        let m = s.module
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 48), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(Array(m.questions.enumerated()), id: \.element.id) { index, q in
                NumberCell(number: index + 1, answered: m.isAnswered(q), marked: m.marked.contains(q.id), current: index == current) {
                    showNavigator = false
                    sm.act { $0.go(to: index) }
                }
            }
        }
    }

    // MARK: break

    private func breakBody(_ s: TestSession) -> some View {
        VStack(spacing: 14) {
            Text("Break").font(.system(size: 34, weight: .bold))
            Text("Reading and Writing is finished. Math starts when the break ends, or as soon as you choose to continue.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Text(clockText(s.breakRemaining))
                .font(.system(size: 64, weight: .semibold))
                .monospacedDigit()
                .padding(.vertical, 6)
            Button("Resume Testing") { sm.act { $0.endBreak() } }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Backdrop())
    }

    // MARK: glass bars

    private func topBar(_ s: TestSession) -> some View {
        let m = s.module
        let onBreak = s.phase == .onBreak
        let isMath = !onBreak && (s.phase == .review ? m.section == .math : s.current.section == .math)
        let timed = m.timeLimitSec != nil
        let low = timed && m.remainingSec <= 300
        return GlassEffectContainer(spacing: 18) {
            ZStack {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(onBreak ? "Break" : m.title).font(.headline).lineLimit(1)
                        Text(s.isAdaptive ? s.title : (timed ? "Timed quiz" : "Untimed quiz"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                    Spacer()
                    HStack(spacing: 8) {
                        if isMath {
                            Button("Calculator", systemImage: "function") { openWindow(id: "calculator") }
                            Button("Reference", systemImage: "x.squareroot") { openWindow(id: "reference") }
                        }
                        Button("Exit", systemImage: "xmark") { confirmExit = true }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
                if !onBreak {
                    Button {
                        clockHidden.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: clockHidden ? "eye.slash" : (timed ? "timer" : "stopwatch"))
                            Text(clockHidden ? "Show" : clockText(timed ? m.remainingSec : m.usedSec))
                                .font(.system(size: 19, weight: .semibold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(low && !clockHidden ? Color.red : Color.primary)
                        .padding(.horizontal, 6)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .help(clockHidden ? "Show the clock" : "Hide the clock")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private func bottomBar(_ s: TestSession) -> some View {
        let m = s.module
        let onReview = s.phase == .review
        return GlassEffectContainer(spacing: 18) {
            ZStack {
                HStack(spacing: 10) {
                    Text("\(m.answeredCount) of \(m.questions.count) answered")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect()
                    Spacer()
                    Button("Back") { sm.act { $0.back() } }
                        .buttonStyle(.glass)
                        .disabled(!onReview && s.questionIndex == 0)
                    if onReview {
                        Button(s.isLastModule ? (s.isAdaptive ? "Finish Test" : "Finish Quiz") : "Submit Module") { confirmSubmit = true }
                            .buttonStyle(.glassProminent)
                    } else {
                        Button("Next") { sm.act { $0.next() } }
                            .buttonStyle(.glassProminent)
                    }
                }
                if !onReview {
                    Button {
                        showNavigator.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Text("Question \(s.questionIndex + 1) of \(m.questions.count)").fontWeight(.semibold).monospacedDigit()
                            Image(systemName: "chevron.up").font(.caption.weight(.bold))
                        }
                        .padding(.horizontal, 6)
                    }
                    .buttonStyle(.glass)
                    .popover(isPresented: $showNavigator, arrowEdge: .top) {
                        VStack(spacing: 14) {
                            Text(m.title).font(.headline)
                            NumberLegend()
                            numberGrid(s, current: s.questionIndex)
                                .frame(width: 430)
                            Button("Go to Review Page") {
                                showNavigator = false
                                sm.act { $0.openReview() }
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .controlSize(.extraLarge)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }
}
