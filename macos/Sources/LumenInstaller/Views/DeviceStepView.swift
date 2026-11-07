import SwiftUI

struct DeviceStepView: View {
    @EnvironmentObject var m: AppModel
    @State private var manualTab = 0

    /// Wi‑Fi (Play 6, Z9X HB) while no projector is found, and for a model that connects over Wi‑Fi.
    var showWifi: Bool { m.profile?.connection == .wifi || !m.deviceConnected }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Header(title: L("Подключите проектор"),
                   lead: L("Проектор с включённым ADB определится сам. Если нет, введите серийный номер или выберите модель."))

            if let e = m.scanError { Note(.bad, icon: "xmark.octagon", e) }

            if m.devices.isEmpty {
                VStack(spacing: 12) {
                    PulseView()
                    Text(L("Ищу проекторы…")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    if m.mode == .demo {
                        Text(L("Включите «Кабель USB» на панели демо-проектора справа."))
                            .font(.system(size: 13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 30).card()
            } else {
                ForEach(m.devices) { d in DeviceRow(device: d, selected: m.selectedDeviceID == d.id).onTapGesture { m.select(d) } }
            }

            if let p = m.profile, m.selectedDevice?.match == nil {
                Note(.ok, icon: "checkmark.circle", L("Модель выбрана вручную: %@ (%@).", p.name, p.model))
            }

            if showWifi {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Подключение по Wi-Fi")).font(.system(size: 15, weight: .semibold))
                    HStack {
                        TextField("192.168.1.50", text: $m.wifiAddr).textFieldStyle(.roundedBorder).frame(maxWidth: 240).onSubmit { m.connectWifi() }
                        Button(L("Подключить")) { m.connectWifi() }.buttonStyle(LumenButton(small: true))
                        Button(L("Найти в сети")) { m.findOnNetwork() }.buttonStyle(LumenButton(kind: .ghost, small: true))
                    }
                    if let w = m.wifiMessage { Text(w).font(.system(size: 12.5)).foregroundStyle(Theme.muted) }
                }
                .card()
            }

            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $manualTab) {
                    Text(L("По серийному номеру")).tag(0)
                    Text(L("Выбрать модель")).tag(1)
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)

                if manualTab == 0 {
                    Text(L("Серийный номер есть на наклейке снизу проектора и в разделе «Настройки → Об устройстве»."))
                        .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                    HStack {
                        TextField(L("например, XHN…"), text: $m.serialInput).textFieldStyle(.roundedBorder).frame(maxWidth: 240).onSubmit { m.identifySerial() }
                            .onChange(of: m.serialInput) { m.serialEdited() }
                        Button(L("Определить")) { m.identifySerial() }.buttonStyle(LumenButton(small: true))
                    }
                    if let s = m.serialMatch, let p = m.profiles.first(where: { $0.id == s.id }) {
                        Note(s.warn ? .warn : .ok, icon: s.warn ? "exclamationmark.triangle" : "checkmark.circle",
                             Text("\(p.name): \(s.detail)"))
                    } else if m.serialTried {
                        Note(.warn, icon: "questionmark.circle", L("%@: по этому номеру модель не определить. Выберите её из списка или подключите проектор.", m.serialInput.trimmingCharacters(in: .whitespaces).uppercased()))
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                        ForEach(m.profiles) { p in
                            let sel = m.profile?.id == p.id
                            Button { m.chooseManually(p.id) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(p.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                                    Text(L("модель %@ · прошивка %@", "\(p.model)", "\(p.firmware.joined(separator: ", "))")).font(.system(size: 12)).foregroundStyle(Theme.muted)
                                    Text(p.connection == .usb ? L("по кабелю USB") : L("по Wi-Fi + кабель для записи")).font(.system(size: 11.5)).foregroundStyle(Theme.faint)
                                }
                                .padding(13).frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12).fill(sel ? Theme.accent.opacity(0.07) : Color.white.opacity(0.03)))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(sel ? Theme.accent.opacity(0.6) : Theme.line))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .card()

            HStack {
                BackButton(to: .prepare)
                if !m.deviceConnected {
                    Label(L("Проектор не найден. Подключите его, чтобы продолжить."), systemImage: "cable.connector.slash")
                        .font(.system(size: 13)).foregroundStyle(Theme.warn)
                }
                Spacer()
                Button { m.step = .system; m.autoselectRelease(); if m.releases.isEmpty { m.loadReleases() } } label: {
                    HStack { Text(L("Дальше: система")); Image(systemName: "arrow.right") }
                }
                .buttonStyle(LumenButton(kind: .primary))
                .disabled(m.profile == nil || !m.deviceConnected)
            }
        }
    }
}

struct DeviceRow: View {
    let device: Device
    let selected: Bool
    @EnvironmentObject var m: AppModel

