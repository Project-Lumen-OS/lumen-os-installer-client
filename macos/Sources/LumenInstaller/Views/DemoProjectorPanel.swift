import SwiftUI

/// The demo projector as it would look on the wall: its screen follows what the installer does to it.
struct DemoProjectorPanel: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        let s = m.simStatus
        VStack(alignment: .leading, spacing: 0) {
            Text(L("ДЕМО-ПРОЕКТОР")).font(.system(size: 10.5, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.accent)
            Text("XGIMI Z9X · \(Simulator.serial)").font(.system(size: 14, weight: .semibold)).padding(.top, 3).padding(.bottom, 16)

            ScreenView(screen: s?.screen ?? .stock)
            BeamShape().fill(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.67).opacity(0.02), Color(red: 1, green: 0.9, blue: 0.67).opacity(0.22)], startPoint: .top, endPoint: .bottom))
                .frame(height: 34).padding(.horizontal, 30)
            ProjectorGlyph().frame(width: 120, height: 50).frame(maxWidth: .infinity)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Кабель USB A–A")).font(.system(size: 13, weight: .medium))
                    Text(s?.cable == true ? L("подключён к компьютеру") : L("не подключён")).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { s?.cable ?? false }, set: { m.setCable($0) })).toggleStyle(.switch).labelsHidden()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
            .padding(.top, 20)

            VStack(alignment: .leading, spacing: 7) {
                kv(L("Экран"), screenName(s?.screen))
                kv(L("Последняя команда"), s?.lastWrite ?? "—")
            }
            .padding(.top, 14)

            Text(L("Симулятор отвечает на adb и fastboot как Z9X. Установщик настоящий, образ тестовый."))
                .font(.system(size: 11.5)).foregroundStyle(Theme.faint).lineSpacing(2).padding(.top, 16)

            Spacer()
            Button { m.resetDemoProjector() } label: { Label(L("Сбросить демо-проектор"), systemImage: "arrow.counterclockwise") }
                .buttonStyle(LumenButton(kind: .ghost, small: true)).disabled(m.running)
                .help(L("Возвращает симулятор к стоковой системе XGIMI."))
            Text(L("Только для симулятора, настоящий проектор не затрагивается.")).font(.system(size: 10.5)).foregroundStyle(Theme.faint).padding(.leading, 11)
        }
        .padding(.horizontal, 18).padding(.top, 40).padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.04, green: 0.047, blue: 0.1).opacity(0.6))
    }

    func kv(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.system(size: 11)).foregroundStyle(Theme.muted)
            Text(v).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.text).lineLimit(2)
        }
    }

    func screenName(_ s: Simulator.Status.Screen?) -> String {
        switch s {
        case .stock, .none: L("родная система XGIMI")
        case .fastboot: "fastbootd"
        case .reboot: L("перезагрузка")
        case .booting: L("первый запуск Lumen OS")
        case .lumen: L("Lumen OS: экран настройки")
        }
    }
}

struct BeamShape: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX + 14, y: r.maxY)); p.addLine(to: CGPoint(x: r.midX - 14, y: r.maxY)); p.closeSubpath()
        }
    }
}

struct ScreenView: View {
    let screen: Simulator.Status.Screen
    @State private var dots = 0
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            switch screen {
            case .stock:
                LinearGradient(colors: [Color(red: 0.1, green: 0.17, blue: 0.29), Color(red: 0.05, green: 0.08, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 6) {
                    Text("XGIMI").font(.system(size: 18, weight: .heavy)).tracking(6).foregroundStyle(Color(red: 0.56, green: 0.7, blue: 1))
                    HStack(spacing: 5) { ForEach(0..<4) { _ in RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.12)).frame(width: 34, height: 22) } }
                }
            case .fastboot:
                Color.black
                VStack(alignment: .leading, spacing: 3) {
                    Text("fastbootd").font(.system(size: 13, weight: .bold, design: .monospaced))
                    Text("product: mt5877").font(.system(size: 10, design: .monospaced))
                    Text("slot: b" + String(repeating: ".", count: dots)).font(.system(size: 10, design: .monospaced))
                }
                .foregroundStyle(Color(red: 0.62, green: 0.89, blue: 0.62))
            case .reboot:
                Color.black
                ProgressView().controlSize(.small).tint(.gray)
            case .booting:
                RadialGradient(colors: [Color(red: 0.17, green: 0.13, blue: 0.32), .black], center: .center, startRadius: 0, endRadius: 140)
                VStack(spacing: 8) {
                    LumenLogo(size: 30)
                    Text("Lumen OS" + String(repeating: ".", count: dots)).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                }
            case .lumen:
                LinearGradient(colors: [Color(red: 0.13, green: 0.2, blue: 0.4), Color(red: 0.79, green: 0.44, blue: 0.31), Color(red: 0.96, green: 0.7, blue: 0.42)], startPoint: .top, endPoint: .bottom)
                Circle().fill(Color(red: 1, green: 0.89, blue: 0.66)).frame(width: 24, height: 24).shadow(color: Color(red: 1, green: 0.82, blue: 0.54), radius: 12)
                    .offset(x: 55, y: 30)
                VStack(spacing: 2) {
                    Text("21:30").font(.system(size: 26, weight: .light)).foregroundStyle(.white)
                    Text(L("Добро пожаловать")).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.85))
                }
                .shadow(radius: 6)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line2))
        .animation(.easeInOut(duration: 0.4), value: screen)
        .onReceive(timer) { _ in dots = (dots + 1) % 4 }
    }
}
