import SwiftUI

enum Theme {
    static let bg = Color(red: 0.043, green: 0.051, blue: 0.09)
    static let panel = Color(red: 0.09, green: 0.10, blue: 0.20).opacity(0.78)
    static let line = Color(red: 0.63, green: 0.67, blue: 1).opacity(0.13)
    static let line2 = Color(red: 0.63, green: 0.67, blue: 1).opacity(0.24)
    static let text = Color(red: 0.91, green: 0.92, blue: 1)
    static let muted = Color(red: 0.60, green: 0.63, blue: 0.78)
    static let faint = Color(red: 0.42, green: 0.44, blue: 0.60)
    static let accent = Color(red: 1, green: 0.78, blue: 0.42)
    static let accent2 = Color(red: 1, green: 0.61, blue: 0.37)
    static let blue = Color(red: 0.49, green: 0.65, blue: 1)
    static let ok = Color(red: 0.37, green: 0.83, blue: 0.60)
    static let warn = Color(red: 1, green: 0.76, blue: 0.37)
    static let bad = Color(red: 1, green: 0.42, blue: 0.49)
}

struct SkyBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.bg, Color(red: 0.055, green: 0.067, blue: 0.14), Theme.bg], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.accent2.opacity(0.18), .clear], center: UnitPoint(x: 0.9, y: -0.05), startRadius: 0, endRadius: 650)
            RadialGradient(colors: [Color(red: 0.35, green: 0.43, blue: 1).opacity(0.17), .clear], center: UnitPoint(x: 0.05, y: 1.1), startRadius: 0, endRadius: 600)
            Canvas { ctx, size in
                var rng = SeededRandom(seed: 7)
                for _ in 0..<90 {
                    let p = CGPoint(x: rng.next() * size.width, y: rng.next() * size.height)
                    let r = 0.5 + rng.next() * 1.0
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: r, height: r)), with: .color(.white.opacity(0.25 + rng.next() * 0.45)))
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) % 10_000) / 10_000
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 18
    var highlight = false
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(highlight ? Theme.accent.opacity(0.65) : Theme.line, lineWidth: highlight ? 1.5 : 1))
    }
}
extension View {
    func card(padding: CGFloat = 18, highlight: Bool = false) -> some View { modifier(CardModifier(padding: padding, highlight: highlight)) }
}

struct Badge: View {
    enum Tone { case plain, ok, warn, bad, blue }
    let text: String
    var tone: Tone = .plain
    var icon: String? = nil
    var color: Color {
        switch tone { case .plain: Theme.muted; case .ok: Theme.ok; case .warn: Theme.warn; case .bad: Theme.bad; case .blue: Theme.blue }
    }
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9.5, weight: .bold)) }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(tone == .plain ? 0 : 0.09)))
        .overlay(Capsule().strokeBorder(color.opacity(0.4)))
    }
}

/// "← Back" to the previous step.
struct BackButton: View {
    @EnvironmentObject var m: AppModel
    let to: AppModel.Step
    var body: some View {
        Button { m.step = to } label: { HStack { Image(systemName: "arrow.left"); Text(L("Назад")) } }
            .buttonStyle(LumenButton(kind: .ghost))
            .disabled(m.running)
    }
}

struct Note: View {
    enum Tone { case plain, ok, warn, bad }
    let tone: Tone
    let icon: String
    let text: Text
    init(_ tone: Tone = .plain, icon: String = "info.circle", _ text: Text) { self.tone = tone; self.icon = icon; self.text = text }
    init(_ tone: Tone = .plain, icon: String = "info.circle", _ s: String) { self.init(tone, icon: icon, Text(s)) }
    var color: Color { switch tone { case .plain: Theme.blue; case .ok: Theme.ok; case .warn: Theme.warn; case .bad: Theme.bad } }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).font(.system(size: 14, weight: .semibold)).padding(.top, 1)
            text.foregroundStyle(Theme.text.opacity(0.92)).lineSpacing(2.5).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 11).fill(color.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(color.opacity(0.32)))
    }
}

struct LumenButton: ButtonStyle {
    enum Kind { case primary, normal, danger, ghost }
    var kind: Kind = .normal
    var small = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration c: Configuration) -> some View {
        c.label
            .font(.system(size: small ? 12.5 : 13.5, weight: .semibold))
            .padding(.horizontal, small ? 11 : 16).padding(.vertical, small ? 6 : 9)
            .foregroundStyle(fg)
            .background(RoundedRectangle(cornerRadius: small ? 8 : 10).fill(bg).brightness(c.isPressed ? -0.06 : 0))
            .overlay(RoundedRectangle(cornerRadius: small ? 8 : 10).strokeBorder(border))
            .shadow(color: kind == .primary ? Theme.accent2.opacity(0.28) : .clear, radius: 12, y: 5)
            .opacity(enabled ? 1 : 0.42)
            .contentShape(Rectangle())
    }
    private var fg: Color { switch kind { case .primary: Color(red: 0.17, green: 0.09, blue: 0); case .danger: Color(red: 1, green: 0.78, blue: 0.8); case .ghost: Theme.muted; case .normal: Theme.text } }
    private var bg: AnyShapeStyle {
        switch kind {
        case .primary: AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.83, blue: 0.53), Color(red: 1, green: 0.69, blue: 0.37)], startPoint: .top, endPoint: .bottom))
        case .danger: AnyShapeStyle(Theme.bad.opacity(0.16))
        case .ghost: AnyShapeStyle(Color.clear)
        case .normal: AnyShapeStyle(Color.white.opacity(0.06))
        }
    }
    private var border: Color { switch kind { case .primary, .ghost: .clear; case .danger: Theme.bad.opacity(0.5); case .normal: Theme.line2 } }
}

struct ProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(LinearGradient(colors: [Theme.accent2, Theme.accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(8, g.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 8)
        .animation(.easeOut(duration: 0.2), value: value)
    }
}

struct Header: View {
    let title: String
    let lead: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.text)
            Text(lead).font(.system(size: 14)).foregroundStyle(Theme.muted).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 10)
    }
}

func formatBytes(_ b: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
}