    var body: some View {
        let p = m.profiles.first { $0.id == device.match?.id }
        HStack(spacing: 16) {
            ProjectorGlyph().frame(width: 58, height: 44)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(p?.name ?? (device.state == "unauthorized" ? L("Устройство ждёт разрешения") : L("Неизвестное устройство")))
                        .font(.system(size: 15.5, weight: .semibold)).foregroundStyle(Theme.text)
                    if let s = device.hwSerial ?? Optional(device.serial) { Text(s).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.faint) }
                }
                FlowLayout(spacing: 6) {
                    Badge(text: device.transport == .usb ? "USB" : device.transport == .wifi ? "Wi-Fi \(device.serial)" : "fastboot", tone: .blue,
                          icon: device.transport == .wifi ? "wifi" : "cable.connector")
                    if let mt = device.match { Badge(text: L("определено %@", "\(mt.detail)"), tone: mt.warn ? .warn : .ok, icon: "sparkle.magnifyingglass") }
                    if let s = device.system { Badge(text: s, tone: device.lumen ? .ok : .plain) }
                    if let fw = device.firmware {
                        Badge(text: L("прошивка %@", "\(fw)"), tone: device.firmwareOk == false ? .bad : .plain,
                              icon: device.firmwareOk == false ? "xmark" : device.firmwareOk == true ? "checkmark" : nil)
                    }
                }
                if device.state == "unauthorized" {
                    Text(L("На проекторе появился запрос «Разрешить отладку?». Нажмите «Разрешить».")).font(.system(size: 12.5)).foregroundStyle(Theme.warn)
                } else if device.firmwareOk == false, let p {
                    Text(L("Эта прошивка XGIMI не подходит, нужна %@. Установщик не станет ставить систему.", "\(p.firmware.joined(separator: ", "))")).font(.system(size: 12.5)).foregroundStyle(Theme.bad)
                } else if device.match == nil, device.state == "device" {
                    Text(L("Это не поддерживаемый проектор XGIMI.")).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 20)).foregroundStyle(selected ? Theme.accent : Theme.line2)
        }
        .card(padding: 16, highlight: selected)
        .contentShape(Rectangle())
    }
}

struct ProjectorGlyph: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [Color(white: 0.27), Color(white: 0.15)], startPoint: .top, endPoint: .bottom))
                .frame(height: 34).offset(y: 4)
            Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.95, blue: 0.84), Color(white: 0.4)], center: .center, startRadius: 0, endRadius: 9))
                .frame(width: 18, height: 18).offset(y: 4)
            Circle().fill(Theme.ok).frame(width: 5, height: 5).offset(x: 20, y: 14).shadow(color: Theme.ok, radius: 3)
        }
    }
}

struct PulseView: View {
    @State private var on = false
    var body: some View {
        ZStack {
            Circle().strokeBorder(Theme.blue.opacity(0.5), lineWidth: 2)
            Circle().strokeBorder(Theme.blue.opacity(0.5), lineWidth: 2).scaleEffect(on ? 1.8 : 1).opacity(on ? 0 : 0.9)
            Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(Theme.blue)
        }
        .frame(width: 54, height: 54)
        .onAppear { withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { on = true } }
    }
}
