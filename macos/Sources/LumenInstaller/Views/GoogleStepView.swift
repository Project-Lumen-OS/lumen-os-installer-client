import SwiftUI

struct GoogleStepView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Header(title: L("Сервисы Google"),
                   lead: L("Lumen OS выходит без сервисов Google. Их можно добавить из архива MindTheGapps."))

            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(.white)
                    Text("G").font(.system(size: 24, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [.blue, .red, .yellow, .green], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Установить сервисы Google")).font(.system(size: 15.5, weight: .semibold))
                    Text(L("Google Play, голосовой поиск Google и пульт в приложении Google TV."))
                        .font(.system(size: 13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $m.gappsEnabled).toggleStyle(.switch).labelsHidden()
                    .onChange(of: m.gappsEnabled) { _, on in if on { m.refreshGappsFile() } }
            }
            .card()

            if m.gappsEnabled {
                if let z = m.gappsZip {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Нужный файл")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                        Text(z.name).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                        HStack(spacing: 14) {
                            Text("\(formatBytes(z.size))"); Text("GMS \(z.gmsversion)"); Text("sha256 \(z.sha.prefix(16))…")
                        }
                        .font(.system(size: 12)).foregroundStyle(Theme.faint)
                        HStack {
                            Button { m.downloadGapps() } label: { Label(L("Скачать с официального сайта MindTheGapps"), systemImage: "arrow.down.circle") }
                                .buttonStyle(LumenButton(small: true)).disabled(m.gappsProgress != nil)
                            Button(L("Выбрать файл…")) { m.pickGapps() }.buttonStyle(LumenButton(kind: .ghost, small: true)).disabled(m.gappsProgress != nil)
                        }
                        if let p = m.gappsProgress {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(m.gappsPhase)… \(Int(p * 100))%").font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                                ProgressBar(value: p)
                            }
                        } else if let s = m.gappsState {
                            Note(m.gappsOK ? .ok : .bad, icon: m.gappsOK ? "checkmark.seal" : "xmark.octagon", s)
                        }
                    }
                    .card()

                    planNote

                    if lumenInstalled {
                        Text(L("На проекторе уже стоит Lumen OS. Сервисы можно добавить отдельно, данные очистятся.")).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                        HStack {
                            Button { m.runCommand("gapps", title: L("Добавление сервисов Google"), zip: m.gappsFile) } label: {
                                Label(L("Добавить на уже установленную Lumen OS"), systemImage: "plus.circle")
                            }
                            .buttonStyle(LumenButton(small: true))
                            .disabled(!m.gappsOK || m.running || m.mode == .demo || isUnavailable || !m.deviceConnected)
                            Button { m.runCommand("gapps", title: L("Удаление сервисов Google"), remove: true) } label: { Label(L("Удалить сервисы Google"), systemImage: "minus.circle") }
                                .buttonStyle(LumenButton(kind: .ghost, small: true)).disabled(m.running || m.mode == .demo || isUnavailable || !m.deviceConnected)
                        }
                    }
                } else {
                    Note(.warn, icon: "questionmark.circle", L("Для этой модели в установщике пока нет списка допустимых файлов Google."))
                }
            }

            HStack {
                BackButton(to: .system)
                Spacer()
                Button { m.step = .install } label: { HStack { Text(L("Дальше: установка")); Image(systemName: "arrow.right") } }
                    .buttonStyle(LumenButton(kind: .primary))
            }
        }
    }

    /// Adding or removing the services on their own only makes sense on a projector that already runs Lumen OS.
    var lumenInstalled: Bool { m.selectedDevice?.lumen == true }

    var isUnavailable: Bool { if case .unavailable = m.gappsPlan { return true }; return false }

    @ViewBuilder var planNote: some View {
        if m.mode == .demo {
            Note(.warn, icon: "exclamationmark.triangle", L("В демо сервисы Google не ставятся, только скачивание и проверка файла."))
        } else {
            switch m.gappsPlan {
            case .onePass:
                Note(.ok, icon: "bolt.circle", T("Ставятся вместе с системой, данные очищаются один раз."))
            case .afterInstall:
                Note(.plain, icon: "arrow.triangle.2.circlepath", T("Ставятся вторым шагом после системы: в этом установщике нет erofs-utils. Данные очистятся ещё раз."))
            case .unavailable(let why):
                Note(.bad, icon: "xmark.octagon", why)
            }
        }
    }
}
