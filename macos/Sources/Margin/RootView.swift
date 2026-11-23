import SwiftUI
import MarginCore

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        content
            .task { await model.loadAll() }
            .alert("Margin", isPresented: alertShown) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.alertMessage ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.overlay {
        case .none:
            ShellView()
        case .session(let sm):
            SessionView(sm: sm).id(sm.id)
        case .results(let result):
            ResultsView(result: result).id(result.id)
        }
    }

    private var alertShown: Binding<Bool> {
        Binding(get: { model.alertMessage != nil }, set: { shown in if !shown { model.alertMessage = nil } })
    }
}

struct ShellView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.page) {
                ForEach(SidebarPage.allCases) { page in
                    Label(page.title, systemImage: page.symbol).tag(page)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 280)
            .safeAreaInset(edge: .bottom) {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        } detail: {
            switch model.page ?? .home {
            case .home: HomeView()
            case .bank: BankView()
            case .test: TestSetupView()
            case .history: HistoryView()
            }
        }
    }

    private var footnote: String {
        if model.loading { return "Loading question bank…" }
        if model.bank.isEmpty { return "No questions downloaded yet" }
        return "\(model.bank.questions.count.formatted()) questions stored on this Mac"
    }
}
