import SwiftUI
import MarginCore

enum SidebarPage: String, CaseIterable, Identifiable, Hashable {
    case home, bank, test, history

    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .bank: return "Question Bank"
        case .test: return "Practice Test"
        case .history: return "History"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house"
        case .bank: return "books.vertical"
        case .test: return "timer"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

/// A running quiz or test. `revision` changes after every action so views redraw.
@Observable
final class SessionModel: Identifiable {
    let session: TestSession
    var revision = 0

    init(_ session: TestSession) { self.session = session }

    func act(_ change: (TestSession) -> Void) {
        change(session)
        revision += 1
    }
}

enum OverlayRoute {
    case none
    case session(SessionModel)
    case results(SessionResult)
}

@MainActor
@Observable
final class AppModel {
    var bank = Bank()
    var history: [SessionResult] = []
    var page: SidebarPage? = .home
    var overlay: OverlayRoute = .none
    var loading = true
    var alertMessage: String?

    var downloading = false
    var progress: DownloadProgress?
    var downloadMessage: String?
    private var downloadTask: Task<Void, Never>?

    var seenIds: Set<String> { HistoryStore.seenIds(history) }
    var missedIds: Set<String> { HistoryStore.missedIds(history) }

    func loadAll() async {
        history = HistoryStore.load()
        await reloadBank()
    }

    func reloadBank() async {
        loading = true
        let loaded = await Task.detached(priority: .userInitiated) { BankStore.load() }.value
        bank = loaded
        loading = false
    }

    // MARK: download

    func startDownload() {
        guard !downloading else { return }
        downloading = true
        downloadMessage = nil
        progress = nil
        downloadTask = Task {
            var message: String
            do {
                let summary = try await BankStore.download(progress: { [weak self] p in
                    Task { @MainActor in self?.report(p) }
                })
                if summary.added == 0 && summary.failed == 0 {
                    message = "Already up to date."
                } else {
                    message = "Added \(summary.added.formatted()) questions."
                    if summary.failed > 0 {
                        message += " \(summary.failed.formatted()) could not be fetched; run the download again to retry them."
                    }
                }
            } catch is CancellationError {
                message = "Stopped. What was downloaded so far is kept; start again to continue."
            } catch {
                message = "The download did not finish: \(error.localizedDescription) What was downloaded so far is kept."
            }
            await self.reloadBank()
            self.downloading = false
            self.progress = nil
            self.downloadMessage = message
        }
    }

    private func report(_ p: DownloadProgress) {
        guard downloading else { return }
        if let current = progress, current.total == p.total, p.done < current.done { return }   // updates can arrive out of order
        progress = p
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    // MARK: sessions

    func start(_ session: TestSession) {
        if session.phase == .finished || session.module.questions.isEmpty {
            alertMessage = "There are not enough questions for that yet. Download the question bank from Home first."
            return
        }
        overlay = .session(SessionModel(session))
    }

    /// Ends the running session. Pass nil to leave without saving.
    func finish(_ result: SessionResult?) {
        guard let result else { overlay = .none; return }
        history.append(result)
        do { try HistoryStore.save(history) } catch { alertMessage = "This result could not be saved: \(error.localizedDescription)" }
        overlay = .results(result)
    }

    func showResults(_ result: SessionResult) { overlay = .results(result) }
    func closeOverlay() { overlay = .none }

    func deleteResult(id: String) {
        history.removeAll { $0.id == id }
        try? HistoryStore.save(history)
    }

    func startMissedQuiz(from questions: [Question]? = nil) {
        var pool = questions ?? missedIds.compactMap { bank.byId[$0] }
        pool.shuffle()
        let pick = Array(pool.prefix(questions == nil ? 20 : pool.count)).sorted(by: Self.bankOrder)
        guard !pick.isEmpty else { return }
        start(TestSession.quiz(bank: bank, questions: pick, timed: false, title: "Missed Questions"))
    }

    nonisolated static func bankOrder(_ a: Question, _ b: Question) -> Bool {
        (a.section.order, Catalog.domainOrder(a.domain), a.skill, a.band, a.id) < (b.section.order, Catalog.domainOrder(b.domain), b.skill, b.band, b.id)
    }
}

func clockText(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
}
