import SwiftUI

/// Soft color behind the main pages, so the glass surfaces have something to refract.
struct Backdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(colors: [Color.accentColor.opacity(0.20), Color.purple.opacity(0.08), Color.teal.opacity(0.14)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(Color.accentColor.opacity(0.28))
                .frame(width: 520, height: 520)
                .blur(radius: 130)
                .offset(x: -280, y: -240)
            Circle()
                .fill(Color.teal.opacity(0.22))
                .frame(width: 460, height: 460)
                .blur(radius: 140)
                .offset(x: 340, y: 280)
        }
        .ignoresSafeArea()
    }
}

struct GlassCard: ViewModifier {
    var padding: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

extension View {
    func glassCard(padding: CGFloat = 20) -> some View { modifier(GlassCard(padding: padding)) }
}

struct CardTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.headline)
    }
}

/// A numbered square used by the question navigator and the review page.
struct NumberCell: View {
    let number: Int
    let answered: Bool
    let marked: Bool
    let current: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(number)")
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .frame(width: 42, height: 38)
                .foregroundStyle(answered ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(answered ? Color.accentColor : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(current ? Color.primary : Color.secondary.opacity(0.55),
                                      style: StrokeStyle(lineWidth: current ? 2.5 : 1, dash: answered ? [] : [4, 3]))
                )
                .overlay(alignment: .topTrailing) {
                    if marked {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                            .offset(x: 2, y: -5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(marked ? "Question \(number), marked for review" : "Question \(number)")
    }
}

struct NumberLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            Label("Answered", systemImage: "square.fill").foregroundStyle(.tint)
            Label("Unanswered", systemImage: "square.dashed")
            Label("Marked for review", systemImage: "bookmark.fill")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
