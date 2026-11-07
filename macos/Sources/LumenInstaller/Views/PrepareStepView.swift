import SwiftUI
import AppKit

/// Step 0: what to do on the projector so the computer can see it (install guides, "Prepare the projector").
struct PrepareStepView: View {
    @EnvironmentObject var m: AppModel
    @State private var model = ""
    @State private var progress: Double?
    @State private var message: String?
    @State private var failed = false
    @State private var ready = false   // the checked APK is on disk (hashing 18 MB: not on every redraw)

    var profile: Profile? { m.profiles.first { $0.id == model } ?? m.profiles.first }
    /// As in the install guides, "1. Подготовьте проектор", without the firmware item: the installer checks it itself.
    var steps: [String] {
        switch profile?.id {
        case "play6": return [
            L("Подключите проектор к своему Wi‑Fi. Если в настройках есть автообновление системы, выключите его. Если обновление уже скачано, не перезагружайте проектор сами, пока Lumen OS не будет записана."),
            L("Включите ADB через SystemUI Tuner (файл ниже). На Play 6 он сразу включает ADB по Wi‑Fi, перезагрузка не нужна."),
            L("Запишите IP-адрес проектора. Он есть в настройках сети Wi‑Fi на проекторе и в списке устройств роутера. Если адрес не найти, на следующем шаге есть кнопка «Найти в сети»."),
            L("Кабель A–A держите под рукой, но пока не вставляйте. Флешка может оставаться в порту, установщик скажет, когда её вынуть."),
        ]
        case "hb": return [
            L("Подключите проектор к своему Wi‑Fi. Если сток предлагает обновление системы, откажитесь: скачанное обновление ждёт перезагрузки и мешает установке."),
            L("Включите ADB: в «Настройки → Об устройстве» нажимайте OK на номере сборки, пока не откроется «Для разработчиков», и включите там «Отладка по USB». На HB это ADB по Wi‑Fi."),
            L("Запишите IP-адрес проектора. Он есть в настройках сети Wi‑Fi на проекторе и в списке устройств роутера."),
        ]
        default: return [
            L("Выключите Wi‑Fi и не включайте его до конца установки: сток сам ставит обновления XGIMI во второй слот."),
            L("Включите ADB через SystemUI Tuner (файл ниже)."),
            L("Перезагрузите проектор: ADB заработает только после перезагрузки."),
            L("Подключите кабель A–A к порту USB 2.0 проектора и к компьютеру."),
        ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Header(title: L("Подготовьте проектор"),
                   lead: L("На проекторе должен быть включён ADB. Это делается один раз на стоковой системе."))

            Picker("", selection: $model) {
                ForEach(m.profiles) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                            .frame(width: 20, height: 20).background(Circle().strokeBorder(Theme.line2))
                        Text(s).font(.system(size: 13.5)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(L("Названия пунктов меню на стоке могут немного отличаться, это зависит от языка и версии прошивки.")).font(.system(size: 12)).foregroundStyle(Theme.faint)
                    .fixedSize(horizontal: false, vertical: true)
                if let p = profile {
                    Button(L("Подробная инструкция")) { m.openURL(p.guideURL.absoluteString) }
                        .buttonStyle(.plain).font(.system(size: 12.5)).foregroundStyle(Theme.blue).padding(.top, 2)
                }
            }
            .card()

            if profile?.id != "hb" { tuner }

            HStack {
                Spacer()
                Button { m.step = .device } label: { HStack { Text(L("Дальше: проектор")); Image(systemName: "arrow.right") } }
                    .buttonStyle(LumenButton(kind: .primary))
            }
        }
        .onAppear { if model.isEmpty { model = m.profile?.id ?? "z9x" } }
        .task { ready = await Task.detached { Tuner.ready }.value }
    }

    var tuner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SystemUI Tuner \(Tuner.version)").font(.system(size: 15, weight: .semibold))
            Text(L("На стоке XGIMI меню «Для разработчиков» скрыто, ADB включается через это приложение. Скопируйте файл на флешку FAT32, установите его через файловый менеджер XGIMI, откройте SystemUI Tuner и подтвердите включение отладки по USB."))
                .font(.system(size: 13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if ready {
                    Button { saveToStick() } label: { Label(L("Сохранить на флешку…"), systemImage: "externaldrive") }
                        .buttonStyle(LumenButton(small: true))
                    Button(L("Показать в Finder")) { m.reveal(Tuner.file) }.buttonStyle(LumenButton(kind: .ghost, small: true))
                } else {
                    Button { download() } label: { Label(L("Скачать (17,9 МБ)"), systemImage: "arrow.down.circle") }
                        .buttonStyle(LumenButton(small: true)).disabled(progress != nil)
                }
                Button(L("Источник")) { m.openURL(Tuner.source) }.buttonStyle(.plain).font(.system(size: 12.5)).foregroundStyle(Theme.blue)
            }
            if let p = progress { ProgressBar(value: p) }
            if let msg = message { Note(failed ? .bad : .ok, icon: failed ? "xmark.octagon" : "checkmark.circle", msg) }
            Text(L("Файл сохраняется как %@: файловый менеджер XGIMI не открывает файлы .apk.", Tuner.stickName))
                .font(.system(size: 12)).foregroundStyle(Theme.faint)
        }
        .card()
    }

    func download() {
        progress = 0; message = nil
        Task {
            do {
                try await Tuner.fetch { d, t in Task { @MainActor in progress = Double(d) / Double(max(t, 1)) } }
                failed = false; ready = true; message = L("Файл скачан, sha256 совпадает.")
            } catch { failed = true; message = error.localizedDescription }
            progress = nil
        }
    }

    func saveToStick() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.directoryURL = URL(fileURLWithPath: "/Volumes")
        p.message = L("Выберите флешку")
        p.prompt = L("Сохранить")
        guard p.runModal() == .OK, let url = p.url else { return }
        do { failed = false; message = L("Сохранено: %@", try Tuner.copy(to: url.path)) }
        catch { failed = true; message = error.localizedDescription }
    }
}
