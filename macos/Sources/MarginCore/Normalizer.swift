import Foundation

/// Turns one stored bank line (list entry + raw question body) into a Question.
/// The question bank serves two shapes: the current one (stem / answerOptions / correct_answer)
/// and an older "disclosed" one (prompt / answer.choices / correct_choice). Both are handled,
/// and anything unexpected degrades to an unusable question instead of a crash.
public enum Normalizer {
    public static func question(fromLine line: Any?, liveIds: Set<String> = []) -> Question? {
        guard let o = line as? [String: Any], let stub = o["stub"] as? [String: Any] else { return nil }
        let id = str(stub["questionId"]) ?? str(stub["external_id"]) ?? str(stub["ibn"]) ?? ""
        guard !id.isEmpty else { return nil }

        var q = Question(id: id)
        q.externalId = nonEmpty(str(stub["external_id"]))
        q.ibn = nonEmpty(str(stub["ibn"]))
        q.domain = str(stub["primary_class_cd"]) ?? ""
        q.skill = str(stub["skill_desc"]) ?? ""
        q.difficulty = (str(stub["difficulty"]) ?? "M").uppercased()
        q.band = int(stub["score_band_range_cd"]) ?? 0
        q.domainName = nonEmpty(str(stub["primary_class_cd_desc"])) ?? Catalog.domainName(q.domain)
        q.section = Catalog.section(of: q.domain) ?? (int(o["test"]) == 2 ? .math : .rw)
        if !["E", "M", "H"].contains(q.difficulty) { q.difficulty = "M" }
        if q.band < 1 || q.band > 7 { q.band = q.difficulty == "E" ? 2 : q.difficulty == "H" ? 6 : 4 }
        if let ext = q.externalId { q.live = liveIds.contains(ext) }

        var detail: Any? = o["detail"]
        if let list = detail as? [Any] { detail = list.first }
        if let d = detail as? [String: Any] { fill(&q, d) }
        return q
    }

    private static func fill(_ q: inout Question, _ d: [String: Any]) {
        if let a = d["answer"] as? [String: Any], d["prompt"] != nil || a["choices"] != nil || a["style"] != nil {
            // Older disclosed shape
            q.stem = HTMLText.dropScripts(str(d["prompt"]) ?? str(d["stem"]))
            q.stimulus = HTMLText.dropScripts(str(d["body"]) ?? str(d["stimulus"]))
            q.rationale = HTMLText.dropScripts(str(a["rationale"]) ?? str(d["rationale"]))
            if let choices = a["choices"] as? [String: Any] {
                for key in choices.keys.sorted(by: { $0.lowercased() < $1.lowercased() }) {
                    q.choices.append(HTMLText.dropScripts(choiceText(choices[key])))
                }
            } else if let choices = a["choices"] as? [Any] {
                for c in choices { q.choices.append(HTMLText.dropScripts(choiceText(c))) }
            }
            let style = str(a["style"]) ?? ""
            q.isSpr = q.choices.isEmpty || style.uppercased().contains("SPR")
            if let key = nonEmpty(str(a["correct_choice"]) ?? str(a["correct_answer"])) {
                let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
                q.correct.append(q.isSpr ? k : k.uppercased())
            }
        } else {
            // Current shape
            q.stem = HTMLText.dropScripts(str(d["stem"]) ?? str(d["prompt"]))
            q.stimulus = HTMLText.dropScripts(str(d["stimulus"]) ?? str(d["body"]))
            q.rationale = HTMLText.dropScripts(str(d["rationale"]))
            var options: Any? = d["answerOptions"]
            if let encoded = options as? String, encoded.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("["),
               let data = encoded.data(using: .utf8) {
                options = try? JSONSerialization.jsonObject(with: data)
            }
            var optionIds: [String] = []
            if let list = options as? [Any] {
                for op in list {
                    if let oo = op as? [String: Any] {
                        q.choices.append(HTMLText.dropScripts(str(oo["content"]) ?? str(oo["body"])))
                        optionIds.append(str(oo["id"]) ?? "")
                    } else if let s = str(op) {
                        q.choices.append(HTMLText.dropScripts(s)); optionIds.append("")
                    }
                }
            }
            let type = (str(d["type"]) ?? "").lowercased()
            q.isSpr = type == "spr" || (type != "mcq" && q.choices.isEmpty)
            let answers = strings(d["correct_answer"])
            if q.isSpr {
                q.correct.append(contentsOf: answers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            } else {
                for s in answers {
                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    if t.count == 1, "ABCDEF".contains(t) { q.correct.append(t) }
                }
                if q.correct.isEmpty {
                    for k in strings(d["keys"]) {
                        if let i = optionIds.firstIndex(of: k), i < 6 { q.correct.append(String(Array("ABCDEF")[i])) }
                    }
                }
            }
        }
        if q.correct.isEmpty { recoverKey(&q) }
    }

    private static func choiceText(_ any: Any?) -> String? {
        if let o = any as? [String: Any] { return str(o["body"]) ?? str(o["content"]) }
        return str(any)
    }

    /// Some older items ship without a key; the explanation states it in prose.
    private static func recoverKey(_ q: inout Question) {
        let text = HTMLText.stripTags(q.rationale)
        guard !text.isEmpty else { return }
        if !q.isSpr {
            if let m = Rx.first("Choice\\s*([A-D])\\s*is\\s*(?:the\\s*)?(?:correct|best)", in: text, options: [.caseInsensitive]) {
                q.correct.append(m[1].uppercased()); q.keyRecovered = true
            }
            return
        }
        guard let m = Rx.first("correct answer is\\s*(.+)", in: text, options: [.caseInsensitive]) else { return }
        var tail = m[1]
        // Stop at the end of the sentence: a period followed by a space or the end, which a decimal point never is.
        if let end = Rx.firstRange("\\.(?=\\s|$)", in: tail) { tail = (tail as NSString).substring(to: end.location) }
        if let cut = tail.range(of: " Note", options: .caseInsensitive), cut.lowerBound > tail.startIndex { tail = String(tail[..<cut.lowerBound]) }
        for n in Rx.all("-?(?:\\d+\\.\\d+|\\.\\d+|\\d+/\\d+|\\d+)", in: tail) where !q.correct.contains(n) { q.correct.append(n) }
        if !q.correct.isEmpty { q.keyRecovered = true }
    }

    // ---- tolerant JSON access ----

    static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }

    static func str(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        if any is NSNull || any == nil { return nil }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    static func int(_ any: Any?) -> Int? {
        if let s = any as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }

    static func strings(_ any: Any?) -> [String] {
        if let list = any as? [Any] { return list.compactMap { str($0) } }
        if let s = str(any) {
            if s.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("["), let data = s.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                return parsed.compactMap { str($0) }
            }
            return s.isEmpty ? [] : [s]
        }
        return []
    }
}
