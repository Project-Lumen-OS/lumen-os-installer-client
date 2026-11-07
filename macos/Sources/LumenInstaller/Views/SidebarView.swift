import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var m: AppModel

    func subtitle(_ s: AppModel.Step) -> String? {
        switch s {
        case .prepare: return nil
        case .device: return m.profile.map { p in m.selectedDevice?.hwSerial.map { "\(p.name) · \($0)" } ?? p.name }
        case .system: return m.workspace.map { $0.image.lastPath }
        case .google:
            guard m.gappsEnabled else { return L("без Google") }
            if m.mode == .demo { return L("в демо: только проверка файла") }
            if case .unavailable = m.gappsPlan { return L("недоступны для модели") }
            return m.gappsOK ? (m.gappsPlan == .onePass ? L("вместе с системой") : L("после установки")) : L("нужен файл")
        case .install: return m.running ? L("идёт…") : m.waitingGapps != nil ? L("ждёт ADB") : m.installDone ? L("готово") : m.exitCode.map { $0 == 0 ? L("готово") : L("остановлено") }
        }
    }
    func title(_ s: AppModel.Step) -> String {
        switch s { case .prepare: L("Подготовка"); case .device: L("Проектор"); case .system: L("Система"); case .google: L("Сервисы Google"); case .install: L("Установка") }
    }
    /// Back is always open; forward needs the projector connected (the install button checks it again).
    func locked(_ s: AppModel.Step) -> Bool {
        if m.running && s != .install { return true }
        let forward = s.rawValue > m.step.rawValue && !m.deviceConnected
        switch s {
        case .prepare, .device: return false
        case .system, .google: return m.profile == nil || forward
        case .install: return m.profile == nil || m.workspace == nil || forward
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 11) {
                LumenLogo(size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lumen Installer").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                    if m.mode == .demo { Text(L("Демо-режим")).font(.system(size: 11.5)).foregroundStyle(Theme.accent) }
                }
            }
            .padding(.top, 34).padding(.bottom, 20).padding(.horizontal, 6)

            ForEach(AppModel.Step.allCases, id: \.self) { s in
                Button { if !locked(s) { m.step = s } } label: {
                    HStack(spacing: 11) {
                        ZStack {
                            if s == .install && m.installDone {   // the system is installed: the last step turns green
                                Circle().fill(Theme.ok)
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Color(red: 0.03, green: 0.15, blue: 0.1))
                            } else {
                                Circle().strokeBorder(m.step == s ? Theme.accent : Theme.line2, lineWidth: m.step == s ? 1.5 : 1)
                                Text("\(s.rawValue + 1)").font(.system(size: 11, weight: .semibold)).foregroundStyle(m.step == s ? Theme.accent : Theme.muted)
                            }
                        }
                        .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title(s)).font(.system(size: 13.5, weight: .medium)).foregroundStyle(m.step == s ? Theme.text : Theme.muted)
                            if let sub = subtitle(s) {
                                Text(sub).font(.system(size: 11.5)).foregroundStyle(s == .install && m.installDone ? Theme.ok : Theme.faint).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(m.step == s ? Theme.blue.opacity(0.11) : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(m.step == s ? Theme.blue.opacity(0.28) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(locked(s) ? 0.45 : 1)
            }

            Text(L("ОБСЛУЖИВАНИЕ")).font(.system(size: 10.5, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.faint)
                .padding(.top, 22).padding(.bottom, 4).padding(.horizontal, 10)
            let ready = m.profile != nil && (m.workspace != nil) && !m.running && m.deviceConnected
            MaintButton(icon: "checkmark.shield", title: L("Проверка без записи"), enabled: ready) { m.runCommand("check", title: L("Проверка (ничего не записывается)")) }
            MaintButton(icon: "stethoscope", title: L("Проверить систему"), enabled: ready) { m.runCommand("verify", title: L("Проверка после установки")) }
            MaintButton(icon: "g.circle", title: L("Сервисы Google"), enabled: ready) { m.runCommand("gapps", title: L("Сервисы Google")) }
            MaintButton(icon: "list.bullet.clipboard", title: L("Прогресс установки"), enabled: ready) { m.runCommand("status", title: L("Прогресс установки")) }

            Spacer()
            LanguagePicker().controlSize(.small).padding(.horizontal, 10).padding(.bottom, 10)
            HStack(spacing: 14) {
                if let p = m.profile { Button(L("Инструкция")) { m.openURL(p.guideURL.absoluteString) } }
                Button("Telegram") { m.openURL("https://t.me/projector_lumenos") }
                Button(L("Выйти")) { m.leaveMode() }
            }
            .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.faint)
            .padding(.horizontal, 10).padding(.bottom, 14)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.04, green: 0.047, blue: 0.1).opacity(0.6))
    }
}

struct MaintButton: View {
    let icon: String
    let title: String
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).frame(width: 16)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}
