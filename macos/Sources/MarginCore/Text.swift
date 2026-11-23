import Foundation

enum Rx {
    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: options)
    }

    /// Capture groups of the first match (index 0 is the whole match), or nil.
    static func first(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String]? {
        guard let rx = regex(pattern, options) else { return nil }
        let ns = text as NSString
        guard let m = rx.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    static func firstRange(_ pattern: String, in text: String) -> NSRange? {
        guard let rx = regex(pattern, []) else { return nil }
        let ns = text as NSString
        return rx.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length))?.range
    }

    static func all(_ pattern: String, in text: String) -> [String] {
        guard let rx = regex(pattern, []) else { return [] }
        let ns = text as NSString
        return rx.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    static func replace(_ pattern: String, in text: String, with template: String, options: NSRegularExpression.Options = []) -> String {
        guard let rx = regex(pattern, options) else { return text }
        let ns = text as NSString
        return rx.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: template)
    }

    static func matches(_ pattern: String, _ text: String) -> Bool { first(pattern, in: text) != nil }
}

enum HTMLText {
    static func stripTags(_ html: String?) -> String {
        guard let html, !html.isEmpty else { return "" }
        var s = Rx.replace("<[^>]+>", in: html, with: " ")
        for (entity, plain) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&minus;", "-")] {
            s = s.replacingOccurrences(of: entity, with: plain)
        }
        s = s.replacingOccurrences(of: "\u{00a0}", with: " ").replacingOccurrences(of: "\u{2212}", with: "-")
        return Rx.replace("\\s+", in: s, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func dropScripts(_ html: String?) -> String {
        guard let html, !html.isEmpty else { return "" }
        return Rx.replace("<script\\b[^>]*>.*?</script\\s*>", in: html, with: "", options: [.caseInsensitive, .dotMatchesLineSeparators])
    }
}
