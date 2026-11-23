import Foundation

public enum Grader {
    public static func parseNumber(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let s = raw.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{2212}", with: "-")
        guard !s.isEmpty else { return nil }
        if let f = Rx.first("^(-?\\d+)/(\\d+)$", in: s), let num = Double(f[1]), let den = Double(f[2]) {
            return den == 0 ? nil : num / den
        }
        if Rx.matches("^-?(\\d+|\\d*\\.\\d+|\\d+\\.)$", s) { return Double(s) ?? Double(s + "0") }
        return nil
    }

    public static func isCorrect(_ q: Question, _ answer: String?) -> Bool {
        guard let answer, !q.correct.isEmpty else { return false }
        let a = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty else { return false }
        if !q.isSpr { return q.correct.contains { $0.caseInsensitiveCompare(a) == .orderedSame } }

        let v = parseNumber(a)
        for c in q.correct {
            if c.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(a) == .orderedSame { return true }
            guard let v, let cv = parseNumber(c) else { continue }
            if abs(v - cv) < 1e-9 { return true }
            // A long decimal may be entered rounded or truncated, as long as it fills the entry field.
            if let dot = a.firstIndex(of: "."), !a.contains("/"), a.filter({ $0.isNumber }).count >= 4 {
                let decimals = a.distance(from: dot, to: a.endIndex) - 1
                let scale = pow(10.0, Double(decimals))
                let rounded = (cv * scale).rounded(.toNearestOrAwayFromZero) / scale
                let truncated = (cv * scale).rounded(.towardZero) / scale
                if abs(v - rounded) < 1e-9 || abs(v - truncated) < 1e-9 { return true }
            }
        }
        return false
    }
}
