import SwiftUI

/// The Lumen OS logo from the repository (docs/brand_export/lumen_avatar_1024.png).
struct LumenLogo: View {
    var size: CGFloat = 40
    static let image: NSImage? = NSImage(contentsOfFile: Paths.logo)
    var body: some View {
        Group {
            if let img = Self.image { Image(nsImage: img).resizable().interpolation(.high) }
            else { Color(red: 0.04, green: 0.035, blue: 0.03) }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
        .overlay(RoundedRectangle(cornerRadius: size * 0.24).strokeBorder(Theme.line2))
        .shadow(color: Theme.accent.opacity(0.18), radius: size * 0.2)
    }
}

/// Russian / English / Chinese.
struct LanguagePicker: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        Picker(L("Язык"), selection: $m.lang) {
            ForEach(Lang.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

struct WelcomeView: View {
    @EnvironmentObject var m: AppModel
    /// The demo projector is in the developer build only (LUMEN_DEV).
    var showDemo = WelcomeView.devBuild
    static let devBuild: Bool = {
        #if LUMEN_DEV
        return true
        #else
        return false
        #endif
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Spacer(); LanguagePicker() }.padding(.bottom, 8)
            HStack(spacing: 14) {
                LumenLogo(size: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lumen Installer").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.muted)
                    Text(L("Lumen OS для проекторов XGIMI")).font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.text)
                }
            }
            Spacer().frame(height: 30)

            HStack(spacing: 18) {
                ChoiceCard(icon: "cable.connector", tint: Theme.accent, title: L("Подключить проектор"),
                           text: L("Установка на проектор по USB или Wi‑Fi.")) { m.choose(.real) }
                if showDemo {
                    ChoiceCard(icon: "play.rectangle.on.rectangle", tint: Theme.blue, title: L("Демо-проектор"),
                               text: L("Симулятор XGIMI Z9X с настоящим установщиком.")) { m.choose(.demo) }
                }
            }
            .frame(maxWidth: showDemo ? 820 : 400)
        }
        .padding(.horizontal, 64)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.top, 20)
    }
}

struct ChoiceCard: View {
    let icon: String
    let tint: Color
    let title: String
    let text: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
                    .frame(width: 46, height: 46).background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.13)))
                    .padding(.bottom, 4)
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                Text(text).font(.system(size: 13.5)).foregroundStyle(Theme.muted).lineSpacing(2.5).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack { Text(L("Начать")).font(.system(size: 13, weight: .semibold)); Image(systemName: "arrow.right") }.foregroundStyle(tint)
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 240, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(hover ? tint.opacity(0.5) : Theme.line))
            .offset(y: hover ? -2 : 0)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}
