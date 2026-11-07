import SwiftUI

struct InstallStepView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Header(title: m.runTitle.isEmpty ? L("Установка") : m.runTitle,
                   lead: L("Установку ведёт официальный скрипт Lumen OS. Если ему нужен ответ, появится окно с вопросом."))

            if !m.running && m.exitCode == nil { summary }

            if m.running || m.exitCode != nil || !m.log.isEmpty {
                if let code = m.exitCode { result(code) }
                if m.isInstallRun { pipeline }
                if m.inGappsChain && m.running {
                    Note(.plain, icon: "g.circle", T("Шаг 2 из 2: установщик добавляет сервисы Google (gapps --zip). Данные очистятся ещё раз."))
                }
                LogView(lines: m.log)
                HStack {
                    if m.running {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(m.vbmetaRunning ? L("Приложение делает шаг vbmeta…") : L("Установщик работает…")).foregroundStyle(Theme.muted) }
                        Spacer()
                        Button(L("Остановить")) { m.stop() }.buttonStyle(LumenButton(kind: .danger, small: true))
                    } else {
                        BackButton(to: .google)
                        Spacer()
                        Button(L("Скопировать журнал")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(m.log.map(\.text).joined(separator: "\n"), forType: .string)
                        }
                        .buttonStyle(LumenButton(kind: .ghost, small: true))
                    }
                }
            }
        }
    }

    var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                row(L("Проектор"), m.profile.map { p in "\(p.name) (\(p.model))" + (m.selectedDevice?.hwSerial.map { " · \($0)" } ?? "") } ?? "—")
                row(L("Подключение"), m.selectedDevice.map { $0.transport == .wifi ? "Wi-Fi \($0.serial)" : $0.transport == .usb ? L("кабель USB") : "fastboot" } ?? L("не подключён"))
                row(L("Система"), m.workspace?.image.lastPath ?? "—")
                googleRow
                if m.mode == .demo { row(L("Режим"), L("демо-проектор, без кодеков (--no-blobs)")) }
            }
            .card()

            Note(.warn, icon: "exclamationmark.triangle",
                 T("Установка стирает все данные на проекторе. Перед записью установщик предложит сделать копию и попросит ввести ERASE."))

            if !m.deviceConnected {
                Note(.bad, icon: "cable.connector.slash", L("Проектор не подключён. Подключите его, чтобы начать установку."))
            }

            HStack {
                BackButton(to: .google)
                Spacer()
                Button { m.beginInstall() } label: { HStack { Image(systemName: "bolt.fill"); Text(L("Начать установку")) } }
                    .buttonStyle(LumenButton(kind: .primary)).disabled(!m.canInstall)
            }
        }
        .task(id: "\(m.selectedDeviceID ?? "")|\(m.profile?.id ?? "")|\(m.running)") { await m.refreshVbmeta() }
        .alert(L("Сначала шаг vbmeta"), isPresented: $m.vbmetaAsk) {
            Button(L("Продолжить")) { m.runVbmeta(thenInstall: true) }
            Button(L("Отмена"), role: .cancel) {}
        } message: {
            Text(L("Перед установкой проектор перезагрузится в fastboot и приложение отключит проверку системы (vbmeta). Данные на этом шаге не стираются.") + (m.profile?.id == "hb" ? " " + L("Для Z9X HB подключите кабель A–A: fastboot работает только по кабелю.") : ""))
        }
    }

    /// ✓ the Google services go on in this install (with the system or right after it), ✕ they do not.
    var googleRow: some View {
        HStack(alignment: .top) {
            Text(L("Сервисы Google")).foregroundStyle(Theme.muted).frame(width: 140, alignment: .leading)
            Image(systemName: m.gappsWillInstall ? "checkmark" : "xmark").font(.system(size: 13, weight: .bold))
                .foregroundStyle(m.gappsWillInstall ? Theme.ok : Theme.muted)
            Spacer()
        }
        .font(.system(size: 13.5))
    }

    func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).foregroundStyle(Theme.muted).frame(width: 140, alignment: .leading)
            Text(v).foregroundStyle(Theme.text).textSelection(.enabled)
            Spacer()
        }
        .font(.system(size: 13.5))
    }

    func result(_ code: Int32) -> some View {
        if m.writtenButUnchecked { return AnyView(writtenResult) }
        if code == 0, m.waitingGapps != nil { return AnyView(waitingResult) }
        return AnyView(resultBox(code))
    }

    /// Lumen OS is written; Google services follow once debugging is on again (the wipe turned it off).
    var waitingResult: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 26)).foregroundStyle(Theme.ok)
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Lumen OS записана. Дальше сервисы Google")).font(.system(size: 16, weight: .semibold))
                Text(L("Пройдите настройку на проекторе. Затем в «Настройки → Настройки устройства → Для разработчиков» включите «Отладка по USB» и «Отладка суперпользователем» (если раздела нет: «Об устройстве → Сборка», 7 раз OK) и подключите кабель. Сервисы Google установятся сами."))
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("Жду проектор с Lumen OS…")).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            Button(L("Не ставить сейчас")) { m.skipWaitingGapps() }.buttonStyle(LumenButton(kind: .ghost, small: true))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.ok.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.ok.opacity(0.4)))
    }

    /// The system is written; only the check after the first start could not reach the projector.
    var writtenResult: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 26)).foregroundStyle(Theme.ok)
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Lumen OS записана")).font(.system(size: 16, weight: .semibold))
                Text(L("Проверка после запуска не прошла: после очистки данных ADB выключен. Пройдите настройку на проекторе, включите ADB и нажмите «Проверить систему»."))
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                if m.chainSkipped {
                    Text(L("Сервисы Google ещё не добавлены. Добавьте их на шаге «Сервисы Google», когда ADB будет включён."))
                        .font(.system(size: 13)).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button { m.runCommand("verify", title: L("Проверка после установки")) } label: { Label(L("Проверить систему"), systemImage: "stethoscope") }
                .buttonStyle(LumenButton(small: true)).disabled(!m.deviceConnected)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.ok.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.ok.opacity(0.4)))
    }

    func resultBox(_ code: Int32) -> some View {
        let ok = code == 0
        let stopLine = m.log.last { $0.kind == .stop }?.text
        return HStack(spacing: 14) {
            Image(systemName: ok ? "checkmark.seal.fill" : "exclamationmark.octagon.fill").font(.system(size: 26)).foregroundStyle(ok ? Theme.ok : Theme.bad)
            VStack(alignment: .leading, spacing: 3) {
                Text(ok ? L("Готово") : L("Установщик остановился")).font(.system(size: 16, weight: .semibold))
                Text(ok ? okText :
                        (stopLine.map { $0.replacingOccurrences(of: #"^\d\d:\d\d:\d\d\s+"#, with: "", options: .regularExpression) } ?? L("Код выхода %@. Подробности в журнале.", "\(code)")))
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if ok && m.mode == .real && !m.inGappsChain && m.gappsChainResult == nil && m.isInstallRun && m.lastOptions?.gappsZip == nil {
                Button { m.step = .google; m.gappsEnabled = true; m.refreshGappsFile() } label: { Label(L("Добавить сервисы Google"), systemImage: "plus.circle") }
                    .buttonStyle(LumenButton(small: true))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill((ok ? Theme.ok : Theme.bad).opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder((ok ? Theme.ok : Theme.bad).opacity(0.4)))
    }

    var okText: String {
        if m.gappsChainResult == 0 || m.lastOptions?.gappsZip != nil { return L("Lumen OS и сервисы Google установлены. Если Google не пускает в аккаунт, зарегистрируйте GSF ID (Обслуживание → Сервисы Google).") }
        if m.mode == .demo && m.isInstallRun { return L("Все шаги выполнены. В демо сервисы Google не ставятся.") }
        return L("Все шаги выполнены, дальше настройка на экране проектора.")
    }

    /// skipped:wiped: after a wipe the installer does not wait for adb, the install went through.
    func isDone(_ key: String) -> Bool { key == "gapps" ? m.gappsChainResult == 0 : ["done", "skipped:wiped"].contains(m.state["step_\(key)"]) }

    var pipeline: some View {
        let steps = m.installPipeline
        let current = steps.firstIndex { !isDone($0.key) && m.skipNote($0.key) == nil }
        return HStack(alignment: .top, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                let done = isDone(s.key)
                let note = done ? nil : m.skipNote(s.key)
                let skip = note != nil
                let cur = m.running && i == current
                let fail = !m.running && (m.exitCode ?? 0) != 0 && i == current
                VStack(spacing: 7) {
                    HStack(spacing: 0) {
                        Rectangle().fill(i == 0 ? .clear : (done || cur || skip) ? Theme.ok : Theme.line2).frame(height: 2)
                        ZStack {
                            Circle().fill(done ? Theme.ok : Color(red: 0.09, green: 0.1, blue: 0.2))
                            Circle().strokeBorder(done ? Theme.ok : cur ? Theme.accent : fail ? Theme.bad : Theme.line2,
                                                  style: StrokeStyle(lineWidth: 2, dash: skip ? [3, 3] : []))
                            if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color(red: 0.03, green: 0.15, blue: 0.1)) }
                            else if cur { Circle().fill(Theme.accent).frame(width: 8, height: 8) }
                            else if fail { Image(systemName: "xmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.bad) }
                            else { Text("\(i + 1)").font(.system(size: 11, weight: .semibold)).foregroundStyle(skip ? Theme.faint : Theme.muted) }
                        }
                        .frame(width: 28, height: 28)
                        .shadow(color: cur ? Theme.accent.opacity(0.5) : .clear, radius: 7)
                        Rectangle().fill(i == steps.count - 1 ? .clear : (done || skip) ? Theme.ok : Theme.line2).frame(height: 2)
                    }
                    VStack(spacing: 2) {
                        Text(s.title).font(.system(size: 11.5)).foregroundStyle(cur ? Theme.text : Theme.muted)
                        if let note { Text(note).font(.system(size: 10.5)).foregroundStyle(Theme.faint) }
                    }
                    .multilineTextAlignment(.center).padding(.horizontal, 2)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .card(padding: 16)
    }
}

struct LogView: View {
    let lines: [LogLine]
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(lines) { l in
                        Text(l.text.isEmpty ? " " : l.text)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(color(l.kind))
                            .fontWeight(l.kind == .stop ? .bold : .regular)
                            .padding(.leading, l.kind == .answer ? 6 : 0)
                            .overlay(alignment: .leading) { if l.kind == .answer { Rectangle().fill(Theme.accent).frame(width: 2) } }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(l.id)
                    }
                }
                .textSelection(.enabled)
                .padding(12)
            }
            .frame(height: 340)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.016, green: 0.02, blue: 0.05).opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
            .onChange(of: lines.count) { _, _ in if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) } }
        }
    }
    func color(_ k: LogLine.Kind) -> Color {
        switch k {
        case .cmd: Theme.blue
        case .ok: Color(red: 0.61, green: 0.91, blue: 0.75)
        case .warn: Theme.warn
        case .stop: Theme.bad
        case .answer: .white
        case .info: Color(red: 0.77, green: 0.78, blue: 0.91)
        }
    }
}

struct PromptSheet: View {
    let prompt: Prompt
    @EnvironmentObject var m: AppModel
    @State private var typed = ""

    var danger: Bool { if case .word = prompt.kind { return true }; return false }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: danger ? "exclamationmark.triangle.fill" : "questionmark.circle.fill").font(.system(size: 22))
                    .foregroundStyle(danger ? Theme.bad : Theme.accent)
                Text(danger ? L("Подтвердите запись на проектор") : L("Установщик спрашивает")).font(.system(size: 18, weight: .semibold))
            }
            if !prompt.context.isEmpty {
                ScrollView {
                    Text(prompt.context.map { $0.replacingOccurrences(of: #"^\d\d:\d\d:\d\d\s+"#, with: "", options: .regularExpression) }.joined(separator: "\n"))
                        .font(.system(size: 13)).foregroundStyle(Color(red: 0.8, green: 0.82, blue: 0.94)).lineSpacing(2.5)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                .frame(maxHeight: 230)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.25)))
            }
            Text(prompt.question.replacingOccurrences(of: #"\s*\[(да/нет|yes/no)\]\s*$"#, with: "", options: .regularExpression))
                .font(.system(size: 15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                switch prompt.kind {
                case .yesNo:
                    Spacer()
                    Button(L("Нет")) { m.answer("нет") }.buttonStyle(LumenButton()).keyboardShortcut(.cancelAction)
                    Button(L("Да")) { m.answer("да") }.buttonStyle(LumenButton(kind: .primary)).keyboardShortcut(.defaultAction)
                case .word(let w):
                    Text(L("Введите %@:", "\(w)")).foregroundStyle(Theme.muted)
                    TextField(w, text: $typed).textFieldStyle(.roundedBorder).font(.system(size: 14, design: .monospaced)).frame(width: 160)
                        .onSubmit { if typed == w { m.answer(typed) } }
                    Spacer()
                    Button(L("Отмена")) { m.answer("no") }.buttonStyle(LumenButton()).keyboardShortcut(.cancelAction)
                    Button(L("Продолжить")) { m.answer(typed) }.buttonStyle(LumenButton(kind: .danger)).disabled(typed != w)
                case .enter:
                    Spacer()
                    Button(L("Готово")) { m.answer("") }.buttonStyle(LumenButton(kind: .primary)).keyboardShortcut(.defaultAction)
                case .text:
                    TextField("", text: $typed).textFieldStyle(.roundedBorder).onSubmit { m.answer(typed) }
                    Button(L("Ответить")) { m.answer(typed) }.buttonStyle(LumenButton(kind: .primary))
                }
            }
        }
        .padding(24)
        .frame(width: 620)
        .background(Color(red: 0.08, green: 0.1, blue: 0.22))
        .interactiveDismissDisabled()
    }
}
