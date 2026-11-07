import SwiftUI

struct SystemStepView: View {
    @EnvironmentObject var m: AppModel
    @State private var showOlder = false   // the latest release (and the chosen one) by default, older ones on request

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Header(title: L("Выберите версию Lumen OS"),
                   lead: L("Официальные релизы с GitHub. Подпись и контрольную сумму проверяет установщик."))

            if let p = m.profile {
                HStack(spacing: 8) {
                    Badge(text: p.name, tone: .blue, icon: "videoprojector")
                    if m.mode == .real {
                        Toggle(L("Показывать бета-версии"), isOn: $m.showBeta).toggleStyle(.switch).controlSize(.small)
                            .onChange(of: m.showBeta) { _, _ in m.autoselectRelease() }
                        Spacer()
                        Button { m.loadReleases() } label: { Label(L("Обновить"), systemImage: "arrow.clockwise") }.buttonStyle(LumenButton(kind: .ghost, small: true))
                    }
                }
            }

            if m.releasesLoading {
                HStack { ProgressView().controlSize(.small); Text(L("Загружаю список релизов с GitHub…")).foregroundStyle(Theme.muted) }.card()
            }
            if let e = m.releasesError { Note(.bad, icon: "xmark.octagon", e) }

            if !m.releasesLoading && m.deviceReleases.isEmpty && m.mode == .real && m.releasesError == nil {
                Note(.warn, icon: "questionmark.circle", m.showBeta ? L("Для этой модели нет релизов. Выберите папку с релизом.") : L("Для этой модели нет релизов (без бета-версий). Включите бета-версии или выберите папку с релизом."))
            }

            VStack(alignment: .leading, spacing: 8) {
                let all = m.deviceReleases
                ForEach(Array(all.enumerated()), id: \.element.id) { i, r in
                    if showOlder || i == 0 || m.selectedReleaseTag == r.tag {
                        ReleaseRow(release: r, latest: i == 0, selected: m.selectedReleaseTag == r.tag)
                            .onTapGesture { m.selectRelease(r) }
                    }
                }
                if all.count > 1 {
                    Button { withAnimation(.easeOut(duration: 0.15)) { showOlder.toggle() } } label: {
                        Label(showOlder ? L("Скрыть предыдущие версии") : L("Предыдущие версии (%@)", "\(all.count - 1)"),
                              systemImage: showOlder ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(LumenButton(kind: .ghost, small: true))
                }
            }

            if let prog = m.downloadProgress {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L("Скачиваю %@…", "\(m.downloadFile ?? "")")).font(.system(size: 13.5, weight: .medium))
                        Spacer()
                        Text("\(Int(prog * 100))%").font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.muted)
                        Button(L("Отмена")) { m.cancelDownload() }.buttonStyle(LumenButton(kind: .ghost, small: true))
                    }
                    ProgressBar(value: prog)
                    Text(L("Файлы сохраняются в ~/Lumen Installer/releases.")).font(.system(size: 12)).foregroundStyle(Theme.faint)
                }
                .card()
            }

            if let ws = m.workspace {
                Note(.ok, icon: "checkmark.circle", T("Готово к установке: %@\n%@", "\(ws.image.lastPath)", "\(ws.dir)"))
                    .contextMenu { Button(L("Показать в Finder")) { m.reveal(ws.image) } }
            }

            HStack {
                BackButton(to: .device)
                if m.mode == .real {
                    Button(L("Выбрать папку с релизом…")) { m.pickLocalRelease() }.buttonStyle(LumenButton(kind: .ghost, small: true))
                }
                Spacer()
                if m.workspace == nil, m.selectedRelease.map(m.isReady) != true {
                    Button { m.prepareRelease() } label: { HStack { Image(systemName: "arrow.down.circle"); Text(L("Скачать")) } }
                        .buttonStyle(LumenButton(kind: .primary))
                        .disabled(m.selectedRelease == nil || m.downloadProgress != nil)
                } else {
                    Button { m.nextFromSystem() } label: { HStack { Text(L("Дальше: сервисы Google")); Image(systemName: "arrow.right") } }
                        .buttonStyle(LumenButton(kind: .primary))
                }
            }
        }
        .onAppear { if m.releases.isEmpty { m.loadReleases() } else { m.autoselectRelease() } }
    }
}

struct ReleaseRow: View {
    let release: Release
    let latest: Bool
    let selected: Bool
    var downloaded: Bool { Releases.isDownloaded(release) }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().strokeBorder(selected ? Theme.accent : Theme.line2, lineWidth: 2)
                if selected { Circle().fill(Theme.accent).frame(width: 8, height: 8) }
            }
            .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Lumen OS \(release.version)").font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.text)
                    if latest && !release.prerelease { Badge(text: L("последняя"), tone: .ok) }
                    if release.prerelease { Badge(text: L("бета"), tone: .warn) }
                    if release.demo { Badge(text: L("демо-образ"), tone: .blue) }
                    if downloaded { Badge(text: L("скачано"), tone: .blue, icon: "checkmark") }
                }
                HStack(spacing: 10) {
                    Text(release.tag).font(.system(size: 12, design: .monospaced))
                    if let d = release.published { Text(d.formatted(date: .abbreviated, time: .omitted)) }
                    if let img = release.images.first { Text(L("образ %@", "\(formatBytes(img.size))")) }
                }
                .font(.system(size: 12)).foregroundStyle(Theme.faint)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Theme.accent.opacity(0.05) : Color.white.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Theme.accent.opacity(0.6) : Theme.line))
        .contentShape(Rectangle())
    }
}
