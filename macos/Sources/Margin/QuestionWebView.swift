import SwiftUI
import WebKit
import MarginCore

/// What the question page is asked to draw. Field names match shared/question.html.
struct QuestionPayload: Encodable {
    struct Review: Encodable {
        var correct: [String]
        var isCorrect: Bool
        var rationale: String
    }

    var number: Int?
    var section = "rw"
    var type = "mcq"
    var stimulus = ""
    var stem = ""
    var choices: [String] = []
    var answer: String?
    var marked = false
    var eliminated: [String] = []
    var review: Review?
    var readOnly = false
    var hideBar = false
    var insetTop = 0
    var insetBottom = 0
    var message: String?

    static func message(_ text: String) -> QuestionPayload {
        var p = QuestionPayload()
        p.message = text
        return p
    }

    init() {}

    init(_ q: Question, number: Int? = nil, answer: String? = nil, marked: Bool = false, eliminated: [String] = [],
         review: Bool = false, readOnly: Bool = false, hideBar: Bool = false, insetTop: Int = 0, insetBottom: Int = 0) {
        self.number = number
        self.section = q.section == .math ? "math" : "rw"
        self.type = q.isSpr ? "spr" : "mcq"
        self.stimulus = q.stimulus
        self.stem = q.stem
        self.choices = q.choices
        self.answer = answer
        self.marked = marked
        self.eliminated = eliminated
        self.review = review ? Review(correct: q.correct, isCorrect: Grader.isCorrect(q, answer), rationale: q.rationale) : nil
        self.readOnly = readOnly
        self.hideBar = hideBar
        self.insetTop = insetTop
        self.insetBottom = insetBottom
    }
}

/// Shows one question. Question text contains math markup, tables and figures, so it is drawn by WebKit
/// from a page built into the app; nothing is loaded from the network.
///
/// The page is redrawn only when `key` changes. Answers are picked inside the page and reported back
/// through the callbacks, so a redraw (which would reset scrolling) is not needed for them.
struct QuestionWebView: NSViewRepresentable {
    var key: String
    var payload: QuestionPayload
    var onAnswer: ((String?) -> Void)? = nil
    var onMark: ((Bool) -> Void)? = nil
    var onEliminated: (([String]) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "margin")
        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsMagnification = true
        context.coordinator.web = web
        context.coordinator.parent = self
        web.loadHTMLString(QuestionPage.html, baseURL: nil)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.show(key: key, payload: payload)
    }

    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "margin")
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: QuestionWebView?
        weak var web: WKWebView?
        private var ready = false
        private var shownKey: String?
        private var pending: String?

        func show(key: String, payload: QuestionPayload) {
            guard key != shownKey else { return }
            guard let data = try? JSONEncoder().encode(payload), let json = String(data: data, encoding: .utf8) else { return }
            shownKey = key
            if ready { run(json) } else { pending = json }
        }

        private func run(_ json: String) {
            web?.evaluateJavaScript("window.Margin.render(" + json + ")", completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                ready = true
                if let json = pending {
                    pending = nil
                    run(json)
                }
            case "answer":
                parent?.onAnswer?(body["value"] as? String)
            case "mark":
                parent?.onMark?((body["value"] as? Bool) ?? false)
            case "eliminated":
                parent?.onEliminated?((body["value"] as? [String]) ?? [])
            default:
                break
            }
        }
    }
}

/// A plain web view for the online graphing calculator.
struct RemoteWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.load(URLRequest(url: url))
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {}
}
